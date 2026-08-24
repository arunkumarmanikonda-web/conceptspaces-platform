begin;

create schema if not exists privacy;
grant usage on schema privacy to authenticated;

create table if not exists privacy.processing_records(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 purpose_code text not null,
 purpose_description text not null,
 legal_basis text not null,
 data_categories jsonb not null default '[]'::jsonb,
 subject_categories jsonb not null default '[]'::jsonb,
 recipients jsonb not null default '[]'::jsonb,
 retention_days integer check(retention_days is null or retention_days>0),
 active boolean not null default true,
 version integer not null default 1 check(version>0),
 supersedes_id uuid references privacy.processing_records(id) on delete set null,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 record_hash text not null,
 unique(organisation_id,purpose_code,version)
);

create table if not exists privacy.consent_records(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 subject_user_id uuid references auth.users(id) on delete set null,
 subject_reference text not null,
 purpose_code text not null,
 legal_basis text not null,
 status text not null check(status in ('granted','withdrawn','not_required')),
 evidence_ref text not null,
 evidence_hash text not null,
 effective_at timestamptz not null default now(),
 withdrawn_at timestamptz,
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now()
);

create table if not exists privacy.retention_policies(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 record_class text not null,
 retention_days integer not null check(retention_days>0),
 legal_hold_required boolean not null default false,
 disposal_method text not null,
 status text not null default 'draft' check(status in ('draft','active','superseded')),
 version integer not null default 1 check(version>0),
 supersedes_id uuid references privacy.retention_policies(id) on delete set null,
 policy_hash text not null,
 created_by uuid not null references auth.users(id),
 approved_by uuid references auth.users(id),
 approved_at timestamptz,
 created_at timestamptz not null default now(),
 unique(organisation_id,record_class,version)
);

create table if not exists privacy.data_subject_requests(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 request_type text not null check(request_type in ('access','correction','erasure','restriction','portability','objection')),
 subject_user_id uuid references auth.users(id) on delete set null,
 subject_reference text not null,
 identity_status text not null default 'pending' check(identity_status in ('pending','verified','rejected')),
 state text not null default 'identity_pending' check(state in ('identity_pending','in_progress','completed','rejected')),
 scope jsonb not null default '[]'::jsonb,
 legal_hold_refs jsonb not null default '[]'::jsonb,
 requested_at timestamptz not null default now(),
 requested_by uuid references auth.users(id) on delete set null,
 verified_by uuid references auth.users(id),
 verified_at timestamptz,
 completed_by uuid references auth.users(id),
 completed_at timestamptz,
 completion_evidence_refs jsonb not null default '[]'::jsonb,
 completion_hash text,
 decision_reason text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);

create table if not exists privacy.project_export_requests(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 project_id uuid not null references project.projects(id) on delete cascade,
 document_id uuid not null references cde.documents(id) on delete cascade,
 requested_by uuid not null references auth.users(id),
 purpose text not null,
 intended_recipient text,
 status text not null default 'pending' check(status in ('pending','approved','rejected','expired','used')),
 requested_at timestamptz not null default now(),
 decided_by uuid references auth.users(id),
 decided_at timestamptz,
 decision_reason text,
 expires_at timestamptz,
 used_at timestamptz,
 request_hash text not null,
 approval_hash text
);

alter table privacy.processing_records enable row level security;
alter table privacy.consent_records enable row level security;
alter table privacy.retention_policies enable row level security;
alter table privacy.data_subject_requests enable row level security;
alter table privacy.project_export_requests enable row level security;

grant select,insert,update on privacy.processing_records,privacy.consent_records,privacy.retention_policies,privacy.data_subject_requests,privacy.project_export_requests to authenticated;

do $$ declare t text; begin
 foreach t in array array['processing_records','consent_records','retention_policies','data_subject_requests'] loop
  execute format('drop policy if exists %I on privacy.%I','privacy_org_read_'||t,t);
  execute format('create policy %I on privacy.%I for select to authenticated using (core.is_internal_org_member(organisation_id))','privacy_org_read_'||t,t);
 end loop;
end $$;

