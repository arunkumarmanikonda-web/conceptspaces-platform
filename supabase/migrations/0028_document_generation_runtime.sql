begin;

alter table public.project_report_snapshots add column if not exists snapshot_payload jsonb not null default '{}'::jsonb;
create index if not exists project_report_snapshots_project_created_idx on public.project_report_snapshots(project_id,created_at desc);
create index if not exists generation_jobs_requested_by_idx on public.generation_jobs(requested_by) where requested_by is not null;
create index if not exists generated_artifacts_job_idx on public.generated_artifacts(generation_job_id);

-- Runtime provenance is read through existing governed SELECT policies/RPCs, but it
-- cannot be authored directly by authenticated sessions. All writes below pass
-- through fixed RPC contracts with explicit actor/project checks.
grant select on public.document_templates,public.template_versions,public.project_report_snapshots,public.generation_jobs,public.generated_artifacts,public.publication_sets,public.publication_set_items to authenticated;
revoke insert,update,delete on public.document_templates,public.template_versions,public.project_report_snapshots,public.generation_jobs,public.generated_artifacts from authenticated;

drop policy if exists document_templates_runtime_insert on public.document_templates;
drop policy if exists template_versions_runtime_insert on public.template_versions;
drop policy if exists project_report_snapshots_runtime_insert on public.project_report_snapshots;
drop policy if exists generation_jobs_runtime_insert on public.generation_jobs;
drop policy if exists generation_jobs_runtime_update on public.generation_jobs;
drop policy if exists generated_artifacts_runtime_insert on public.generated_artifacts;

create or replace function public.prepare_project_generation(target_project_id uuid,target_report_type text,target_output_format text)
returns jsonb
language plpgsql
security definer
set search_path=public,project,regula,cde,core,audit,extensions,auth,pg_temp
as $$
declare
  actor uuid:=auth.uid();
  p project.projects%rowtype;
  org_id uuid;
  truth_payload jsonb;
  requirement_payload jsonb;
  regula_payload jsonb;
  commercial_payload jsonb;
  document_payload jsonb;
  payload jsonb;
  truth_hash text;
  requirement_hash text;
  regula_hash text;
  commercial_hash text;
  document_hash text;
  input_hash text;
  snapshot_id uuid;
  template_id uuid;
  template_version_id uuid;
  existing_template_checksum text;
  existing_template_ref text;
  existing_template_locked boolean;
  job_id uuid;
  snapshot_time timestamptz:=clock_timestamp();
  format_value text:=lower(btrim(target_output_format));
  report_value text:=lower(coalesce(nullif(btrim(target_report_type),''),'project_report'));
  template_checksum text:=encode(extensions.digest('conceptspaces-runtime-project-report-v1','sha256'),'hex');
