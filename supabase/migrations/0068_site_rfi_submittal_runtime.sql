begin;

alter table coordination.issues add column if not exists source_model_id uuid references cde.models(id) on delete set null;
alter table coordination.issues add column if not exists source_model_checksum text;
alter table coordination.issues add column if not exists source_document_id uuid references cde.documents(id) on delete set null;
alter table coordination.issues add column if not exists source_document_version_id uuid references cde.file_versions(id) on delete set null;
alter table coordination.issues add column if not exists source_document_checksum text;
create index if not exists issues_source_model_idx on coordination.issues(source_model_id) where source_model_id is not null;
create index if not exists issues_source_document_idx on coordination.issues(source_document_id) where source_document_id is not null;

create table if not exists site.technical_submittals(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  submittal_number text not null,
  title text not null,
  category text not null,
  revision integer not null default 1,
  parent_submittal_id uuid references site.technical_submittals(id) on delete set null,
  source_model_id uuid references cde.models(id) on delete set null,
  source_model_checksum text,
  source_document_id uuid references cde.documents(id) on delete set null,
  source_document_version_id uuid references cde.file_versions(id) on delete set null,
  source_document_checksum text,
  location_ref text,
  submission_refs jsonb not null default '[]'::jsonb,
  review_evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check(status in ('draft','submitted','review','approved','rejected','superseded')),
  submitted_by uuid references auth.users(id),
  submitted_at timestamptz,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  review_note text,
  decision_hash text,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,submittal_number,revision)
);
create index if not exists technical_submittals_project_status_idx on site.technical_submittals(project_id,status,created_at desc);
alter table site.technical_submittals enable row level security;
drop policy if exists technical_submittals_read on site.technical_submittals;
create policy technical_submittals_read on site.technical_submittals for select to authenticated using(project.can_access_project(project_id));
drop policy if exists technical_submittals_insert on site.technical_submittals;
create policy technical_submittals_insert on site.technical_submittals for insert to authenticated with check(project.can_access_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.site_phase',true) in ('submittal_create','submittal_revise'));
drop policy if exists technical_submittals_update on site.technical_submittals;
create policy technical_submittals_update on site.technical_submittals for update to authenticated using(project.can_access_project(project_id)) with check(
  (current_setting('conceptspaces.site_phase',true)='submittal_submit' and submitted_by=auth.uid() and status='submitted')
  or (current_setting('conceptspaces.site_phase',true)='submittal_review' and project.can_manage_project(project_id))
  or (current_setting('conceptspaces.site_phase',true)='submittal_revise' and project.can_access_project(project_id))
);
grant select,insert,update on site.technical_submittals to authenticated;

create or replace function public.create_site_rfi(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,coordination,cde,project,audit,auth,pg_temp
as $$
declare issue_id uuid; issue_row coordination.issues%rowtype; model_row cde.models%rowtype; doc_row cde.documents%rowtype; version_row cde.file_versions%rowtype; model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid; document_id_value uuid:=nullif(input_payload->>'document_id','')::uuid; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'question'),'') is null then raise exception 'rfi_title_question_required'; end if;
  if model_id_value is null and document_id_value is null then raise exception 'rfi_precise_model_or_document_link_required'; end if;
  if model_id_value is not null then
    select * into model_row from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued');
    if not found then raise exception 'rfi_current_model_required'; end if;
  end if;
  if document_id_value is not null then
    select * into doc_row from cde.documents where id=document_id_value and project_id=target_project_id and status in ('approved','issued') and current_version_id is not null;
    if not found then raise exception 'rfi_current_document_required'; end if;
    select * into version_row from cde.file_versions where id=doc_row.current_version_id;
    if not found then raise exception 'rfi_document_version_required'; end if;
  end if;
  issue_id:=public.create_coordination_issue(jsonb_build_object(
    'project_id',target_project_id,'issue_type','rfi','title',btrim(input_payload->>'title'),'description',btrim(input_payload->>'question'),
    'priority',coalesce(nullif(lower(btrim(input_payload->>'priority')),''),'medium'),'criticality',coalesce(nullif(upper(btrim(input_payload->>'criticality')),''),'C1'),
    'due_at',input_payload->>'due_at','location_ref',input_payload->>'location_ref','bcf_topic_ref',input_payload->>'model_object_ref'
  ));
  perform set_config('conceptspaces.coordination_phase','raise',true);
  if model_id_value is not null then insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id,'model',model_id_value,'rfi_source') on conflict do nothing; end if;
  if document_id_value is not null then insert into coordination.issue_links(issue_id,resource_type,resource_id,relationship) values(issue_id,'document',document_id_value,'rfi_source') on conflict do nothing; end if;
  update coordination.issues set source_model_id=model_id_value,source_model_checksum=model_row.checksum,source_document_id=document_id_value,source_document_version_id=doc_row.current_version_id,source_document_checksum=version_row.checksum where id=issue_id returning * into issue_row;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'site.rfi.opened','issue',issue_id,null,to_jsonb(issue_row),null,gen_random_uuid());
  return issue_id;
