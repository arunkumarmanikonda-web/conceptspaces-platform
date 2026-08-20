begin;

grant usage on schema cde to authenticated;
grant select,insert,update,delete on cde.documents,cde.file_versions,cde.models,cde.transmittals,cde.transmittal_items to authenticated;

alter table coordination.approval_requests add column if not exists decided_by uuid references auth.users(id);
create index if not exists approval_requests_decided_by_idx on coordination.approval_requests(decided_by) where decided_by is not null;

create policy documents_operate_insert on cde.documents for insert to authenticated
with check (project.can_manage_project(project_id) and authored_by=(select auth.uid()) and cde_state='work_in_progress' and status='draft');
create policy documents_operate_update on cde.documents for update to authenticated
using (project.can_manage_project(project_id)) with check (project.can_manage_project(project_id));
create policy documents_operate_delete on cde.documents for delete to authenticated
using (project.can_manage_project(project_id) and cde_state='work_in_progress' and status='draft' and current_version_id is null);
create policy file_versions_operate_insert on cde.file_versions for insert to authenticated
with check (created_by=(select auth.uid()) and exists(select 1 from cde.documents d where d.id=document_id and project.can_manage_project(d.project_id)));
create policy models_operate_insert on cde.models for insert to authenticated
with check (created_by=(select auth.uid()) and project.can_manage_project(project_id));
create policy models_operate_update on cde.models for update to authenticated
using (project.can_manage_project(project_id)) with check (project.can_manage_project(project_id));
create policy transmittals_operate_insert on cde.transmittals for insert to authenticated
with check (sender_id=(select auth.uid()) and project.can_manage_project(project_id));
create policy transmittals_operate_update on cde.transmittals for update to authenticated
using (project.can_manage_project(project_id)) with check (project.can_manage_project(project_id));
create policy transmittal_items_operate_insert on cde.transmittal_items for insert to authenticated
with check (exists(select 1 from cde.transmittals t where t.id=transmittal_id and project.can_manage_project(t.project_id)));

create or replace function public.decide_governed_approval(
  target_approval_id uuid,new_decision text,decision_comments text,reviewed_resource_hash text
)
returns void
language plpgsql
security invoker
set search_path = coordination, project, core, audit, public
as $$
declare
  a coordination.approval_requests%rowtype;
  org_id uuid;
  before_state jsonb;
  decision_value text := lower(btrim(new_decision));
  role_ok boolean := false;
begin
  if decision_value not in ('approved','approved_with_comments','rejected') then raise exception 'unsupported_approval_decision'; end if;
  select * into a from coordination.approval_requests where id=target_approval_id for update;
  if not found then raise exception 'approval_not_found'; end if;
  if a.decision <> 'pending' then raise exception 'approval_already_decided'; end if;
  if not project.can_access_project(a.project_id) then raise exception 'project_access_required'; end if;
  if a.requested_by=auth.uid() and a.criticality in ('C2','C3','C4') then raise exception 'maker_cannot_approve_own_controlled_action'; end if;
  if a.requested_from is not null and a.requested_from<>auth.uid() then raise exception 'approval_not_assigned_to_current_user'; end if;
  if nullif(btrim(reviewed_resource_hash),'') is null then raise exception 'reviewed_resource_hash_required'; end if;

  if a.role_required is null then
    role_ok := true;
  else
    role_ok := exists(
      select 1 from project.project_members pm
      where pm.project_id=a.project_id and pm.user_id=auth.uid()
        and pm.status='active' and pm.role_code=a.role_required
    ) or exists(
      select 1 from project.projects p
      where p.id=a.project_id
        and core.has_org_role(p.organisation_id,array[a.role_required,'super_admin','org_admin'])
    );
  end if;
  if not role_ok then raise exception 'approval_role_authority_required'; end if;

  if a.criticality in ('C3','C4') then
    if a.role_required not in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') then
      raise exception 'professional_role_required_for_c3_c4';
    end if;
    if not core.has_verified_professional_eligibility(auth.uid(),a.role_required) then
      raise exception 'verified_professional_eligibility_required';
    end if;
  end if;

  select organisation_id into org_id from project.projects where id=a.project_id;
  before_state := to_jsonb(a);
  update coordination.approval_requests
  set decision=decision_value,comments=decision_comments,decided_at=now(),decided_by=auth.uid(),
      decision_evidence_hash=btrim(reviewed_resource_hash)
  where id=a.id returning * into a;
  perform audit.append_event(org_id,a.project_id,'approval.'||decision_value,'approval_request',a.id,before_state,to_jsonb(a),decision_comments,gen_random_uuid());