drop policy if exists privacy_export_read on privacy.project_export_requests;
create policy privacy_export_read on privacy.project_export_requests for select to authenticated
using(project.can_access_project(project_id) or requested_by=auth.uid());

drop policy if exists privacy_processing_write on privacy.processing_records;
create policy privacy_processing_write on privacy.processing_records for insert to authenticated
with check(core.has_org_role(organisation_id,array['super_admin','org_admin']) and created_by=auth.uid() and current_setting('conceptspaces.privacy_phase',true)='processing');
drop policy if exists privacy_consent_write on privacy.consent_records;
create policy privacy_consent_write on privacy.consent_records for insert to authenticated
with check(core.is_internal_org_member(organisation_id) and created_by=auth.uid() and current_setting('conceptspaces.privacy_phase',true)='consent');
drop policy if exists privacy_retention_write on privacy.retention_policies;
create policy privacy_retention_write on privacy.retention_policies for insert to authenticated
with check(core.has_org_role(organisation_id,array['super_admin','org_admin']) and created_by=auth.uid() and current_setting('conceptspaces.privacy_phase',true)='retention');
drop policy if exists privacy_retention_update on privacy.retention_policies;
create policy privacy_retention_update on privacy.retention_policies for update to authenticated
using(core.has_org_role(organisation_id,array['super_admin','org_admin']))
with check(core.has_org_role(organisation_id,array['super_admin','org_admin']) and current_setting('conceptspaces.privacy_phase',true)='retention_approve');
drop policy if exists privacy_dsr_write on privacy.data_subject_requests;
create policy privacy_dsr_write on privacy.data_subject_requests for insert to authenticated
with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.privacy_phase',true)='dsr_create');
drop policy if exists privacy_dsr_update on privacy.data_subject_requests;
create policy privacy_dsr_update on privacy.data_subject_requests for update to authenticated
using(core.has_org_role(organisation_id,array['super_admin','org_admin']))
with check(core.has_org_role(organisation_id,array['super_admin','org_admin']) and current_setting('conceptspaces.privacy_phase',true) in ('dsr_verify','dsr_progress','dsr_complete','dsr_reject'));
drop policy if exists privacy_export_insert on privacy.project_export_requests;
create policy privacy_export_insert on privacy.project_export_requests for insert to authenticated
with check(requested_by=auth.uid() and project.can_access_project(project_id) and current_setting('conceptspaces.privacy_phase',true)='export_request');
drop policy if exists privacy_export_update on privacy.project_export_requests;
create policy privacy_export_update on privacy.project_export_requests for update to authenticated
using(project.can_manage_project(project_id))
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.privacy_phase',true) in ('export_decide','export_use'));