end;$$;
revoke all on function public.create_site_rfi(uuid,jsonb) from public,anon; grant execute on function public.create_site_rfi(uuid,jsonb) to authenticated;

create or replace function public.answer_site_rfi(target_issue_id uuid,target_response text,target_evidence_refs jsonb)
returns text
language plpgsql security invoker
set search_path=public,coordination,project,audit,auth,pg_temp
as $$
declare issue_row coordination.issues%rowtype; before_state jsonb; org_id uuid;
begin
  select * into issue_row from coordination.issues where id=target_issue_id for update;
  if not found or issue_row.issue_type<>'rfi' then raise exception 'rfi_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(issue_row.project_id) then raise exception 'rfi_response_authority_required'; end if;
  if issue_row.status not in ('open','in_progress') then raise exception 'rfi_not_answerable'; end if;
  if nullif(btrim(target_response),'') is null or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0 then raise exception 'rfi_response_evidence_required'; end if;
  before_state:=to_jsonb(issue_row);
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(issue_row.id,btrim(target_response),auth.uid(),target_evidence_refs);
  update coordination.issues set status='answered',updated_at=now() where id=issue_row.id returning * into issue_row;
  select organisation_id into org_id from project.projects where id=issue_row.project_id;
  perform audit.append_event(org_id,issue_row.project_id,'site.rfi.answered','issue',issue_row.id,before_state,to_jsonb(issue_row),target_response,gen_random_uuid());
  return issue_row.status;
end;$$;
revoke all on function public.answer_site_rfi(uuid,text,jsonb) from public,anon; grant execute on function public.answer_site_rfi(uuid,text,jsonb) to authenticated;

create or replace function public.close_site_rfi(target_issue_id uuid,target_verification_note text)
returns text
language plpgsql security invoker
set search_path=public,coordination,project,audit,auth,pg_temp
as $$
declare issue_row coordination.issues%rowtype; before_state jsonb; org_id uuid;
begin
  select * into issue_row from coordination.issues where id=target_issue_id for update;
  if not found or issue_row.issue_type<>'rfi' then raise exception 'rfi_not_found'; end if;
  if auth.uid() is null or not project.can_manage_project(issue_row.project_id) then raise exception 'rfi_close_authority_required'; end if;
  if issue_row.status<>'answered' or nullif(btrim(target_verification_note),'') is null then raise exception 'answered_rfi_verification_required'; end if;
  before_state:=to_jsonb(issue_row);
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(issue_row.id,btrim(target_verification_note),auth.uid(),'[]'::jsonb);
  update coordination.issues set status='closed',closed_at=now(),updated_at=now() where id=issue_row.id returning * into issue_row;
  select organisation_id into org_id from project.projects where id=issue_row.project_id;
  perform audit.append_event(org_id,issue_row.project_id,'site.rfi.closed','issue',issue_row.id,before_state,to_jsonb(issue_row),target_verification_note,gen_random_uuid());
  return issue_row.status;
end;$$;
revoke all on function public.close_site_rfi(uuid,text) from public,anon; grant execute on function public.close_site_rfi(uuid,text) to authenticated;