begin
  if actor is null then raise exception 'authentication_required'; end if;
  if target_project_id is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if format_value not in ('pdf','docx','xlsx','pptx','html','json','csv') then raise exception 'unsupported_generation_format'; end if;
  if report_value not in ('project_report','design_report','feasibility_report','client_presentation','drawing_register','progress_report','handover_pack') then raise exception 'unsupported_report_type'; end if;

  select * into p from project.projects where id=target_project_id;
  if not found then raise exception 'project_not_found'; end if;
  org_id:=p.organisation_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',t.id,'kind',t.kind,'record_key',t.record_key,'value',t.value,'unit',t.unit,'source_type',t.source_type,
    'source_reference',t.source_reference,'confidence',t.confidence,'status',t.status,'criticality',t.criticality,
    'verified_by',t.verified_by,'verified_at',t.verified_at,'updated_at',t.updated_at
  ) order by t.record_key,t.created_at),'[]'::jsonb) into truth_payload
  from project.truth_records t where t.project_id=p.id and t.valid_until is null;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'code',r.code::text,'statement',r.statement,'category',r.category,'acceptance_criteria',r.acceptance_criteria,
    'status',r.status,'criticality',r.criticality,'owner_user_id',r.owner_user_id,'updated_at',r.updated_at
  ) order by r.code),'[]'::jsonb) into requirement_payload
  from project.requirements r where r.project_id=p.id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',f.id,'rule_id',f.rule_id,'disposition',f.disposition,'status',f.status,'observed_value',f.observed_value,
    'required_value',f.required_value,'evidence_refs',f.evidence_refs,'explanation',f.explanation,'checked_by_type',f.checked_by_type,
    'checked_by',f.checked_by,'checked_at',f.checked_at
  ) order by f.checked_at nulls last,f.id),'[]'::jsonb) into regula_payload
  from regula.compliance_findings f where f.project_id=p.id;

  commercial_payload:=jsonb_build_object(
    'contracts',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'status',c.status,'version',c.version,'effective_at',c.effective_at,'expires_at',c.expires_at) order by c.created_at,c.id) from public.contracts c where c.project_id=p.id),'[]'::jsonb),
    'invoices',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'invoice_number',i.invoice_number,'status',i.status,'currency',i.currency,'issue_date',i.issue_date,'due_date',i.due_date,'subtotal',i.subtotal,'tax',i.tax,'total',i.total,'amount_paid',i.amount_paid,'tds_receivable',i.tds_receivable) order by i.issue_date,i.id) from public.invoices i where i.project_id=p.id),'[]'::jsonb)
  );

  document_payload:=jsonb_build_object(
    'documents',coalesce((select jsonb_agg(jsonb_build_object('id',d.id,'document_number',d.document_number::text,'title',d.title,'discipline',d.discipline,'document_type',d.document_type,'cde_state',d.cde_state,'status',d.status,'revision',d.revision,'current_version_id',d.current_version_id) order by d.document_number,d.revision,d.id) from cde.documents d where d.project_id=p.id),'[]'::jsonb),
    'models',coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'model_name',m.model_name,'discipline',m.discipline,'format',m.format,'schema_version',m.schema_version,'status',m.status,'checksum',m.checksum) order by m.created_at,m.id) from cde.models m where m.project_id=p.id),'[]'::jsonb)
  );

  truth_hash:=encode(extensions.digest(truth_payload::text,'sha256'),'hex');
  requirement_hash:=encode(extensions.digest(requirement_payload::text,'sha256'),'hex');
  regula_hash:=encode(extensions.digest(regula_payload::text,'sha256'),'hex');
  commercial_hash:=encode(extensions.digest(commercial_payload::text,'sha256'),'hex');
  document_hash:=encode(extensions.digest(document_payload::text,'sha256'),'hex');

  payload:=jsonb_build_object(
    'schema_version','conceptspaces.project-report.v1',
    'report_type',report_value,
    'project',jsonb_build_object('id',p.id,'code',p.code::text,'name',p.name,'typology',p.typology,'stage',p.stage,'criticality',p.criticality,'status',p.status,'jurisdiction',jsonb_build_object('country',p.jurisdiction_country,'state',p.jurisdiction_state,'city',p.jurisdiction_city)),
    'project_truth',truth_payload,'requirements',requirement_payload,'regulatory_findings',regula_payload,
    'commercial',commercial_payload,'cde',document_payload,
    'snapshot_hashes',jsonb_build_object('project_truth',truth_hash,'requirements',requirement_hash,'regulatory',regula_hash,'commercial',commercial_hash,'documents',document_hash),
    'as_of',snapshot_time
  );
  input_hash:=encode(extensions.digest(payload::text||'|'||template_checksum||'|'||format_value,'sha256'),'hex');

  insert into public.project_report_snapshots(project_id,report_type,as_of,project_truth_hash,requirement_snapshot_hash,regulatory_snapshot_hash,commercial_snapshot_hash,document_snapshot_hash,source_refs,snapshot_payload,created_by)
  values(p.id,report_value,snapshot_time,truth_hash,requirement_hash,regula_hash,commercial_hash,document_hash,
    jsonb_build_array(jsonb_build_object('type','project_truth','hash',truth_hash),jsonb_build_object('type','requirements','hash',requirement_hash),jsonb_build_object('type','regulatory','hash',regula_hash),jsonb_build_object('type','commercial','hash',commercial_hash),jsonb_build_object('type','documents','hash',document_hash)),payload,actor)
  returning id into snapshot_id;

  insert into public.document_templates(organisation_id,code,name,template_kind,output_formats,required_data_paths,current_version,active)
  values(org_id,'CS-RUNTIME-PROJECT-REPORT','Concept Spaces Runtime Project Report','design_report','["pdf","docx","xlsx","pptx","html","json","csv"]'::jsonb,'["project","project_truth","requirements"]'::jsonb,1,true)
  on conflict (organisation_id,code) do update set
    name=excluded.name,template_kind=excluded.template_kind,output_formats=excluded.output_formats,
    required_data_paths=excluded.required_data_paths,current_version=1,active=true,updated_at=now()
  returning id into template_id;

  select tv.id,tv.checksum,tv.template_ref,tv.locked into template_version_id,existing_template_checksum,existing_template_ref,existing_template_locked
  from public.template_versions tv where tv.template_id=template_id and tv.version=1;
  if template_version_id is null then
    insert into public.template_versions(template_id,version,schema_version,template_ref,checksum,required_data_paths,locked,created_by)
    values(template_id,1,'conceptspaces.project-report.v1','runtime:conceptspaces-project-report-v1',template_checksum,'["project","project_truth","requirements"]'::jsonb,true,actor)
    returning id into template_version_id;
  elsif existing_template_checksum<>template_checksum or existing_template_ref<>'runtime:conceptspaces-project-report-v1' or existing_template_locked is not true then
    raise exception 'runtime_template_integrity_failure';
  end if;

  insert into public.generation_jobs(organisation_id,project_id,template_version_id,output_format,status,snapshot_id,input_hash,requested_by,started_at)
  values(org_id,p.id,template_version_id,format_value,'running',snapshot_id,input_hash,actor,now()) returning id into job_id;
  perform audit.append_event(org_id,p.id,'report.generation.started','generation_job',job_id,null,jsonb_build_object('format',format_value,'report_type',report_value,'input_hash',input_hash,'snapshot_id',snapshot_id),null,gen_random_uuid());
  return jsonb_build_object('job_id',job_id,'snapshot_id',snapshot_id,'template_version_id',template_version_id,'input_hash',input_hash,'output_format',format_value,'report_type',report_value,'payload',payload);