create or replace function public.create_privacy_request(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='privacy','core','audit','auth','pg_temp' as $$
declare r privacy.data_subject_requests%rowtype; kind text:=lower(btrim(input_payload->>'request_type'));
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 if kind not in ('access','correction','erasure','restriction','portability','objection') then raise exception 'privacy_request_type_invalid';end if;
 if nullif(btrim(input_payload->>'subject_reference'),'') is null then raise exception 'privacy_subject_reference_required';end if;
 perform set_config('conceptspaces.privacy_phase','dsr_create',true);
 insert into privacy.data_subject_requests(organisation_id,request_type,subject_user_id,subject_reference,scope,requested_by)
 values(target_organisation_id,kind,nullif(input_payload->>'subject_user_id','')::uuid,btrim(input_payload->>'subject_reference'),coalesce(input_payload->'scope','[]'::jsonb),auth.uid()) returning * into r;
 perform audit.append_event(r.organisation_id,null,'privacy.request_created','data_subject_request',r.id,null,to_jsonb(r),null,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.create_privacy_request(uuid,jsonb) from public,anon;grant execute on function public.create_privacy_request(uuid,jsonb) to authenticated;

create or replace function public.verify_privacy_request_identity(target_request_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker
set search_path='privacy','core','audit','auth','pg_temp' as $$
declare r privacy.data_subject_requests%rowtype; d text:=lower(btrim(target_decision)); before_state jsonb;
begin
 select * into r from privacy.data_subject_requests where id=target_request_id for update;if not found then raise exception 'privacy_request_not_found';end if;
 if auth.uid() is null or not core.has_org_role(r.organisation_id,array['super_admin','org_admin']) then raise exception 'privacy_identity_verification_authority_required';end if;
 if r.identity_status<>'pending' then raise exception 'privacy_identity_already_decided';end if;
 if d not in ('verified','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'privacy_identity_decision_invalid';end if;before_state:=to_jsonb(r);
 perform set_config('conceptspaces.privacy_phase',case when d='verified' then 'dsr_verify' else 'dsr_reject' end,true);
 update privacy.data_subject_requests set identity_status=d,state=case when d='verified' then 'in_progress' else 'rejected' end,verified_by=auth.uid(),verified_at=now(),decision_reason=btrim(target_reason),updated_at=now() where id=r.id returning * into r;
 perform audit.append_event(r.organisation_id,null,'privacy.identity_'||d,'data_subject_request',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());return r.state;
end;$$;
revoke all on function public.verify_privacy_request_identity(uuid,text,text) from public,anon;grant execute on function public.verify_privacy_request_identity(uuid,text,text) to authenticated;

create or replace function public.complete_privacy_request(target_request_id uuid,input_payload jsonb)
returns text language plpgsql security invoker
set search_path='privacy','core','audit','extensions','auth','pg_temp' as $$
declare r privacy.data_subject_requests%rowtype; before_state jsonb; evidence jsonb:=coalesce(input_payload->'evidence_refs','[]'::jsonb); holds jsonb:=coalesce(input_payload->'legal_hold_refs','[]'::jsonb); h text;
begin
 select * into r from privacy.data_subject_requests where id=target_request_id for update;if not found then raise exception 'privacy_request_not_found';end if;
 if auth.uid() is null or not core.has_org_role(r.organisation_id,array['super_admin','org_admin']) then raise exception 'privacy_completion_authority_required';end if;
 if r.identity_status<>'verified' or r.state<>'in_progress' then raise exception 'privacy_verified_in_progress_request_required';end if;
 if jsonb_array_length(evidence)=0 then raise exception 'privacy_completion_evidence_required';end if;
 if r.request_type='erasure' and jsonb_array_length(holds)>0 and nullif(btrim(input_payload->>'decision_reason'),'') is null then raise exception 'retention_hold_reason_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('request_id',r.id,'type',r.request_type,'scope',r.scope,'evidence',evidence,'legal_holds',holds,'reason',coalesce(input_payload->>'decision_reason',''))::text,'sha256'),'hex');before_state:=to_jsonb(r);
 perform set_config('conceptspaces.privacy_phase','dsr_complete',true);
 update privacy.data_subject_requests set state='completed',completed_by=auth.uid(),completed_at=now(),completion_evidence_refs=evidence,legal_hold_refs=holds,completion_hash=h,decision_reason=nullif(btrim(input_payload->>'decision_reason'),''),updated_at=now() where id=r.id returning * into r;
 perform audit.append_event(r.organisation_id,null,'privacy.request_completed','data_subject_request',r.id,before_state,to_jsonb(r),h,gen_random_uuid());return r.state;
end;$$;
revoke all on function public.complete_privacy_request(uuid,jsonb) from public,anon;grant execute on function public.complete_privacy_request(uuid,jsonb) to authenticated;

create or replace function public.request_restricted_document_export(target_document_id uuid,target_purpose text,target_recipient text default null)
returns uuid language plpgsql security invoker
set search_path='privacy','cde','project','audit','extensions','auth','pg_temp' as $$
declare d cde.documents%rowtype; p project.projects%rowtype; r privacy.project_export_requests%rowtype; h text;
begin
 select * into d from cde.documents where id=target_document_id;if not found then raise exception 'document_not_found';end if;
 select * into p from project.projects where id=d.project_id;if not found or auth.uid() is null or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;
 if p.data_classification<>'restricted' then raise exception 'restricted_export_request_only_required_for_restricted_project';end if;
 if d.status not in ('approved','issued') or d.cde_state<>'published' then raise exception 'document_not_published_for_export';end if;
 if nullif(btrim(target_purpose),'') is null then raise exception 'export_purpose_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'document_id',d.id,'revision',d.revision,'purpose',btrim(target_purpose),'recipient',coalesce(target_recipient,''),'requester',auth.uid())::text,'sha256'),'hex');
 perform set_config('conceptspaces.privacy_phase','export_request',true);
 insert into privacy.project_export_requests(organisation_id,project_id,document_id,requested_by,purpose,intended_recipient,request_hash) values(p.organisation_id,p.id,d.id,auth.uid(),btrim(target_purpose),nullif(btrim(target_recipient),''),h) returning * into r;
 perform audit.append_event(p.organisation_id,p.id,'security.export_requested','project_export_request',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.request_restricted_document_export(uuid,text,text) from public,anon;grant execute on function public.request_restricted_document_export(uuid,text,text) to authenticated;

create or replace function public.decide_restricted_document_export(target_request_id uuid,target_decision text,target_reason text,target_expires_at timestamptz default null)
returns text language plpgsql security invoker
set search_path='privacy','project','audit','extensions','auth','pg_temp' as $$
declare r privacy.project_export_requests%rowtype; d text:=lower(btrim(target_decision)); before_state jsonb; h text;
begin
 select * into r from privacy.project_export_requests where id=target_request_id for update;if not found then raise exception 'export_request_not_found';end if;
 if auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'export_approval_authority_required';end if;
 if r.requested_by=auth.uid() then raise exception 'export_requester_cannot_approve_own_request';end if;
 if r.status<>'pending' or d not in ('approved','rejected') or nullif(btrim(target_reason),'') is null then raise exception 'export_decision_invalid';end if;
 if d='approved' and target_expires_at is null then raise exception 'export_approval_expiry_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('request_hash',r.request_hash,'decision',d,'reason',btrim(target_reason),'expires_at',target_expires_at,'approver',auth.uid())::text,'sha256'),'hex');before_state:=to_jsonb(r);
 perform set_config('conceptspaces.privacy_phase','export_decide',true);
 update privacy.project_export_requests set status=d,decided_by=auth.uid(),decided_at=now(),decision_reason=btrim(target_reason),expires_at=case when d='approved' then target_expires_at else null end,approval_hash=h where id=r.id returning * into r;
 perform audit.append_event(r.organisation_id,r.project_id,'security.export_'||d,'project_export_request',r.id,before_state,to_jsonb(r),h,gen_random_uuid());return r.status;
end;$$;
revoke all on function public.decide_restricted_document_export(uuid,text,text,timestamptz) from public,anon;grant execute on function public.decide_restricted_document_export(uuid,text,text,timestamptz) to authenticated;

create or replace function public.authorize_document_download(target_document_id uuid,target_export_request_id uuid default null)
returns jsonb language plpgsql security invoker
set search_path='privacy','cde','project','engagement','audit','auth','pg_temp' as $$
declare d cde.documents%rowtype; p project.projects%rowtype; r privacy.project_export_requests%rowtype; internal_mode boolean; client_ok boolean:=false; allowed boolean:=false; watermark boolean:=false; reason_value text;
begin
 select * into d from cde.documents where id=target_document_id;if not found then raise exception 'document_not_found';end if;
 select * into p from project.projects where id=d.project_id;if auth.uid() is null then raise exception 'authentication_required';end if;
 internal_mode:=project.can_access_project(p.id);
 client_ok:=engagement.client_can_access_project(p.id) and exists(select 1 from engagement.client_portal_access a where a.project_id=p.id and a.user_id=auth.uid() and a.status='active' and coalesce((a.permissions->>'download_documents')::boolean,false));
 if d.status not in ('approved','issued') then reason_value:='document_not_approved_or_issued';
 elsif client_ok and d.cde_state<>'published' then reason_value:='client_download_requires_published_document';
 elsif p.data_classification='public' then allowed:=internal_mode or client_ok;
 elsif p.data_classification='internal' then allowed:=internal_mode;reason_value:=case when not internal_mode then 'internal_classification_block' end;
 elsif p.data_classification='confidential' then allowed:=project.can_manage_project(p.id);watermark:=allowed;reason_value:=case when not allowed then 'confidential_download_management_authority_required' end;
 elsif p.data_classification='restricted' then
   if target_export_request_id is not null then select * into r from privacy.project_export_requests where id=target_export_request_id and document_id=d.id and project_id=p.id and requested_by=auth.uid() and status='approved' and expires_at>now();end if;
   allowed:=found;watermark:=allowed;reason_value:=case when not allowed then 'CLASSIFICATION_BLOCK' end;
 end if;
 if allowed then perform audit.append_event(p.organisation_id,p.id,'security.download_authorized','document',d.id,null,jsonb_build_object('classification',p.data_classification,'revision',d.revision,'export_request_id',target_export_request_id,'watermark_required',watermark),null,gen_random_uuid());else perform audit.append_event(p.organisation_id,p.id,'security.download_blocked','document',d.id,null,jsonb_build_object('classification',p.data_classification,'reason',coalesce(reason_value,'permission_denied')),coalesce(reason_value,'permission_denied'),gen_random_uuid());end if;
 return jsonb_build_object('allowed',allowed,'classification',p.data_classification,'watermark_required',watermark,'reason',case when allowed then null else coalesce(reason_value,'permission_denied') end,'document_id',d.id,'revision',d.revision);
end;$$;
revoke all on function public.authorize_document_download(uuid,uuid) from public,anon;grant execute on function public.authorize_document_download(uuid,uuid) to authenticated;

create or replace function public.verify_audit_chain(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path='audit','core','extensions','auth','pg_temp' as $$
declare e audit.events%rowtype; expected_previous text:=null; computed text; first_bad uuid:=null; checked_count bigint:=0;
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 for e in select * from audit.events where organisation_id=target_organisation_id order by created_at,id loop
  checked_count:=checked_count+1;
  if e.previous_hash is distinct from expected_previous then first_bad:=e.id;exit;end if;
  computed:=encode(extensions.digest(concat_ws('|',coalesce(e.previous_hash,''),e.id::text,e.organisation_id::text,coalesce(e.project_id::text,''),coalesce(e.actor_id::text,''),e.action,e.resource_type,coalesce(e.resource_id::text,''),coalesce(e.before_state::text,''),coalesce(e.after_state::text,''),coalesce(e.reason,''),e.correlation_id::text,e.created_at::text),'sha256'),'hex');
  if computed<>e.event_hash then first_bad:=e.id;exit;end if;
  expected_previous:=e.event_hash;
 end loop;
 return jsonb_build_object('valid',first_bad is null,'checked_events',checked_count,'first_invalid_event_id',first_bad,'chain_head',expected_previous);
end;$$;
revoke all on function public.verify_audit_chain(uuid) from public,anon;grant execute on function public.verify_audit_chain(uuid) to authenticated;

create or replace function public.list_privacy_security_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path='privacy','project','core','auth','pg_temp' as $$
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 return jsonb_build_object(
 'processing',coalesce((select jsonb_agg(to_jsonb(r) order by r.purpose_code,r.version desc) from privacy.processing_records r where r.organisation_id=target_organisation_id),'[]'::jsonb),
 'retention',coalesce((select jsonb_agg(to_jsonb(r) order by r.record_class,r.version desc) from privacy.retention_policies r where r.organisation_id=target_organisation_id),'[]'::jsonb),
 'requests',coalesce((select jsonb_agg(to_jsonb(r) order by r.requested_at desc) from privacy.data_subject_requests r where r.organisation_id=target_organisation_id),'[]'::jsonb),
 'exports',coalesce((select jsonb_agg(to_jsonb(r) order by r.requested_at desc) from privacy.project_export_requests r where r.organisation_id=target_organisation_id and project.can_access_project(r.project_id)),'[]'::jsonb),
 'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code::text,'name',p.name,'classification',p.data_classification) order by p.name) from project.projects p where p.organisation_id=target_organisation_id and project.can_access_project(p.id)),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_privacy_security_workspace(uuid) from public,anon;grant execute on function public.list_privacy_security_workspace(uuid) to authenticated;

commit;