create or replace function public.create_technical_submittal(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,site,cde,project,audit,auth,pg_temp
as $$
declare s site.technical_submittals%rowtype; m cde.models%rowtype; d cde.documents%rowtype; fv cde.file_versions%rowtype; model_id_value uuid:=nullif(input_payload->>'model_id','')::uuid; document_id_value uuid:=nullif(input_payload->>'document_id','')::uuid; org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  if nullif(btrim(input_payload->>'submittal_number'),'') is null or nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'category'),'') is null then raise exception 'submittal_identity_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'submission_refs','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'submission_refs','[]'::jsonb))=0 then raise exception 'submittal_evidence_required'; end if;
  if model_id_value is not null then select * into m from cde.models where id=model_id_value and project_id=target_project_id and status in ('approved','issued'); if not found then raise exception 'submittal_current_model_required'; end if; end if;
  if document_id_value is not null then select * into d from cde.documents where id=document_id_value and project_id=target_project_id and status in ('approved','issued') and current_version_id is not null; if not found then raise exception 'submittal_current_document_required'; end if; select * into fv from cde.file_versions where id=d.current_version_id; end if;
  perform set_config('conceptspaces.site_phase','submittal_create',true);
  insert into site.technical_submittals(project_id,submittal_number,title,category,revision,source_model_id,source_model_checksum,source_document_id,source_document_version_id,source_document_checksum,location_ref,submission_refs,status,created_by)
  values(target_project_id,upper(btrim(input_payload->>'submittal_number')),btrim(input_payload->>'title'),lower(btrim(input_payload->>'category')),1,model_id_value,m.checksum,document_id_value,d.current_version_id,fv.checksum,nullif(btrim(input_payload->>'location_ref'),''),input_payload->'submission_refs','draft',auth.uid()) returning * into s;
  select organisation_id into org_id from project.projects where id=target_project_id; perform audit.append_event(org_id,target_project_id,'site.submittal.created','technical_submittal',s.id,null,to_jsonb(s),null,gen_random_uuid()); return s.id;
end;$$;
revoke all on function public.create_technical_submittal(uuid,jsonb) from public,anon; grant execute on function public.create_technical_submittal(uuid,jsonb) to authenticated;

create or replace function public.submit_technical_submittal(target_submittal_id uuid)
returns text
language plpgsql security invoker
set search_path=public,site,cde,project,audit,auth,pg_temp
as $$
declare s site.technical_submittals%rowtype; before_state jsonb; m cde.models%rowtype; d cde.documents%rowtype; fv cde.file_versions%rowtype; org_id uuid;
begin
  select * into s from site.technical_submittals where id=target_submittal_id for update; if not found or auth.uid() is null or not project.can_access_project(s.project_id) then raise exception 'submittal_access_required'; end if;
  if s.status<>'draft' or jsonb_array_length(s.submission_refs)=0 then raise exception 'submittal_not_ready'; end if;
  if s.source_model_id is not null then select * into m from cde.models where id=s.source_model_id; if m.checksum is distinct from s.source_model_checksum or m.status not in ('approved','issued') then raise exception 'submittal_model_source_stale'; end if; end if;
  if s.source_document_id is not null then select * into d from cde.documents where id=s.source_document_id; select * into fv from cde.file_versions where id=d.current_version_id; if d.current_version_id is distinct from s.source_document_version_id or fv.checksum is distinct from s.source_document_checksum then raise exception 'submittal_document_source_stale'; end if; end if;
  before_state:=to_jsonb(s); perform set_config('conceptspaces.site_phase','submittal_submit',true);
  update site.technical_submittals set status='submitted',submitted_by=auth.uid(),submitted_at=now(),updated_at=now() where id=s.id returning * into s;
  select organisation_id into org_id from project.projects where id=s.project_id; perform audit.append_event(org_id,s.project_id,'site.submittal.submitted','technical_submittal',s.id,before_state,to_jsonb(s),null,gen_random_uuid()); return s.status;
end;$$;
revoke all on function public.submit_technical_submittal(uuid) from public,anon; grant execute on function public.submit_technical_submittal(uuid) to authenticated;