end;
$$;
revoke all on function public.decide_governed_approval(uuid,text,text,text) from public,anon;
grant execute on function public.decide_governed_approval(uuid,text,text,text) to authenticated;

create or replace function public.register_cde_document(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  d cde.documents%rowtype;
  org_id uuid;
begin
  if project_id_value is null or not project.can_manage_project(project_id_value) then raise exception 'project_manage_authority_required'; end if;
  if nullif(btrim(input_payload->>'document_number'),'') is null or nullif(btrim(input_payload->>'title'),'') is null then raise exception 'document_number_and_title_required'; end if;
  select organisation_id into org_id from project.projects where id=project_id_value;
  insert into cde.documents(project_id,document_number,title,discipline,document_type,cde_state,status,revision,scale,authored_by,metadata)
  values(project_id_value,upper(btrim(input_payload->>'document_number')),btrim(input_payload->>'title'),
    coalesce(nullif(upper(btrim(input_payload->>'discipline')),''),'GEN'),coalesce(nullif(lower(btrim(input_payload->>'document_type')),''),'document'),
    'work_in_progress','draft',coalesce(nullif(upper(btrim(input_payload->>'revision')),''),'P01'),nullif(btrim(input_payload->>'scale'),''),auth.uid(),coalesce(input_payload->'metadata','{}'::jsonb))
  returning * into d;
  perform audit.append_event(org_id,project_id_value,'cde.document.registered','document',d.id,null,to_jsonb(d),null,gen_random_uuid());
  return d.id;
end;
$$;
revoke all on function public.register_cde_document(jsonb) from public,anon;
grant execute on function public.register_cde_document(jsonb) to authenticated;

create or replace function public.discard_empty_cde_document(target_document_id uuid)
returns void
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare d cde.documents%rowtype; org_id uuid;
begin
  select * into d from cde.documents where id=target_document_id for update;
  if not found then return; end if;
  if not project.can_manage_project(d.project_id) then raise exception 'project_manage_authority_required'; end if;
  if d.current_version_id is not null or d.cde_state<>'work_in_progress' or d.status<>'draft' then raise exception 'document_not_discardable'; end if;
  select organisation_id into org_id from project.projects where id=d.project_id;
  delete from cde.documents where id=d.id;
  perform audit.append_event(org_id,d.project_id,'cde.document.discarded','document',d.id,to_jsonb(d),null,'Empty WIP shell discarded',gen_random_uuid());
end;
$$;
revoke all on function public.discard_empty_cde_document(uuid) from public,anon;
grant execute on function public.discard_empty_cde_document(uuid) to authenticated;

create or replace function public.register_cde_file_version(
  target_document_id uuid,object_key text,mime_type text,size_bytes bigint,checksum_sha256 text
)
returns jsonb
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare
  d cde.documents%rowtype;
  v cde.file_versions%rowtype;
  org_id uuid;
  next_version integer;
begin
  select * into d from cde.documents where id=target_document_id for update;
  if not found then raise exception 'document_not_found'; end if;
  if not project.can_manage_project(d.project_id) then raise exception 'project_manage_authority_required'; end if;
  if d.cde_state in ('published','archived') or d.status in ('issued','superseded','withdrawn') then raise exception 'immutable_document_state_requires_new_revision'; end if;
  if object_key not like d.project_id::text||'/documents/'||d.id::text||'/%' then raise exception 'invalid_document_storage_path'; end if;
  if checksum_sha256 !~ '^[0-9a-fA-F]{64}$' then raise exception 'sha256_checksum_required'; end if;
  if size_bytes<0 then raise exception 'invalid_file_size'; end if;
  select coalesce(max(version),0)+1 into next_version from cde.file_versions where document_id=d.id;
  insert into cde.file_versions(document_id,version,object_key,mime_type,size_bytes,checksum,created_by)
  values(d.id,next_version,object_key,coalesce(nullif(btrim(mime_type),''),'application/octet-stream'),size_bytes,lower(checksum_sha256),auth.uid()) returning * into v;
  update cde.documents set current_version_id=v.id,updated_at=now() where id=d.id;
  select organisation_id into org_id from project.projects where id=d.project_id;
  perform audit.append_event(org_id,d.project_id,'cde.file_version.registered','file_version',v.id,null,to_jsonb(v),null,gen_random_uuid());
  return jsonb_build_object('version_id',v.id,'version',v.version,'checksum',v.checksum);
end;
$$;
revoke all on function public.register_cde_file_version(uuid,text,text,bigint,text) from public,anon;
grant execute on function public.register_cde_file_version(uuid,text,text,bigint,text) to authenticated;

create or replace function public.transition_cde_document(
  target_document_id uuid,target_status text,target_cde_state text,evidence_note text default null
)
returns void
language plpgsql
security invoker
set search_path=cde,project,coordination,audit,public
as $$
declare
  d cde.documents%rowtype;
  v cde.file_versions%rowtype;
  a coordination.approval_requests%rowtype;
  before_state jsonb;
  org_id uuid;
  status_value text:=lower(btrim(target_status));
  state_value text:=lower(btrim(target_cde_state));
begin
  select * into d from cde.documents where id=target_document_id for update;
  if not found then raise exception 'document_not_found'; end if;
  if not project.can_manage_project(d.project_id) then raise exception 'project_manage_authority_required'; end if;
  if d.current_version_id is null then raise exception 'document_version_required'; end if;
  select * into v from cde.file_versions where id=d.current_version_id;
  if status_value not in ('draft','for_review','for_approval','approved','issued','superseded','withdrawn') then raise exception 'unsupported_document_status'; end if;
  if state_value not in ('work_in_progress','shared','published','archived') then raise exception 'unsupported_cde_state'; end if;
  if d.cde_state='archived' or d.status in ('issued','superseded','withdrawn') then raise exception 'terminal_document_state'; end if;
  if state_value='published' or status_value in ('approved','issued') then
    select * into a from coordination.approval_requests
    where project_id=d.project_id and resource_type='document' and resource_id=d.id
      and decision in ('approved','approved_with_comments') and decision_evidence_hash=v.checksum
    order by decided_at desc limit 1;
    if not found or a.decided_by is null then raise exception 'matching_approved_resource_hash_required'; end if;
  end if;
  if status_value='issued' and state_value<>'published' then raise exception 'issued_document_must_be_published'; end if;
  before_state:=to_jsonb(d);
  update cde.documents
  set status=status_value,cde_state=state_value,
      checked_by=case when status_value in ('for_approval','approved','issued') then coalesce(checked_by,auth.uid()) else checked_by end,
      approved_by=case when status_value in ('approved','issued') then a.decided_by else approved_by end,
      updated_at=now()
  where id=d.id returning * into d;
  select organisation_id into org_id from project.projects where id=d.project_id;
  perform audit.append_event(org_id,d.project_id,'cde.document.transition','document',d.id,before_state,to_jsonb(d),evidence_note,gen_random_uuid());
end;
$$;
revoke all on function public.transition_cde_document(uuid,text,text,text) from public,anon;
grant execute on function public.transition_cde_document(uuid,text,text,text) to authenticated;

create or replace function public.register_cde_model(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  m cde.models%rowtype;
  org_id uuid;
  fmt text:=lower(btrim(input_payload->>'format'));
  object_key_value text:=btrim(input_payload->>'object_key');
begin
  if project_id_value is null or not project.can_manage_project(project_id_value) then raise exception 'project_manage_authority_required'; end if;
  if fmt not in ('ifc','dwg','dxf','rvt','nwd','nwc','pdf','gbxml','json') then raise exception 'unsupported_model_format'; end if;
  if nullif(object_key_value,'') is null or object_key_value not like project_id_value::text||'/models/%' then raise exception 'invalid_model_storage_path'; end if;
  if coalesce(input_payload->>'checksum','') !~ '^[0-9a-fA-F]{64}$' then raise exception 'sha256_checksum_required'; end if;
  if nullif(btrim(input_payload->>'model_name'),'') is null then raise exception 'model_name_required'; end if;
  insert into cde.models(project_id,discipline,model_name,format,schema_version,object_key,checksum,coordinate_system,status,created_by)
  values(project_id_value,coalesce(nullif(upper(btrim(input_payload->>'discipline')),''),'GEN'),btrim(input_payload->>'model_name'),fmt,
    nullif(btrim(input_payload->>'schema_version'),''),object_key_value,lower(input_payload->>'checksum'),nullif(btrim(input_payload->>'coordinate_system'),''),'draft',auth.uid()) returning * into m;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'cde.model.registered','model',m.id,null,to_jsonb(m),null,gen_random_uuid());
  return m.id;
end;
$$;
revoke all on function public.register_cde_model(jsonb) from public,anon;
grant execute on function public.register_cde_model(jsonb) to authenticated;

create or replace function public.create_cde_transmittal(input_payload jsonb,document_ids uuid[] default '{}'::uuid[],model_ids uuid[] default '{}'::uuid[])
returns uuid
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  t cde.transmittals%rowtype;
  item_id uuid;
  org_id uuid;
  n text;
  purpose_value text:=coalesce(nullif(lower(btrim(input_payload->>'purpose')),''),'information');
begin
  if project_id_value is null or not project.can_manage_project(project_id_value) then raise exception 'project_manage_authority_required'; end if;
  if purpose_value not in ('information','review','approval','construction','record') then raise exception 'unsupported_transmittal_purpose'; end if;
  n:=coalesce(nullif(upper(btrim(input_payload->>'transmittal_number')),''),'TR-'||to_char(now(),'YYYYMMDDHH24MISS'));
  insert into cde.transmittals(project_id,transmittal_number,sender_id,recipient_refs,message,acknowledgement_required)
  values(project_id_value,n,auth.uid(),coalesce(input_payload->'recipient_refs','[]'::jsonb),nullif(btrim(input_payload->>'message'),''),coalesce((input_payload->>'acknowledgement_required')::boolean,false)) returning * into t;
  foreach item_id in array coalesce(document_ids,'{}'::uuid[]) loop
    if not exists(select 1 from cde.documents d where d.id=item_id and d.project_id=project_id_value and d.current_version_id is not null and d.cde_state in ('shared','published')) then raise exception 'transmittal_document_not_shareable'; end if;
    insert into cde.transmittal_items(transmittal_id,document_id,purpose) values(t.id,item_id,purpose_value);
  end loop;
  foreach item_id in array coalesce(model_ids,'{}'::uuid[]) loop
    if not exists(select 1 from cde.models m where m.id=item_id and m.project_id=project_id_value and m.status not in ('withdrawn','superseded')) then raise exception 'transmittal_model_not_shareable'; end if;
    insert into cde.transmittal_items(transmittal_id,model_id,purpose) values(t.id,item_id,purpose_value);
  end loop;
  select organisation_id into org_id from project.projects where id=project_id_value;
  perform audit.append_event(org_id,project_id_value,'cde.transmittal.created','transmittal',t.id,null,to_jsonb(t),null,gen_random_uuid());
  return t.id;
end;
$$;
revoke all on function public.create_cde_transmittal(jsonb,uuid[],uuid[]) from public,anon;
grant execute on function public.create_cde_transmittal(jsonb,uuid[],uuid[]) to authenticated;

create or replace function public.issue_cde_transmittal(target_transmittal_id uuid)
returns void
language plpgsql
security invoker
set search_path=cde,project,audit,public
as $$
declare t cde.transmittals%rowtype; org_id uuid;
begin
  select * into t from cde.transmittals where id=target_transmittal_id for update;
  if not found then raise exception 'transmittal_not_found'; end if;
  if not project.can_manage_project(t.project_id) then raise exception 'project_manage_authority_required'; end if;
  if t.issued_at is not null then raise exception 'transmittal_already_issued'; end if;
  if not exists(select 1 from cde.transmittal_items i where i.transmittal_id=t.id) then raise exception 'transmittal_item_required'; end if;
  update cde.transmittals set issued_at=now() where id=t.id returning * into t;
  select organisation_id into org_id from project.projects where id=t.project_id;
  perform audit.append_event(org_id,t.project_id,'cde.transmittal.issued','transmittal',t.id,null,to_jsonb(t),null,gen_random_uuid());
end;
$$;
revoke all on function public.issue_cde_transmittal(uuid) from public,anon;
grant execute on function public.issue_cde_transmittal(uuid) to authenticated;

create or replace function public.list_project_cde(target_project_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path=cde,project,public
as $$
  select case when project.can_access_project(target_project_id) then jsonb_build_object(
    'documents',coalesce((select jsonb_agg(jsonb_build_object(
      'id',d.id,'document_number',d.document_number::text,'title',d.title,'discipline',d.discipline,'document_type',d.document_type,
      'cde_state',d.cde_state,'status',d.status,'revision',d.revision,'current_version_id',d.current_version_id,
      'current_version',(select jsonb_build_object('id',v.id,'version',v.version,'object_key',v.object_key,'mime_type',v.mime_type,'size_bytes',v.size_bytes,'checksum',v.checksum,'created_at',v.created_at) from cde.file_versions v where v.id=d.current_version_id),
      'updated_at',d.updated_at
    ) order by d.document_number,d.revision) from cde.documents d where d.project_id=target_project_id),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from cde.models m where m.project_id=target_project_id),'[]'::jsonb),
    'transmittals',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'transmittal_number',t.transmittal_number::text,'message',t.message,'issued_at',t.issued_at,'created_at',t.created_at,'item_count',(select count(*) from cde.transmittal_items i where i.transmittal_id=t.id)) order by t.created_at desc) from cde.transmittals t where t.project_id=target_project_id),'[]'::jsonb)
  ) else jsonb_build_object('documents','[]'::jsonb,'models','[]'::jsonb,'transmittals','[]'::jsonb) end;
$$;
revoke all on function public.list_project_cde(uuid) from public,anon;
grant execute on function public.list_project_cde(uuid) to authenticated;

commit;