end;
$$;
revoke all on function public.prepare_project_generation(uuid,text,text) from public,anon,authenticated;
grant execute on function public.prepare_project_generation(uuid,text,text) to authenticated;

create or replace function public.complete_project_generation(target_job_id uuid,target_object_ref text,target_output_hash text,target_title text)
returns uuid
language plpgsql
security definer
set search_path=public,project,audit,storage,auth,pg_temp
as $$
declare
  actor uuid:=auth.uid();
  j public.generation_jobs%rowtype;
  a public.generated_artifacts%rowtype;
  object_owner uuid;
  object_owner_id text;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  select * into j from public.generation_jobs where id=target_job_id for update;
  if not found then raise exception 'generation_job_not_found'; end if;
  if j.requested_by<>actor then raise exception 'generation_requester_required'; end if;
  if j.project_id is null or not project.can_manage_project(j.project_id) then raise exception 'project_manage_authority_required'; end if;
  if j.status<>'running' then raise exception 'generation_job_not_running'; end if;
  if target_object_ref not like j.project_id::text||'/generated/'||j.id::text||'/%' then raise exception 'invalid_generated_artifact_path'; end if;
  if target_output_hash !~ '^[0-9a-fA-F]{64}$' then raise exception 'sha256_output_hash_required'; end if;

  select o.owner,o.owner_id into object_owner,object_owner_id
  from storage.objects o
  where o.bucket_id='project-cde' and o.name=target_object_ref and coalesce(o.is_delete_marker,false)=false
  limit 1;
  if not found then raise exception 'generated_artifact_object_not_found'; end if;
  if object_owner is distinct from actor and coalesce(object_owner_id,'')<>actor::text then raise exception 'generated_artifact_object_owner_mismatch'; end if;

  update public.generation_jobs set status='completed',output_hash=lower(target_output_hash),completed_at=now() where id=j.id;
  insert into public.generated_artifacts(generation_job_id,project_id,title,output_format,object_ref,checksum,status,revision,source_snapshot_id,template_version_id)
  values(j.id,j.project_id,coalesce(nullif(btrim(target_title),''),'Concept Spaces Project Report'),j.output_format,target_object_ref,lower(target_output_hash),'draft','P01',j.snapshot_id,j.template_version_id)
  returning * into a;
  perform audit.append_event(j.organisation_id,j.project_id,'report.generation.completed','generated_artifact',a.id,null,to_jsonb(a),null,gen_random_uuid());
  return a.id;
end;
$$;
revoke all on function public.complete_project_generation(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.complete_project_generation(uuid,text,text,text) to authenticated;

create or replace function public.fail_project_generation(target_job_id uuid,target_error_code text)
returns void
language plpgsql
security definer
set search_path=public,project,audit,auth,pg_temp
as $$
declare actor uuid:=auth.uid(); j public.generation_jobs%rowtype;
begin
  if actor is null then raise exception 'authentication_required'; end if;
  select * into j from public.generation_jobs where id=target_job_id for update;
  if not found then return; end if;
  if j.requested_by<>actor then raise exception 'generation_requester_required'; end if;
  if j.project_id is null or not project.can_manage_project(j.project_id) then raise exception 'project_manage_authority_required'; end if;
  if j.status='completed' then raise exception 'completed_generation_job_is_terminal'; end if;
  if j.status='failed' then return; end if;
  update public.generation_jobs set status='failed',error_code=left(coalesce(nullif(btrim(target_error_code),''),'generation_failed'),200),completed_at=now() where id=j.id;
  perform audit.append_event(j.organisation_id,j.project_id,'report.generation.failed','generation_job',j.id,null,jsonb_build_object('error_code',left(coalesce(target_error_code,'generation_failed'),200)),left(coalesce(target_error_code,'generation_failed'),200),gen_random_uuid());
end;
$$;
revoke all on function public.fail_project_generation(uuid,text) from public,anon,authenticated;
grant execute on function public.fail_project_generation(uuid,text) to authenticated;

create or replace function public.list_project_generated_artifacts(target_project_id uuid)
returns table(id uuid,title text,output_format text,object_ref text,checksum text,status text,revision text,source_snapshot_id uuid,created_at timestamptz)
language sql
stable
security definer
set search_path=public,project,auth,pg_temp
as $$
  select a.id,a.title,a.output_format,a.object_ref,a.checksum,a.status,a.revision,a.source_snapshot_id,a.created_at
  from public.generated_artifacts a
  where a.project_id=target_project_id and auth.uid() is not null and project.can_access_project(target_project_id)
  order by a.created_at desc;
$$;
revoke all on function public.list_project_generated_artifacts(uuid) from public,anon,authenticated;
grant execute on function public.list_project_generated_artifacts(uuid) to authenticated;

commit;