create or replace function public.review_technical_submittal(target_submittal_id uuid,target_decision text,target_note text,target_evidence_refs jsonb)
returns text
language plpgsql security invoker
set search_path=public,site,project,audit,extensions,auth,pg_temp
as $$
declare s site.technical_submittals%rowtype; before_state jsonb; decision_value text:=lower(btrim(target_decision)); hash_value text; org_id uuid;
begin
  select * into s from site.technical_submittals where id=target_submittal_id for update; if not found or auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'submittal_review_authority_required'; end if;
  if s.status not in ('submitted','review') or decision_value not in ('review','approved','rejected') then raise exception 'submittal_review_state_invalid'; end if;
  if decision_value in ('approved','rejected') and (nullif(btrim(target_note),'') is null or jsonb_typeof(coalesce(target_evidence_refs,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(target_evidence_refs,'[]'::jsonb))=0) then raise exception 'submittal_decision_evidence_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('submittal_id',s.id,'revision',s.revision,'source_model_checksum',s.source_model_checksum,'source_document_checksum',s.source_document_checksum,'submission_refs',s.submission_refs,'decision',decision_value,'note',target_note,'evidence',coalesce(target_evidence_refs,'[]'::jsonb))::text,'sha256'),'hex');
  before_state:=to_jsonb(s); perform set_config('conceptspaces.site_phase','submittal_review',true);
  update site.technical_submittals set status=decision_value,reviewed_by=case when decision_value in ('approved','rejected') then auth.uid() else reviewed_by end,reviewed_at=case when decision_value in ('approved','rejected') then now() else reviewed_at end,review_note=target_note,review_evidence_refs=coalesce(target_evidence_refs,'[]'::jsonb),decision_hash=case when decision_value in ('approved','rejected') then hash_value else decision_hash end,updated_at=now() where id=s.id returning * into s;
  select organisation_id into org_id from project.projects where id=s.project_id; perform audit.append_event(org_id,s.project_id,'site.submittal.'||decision_value,'technical_submittal',s.id,before_state,to_jsonb(s),target_note,gen_random_uuid()); return s.status;
end;$$;
revoke all on function public.review_technical_submittal(uuid,text,text,jsonb) from public,anon; grant execute on function public.review_technical_submittal(uuid,text,text,jsonb) to authenticated;

create or replace function public.list_site_delivery_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,site,coordination,project,cost,procurement,cde,pg_temp
as $$
declare org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  return jsonb_build_object(
    'organisation_id',org_id,
    'activities',coalesce((select jsonb_agg(to_jsonb(a) order by a.wbs_code) from site.activities a where a.project_id=target_project_id),'[]'::jsonb),
    'diaries',coalesce((select jsonb_agg(to_jsonb(d) order by d.diary_date desc) from site.site_diaries d where d.project_id=target_project_id),'[]'::jsonb),
    'observations',coalesce((select jsonb_agg(to_jsonb(o) order by o.observed_at desc) from site.observations o where o.project_id=target_project_id),'[]'::jsonb),
    'rfis',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from coordination.issues i where i.project_id=target_project_id and i.issue_type='rfi'),'[]'::jsonb),
    'submittals',coalesce((select jsonb_agg(to_jsonb(s) order by s.created_at desc) from site.technical_submittals s where s.project_id=target_project_id),'[]'::jsonb),
    'itps',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from public.inspection_test_plans i where i.project_id=target_project_id),'[]'::jsonb),
    'inspections',coalesce((select jsonb_agg(to_jsonb(i) order by i.inspected_at desc) from public.inspection_records i where i.project_id=target_project_id),'[]'::jsonb),
    'ncrs',coalesce((select jsonb_agg(to_jsonb(n) order by n.created_at desc) from public.non_conformances n where n.project_id=target_project_id),'[]'::jsonb),
    'measurements',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at desc) from site.progress_measurements m where m.project_id=target_project_id),'[]'::jsonb),
    'claims',coalesce((select jsonb_agg(to_jsonb(c) order by c.period_to desc,c.created_at desc) from public.progress_claims c where c.project_id=target_project_id),'[]'::jsonb),
    'variations',coalesce((select jsonb_agg(to_jsonb(v) order by v.created_at desc) from site.variations v where v.project_id=target_project_id),'[]'::jsonb),
    'offline_packages',coalesce((select jsonb_agg(to_jsonb(p) order by p.downloaded_at desc) from site.offline_packages p where p.project_id=target_project_id and (p.user_id=auth.uid() or project.can_manage_project(target_project_id))),'[]'::jsonb),
    'approved_boq_lines',coalesce((select jsonb_agg(to_jsonb(b) order by b.code) from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id where cp.project_id=target_project_id and cp.status='approved'),'[]'::jsonb),
    'purchase_orders',coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at desc) from procurement.purchase_orders po where po.project_id=target_project_id and po.status in ('approved','issued','delivering','closed')),'[]'::jsonb),
    'vendors',coalesce((select jsonb_agg(to_jsonb(v) order by v.legal_name) from procurement.vendors v where v.organisation_id=org_id and v.status='active'),'[]'::jsonb),
    'approved_models',coalesce((select jsonb_agg(to_jsonb(m) order by m.updated_at desc) from cde.models m where m.project_id=target_project_id and m.status in ('approved','issued')),'[]'::jsonb),
    'approved_documents',coalesce((select jsonb_agg(to_jsonb(d) order by d.updated_at desc) from cde.documents d where d.project_id=target_project_id and d.status in ('approved','issued') and d.current_version_id is not null),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_site_delivery_workspace(uuid) from public,anon; grant execute on function public.list_site_delivery_workspace(uuid) to authenticated;

commit;
