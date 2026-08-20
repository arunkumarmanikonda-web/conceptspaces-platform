begin;

-- -----------------------------------------------------------------------------
-- Build Pack 20: Governed Operating Mutations
-- Commercial, workflow, issue and approval actions are transactional, RLS-bound
-- and append an immutable hash-linked audit event for every material state change.
-- -----------------------------------------------------------------------------

alter table public.proposals add column if not exists created_by uuid references auth.users(id);
alter table public.proposals add column if not exists submitted_at timestamptz;
alter table public.contracts add column if not exists created_by uuid references auth.users(id);
alter table public.invoices add column if not exists created_by uuid references auth.users(id);

-- Hash-linked append-only audit helper. Internal only, not exposed through PostgREST.
create or replace function audit.append_event(
  target_organisation_id uuid,
  target_project_id uuid,
  target_action text,
  target_resource_type text,
  target_resource_id uuid,
  target_before_state jsonb default null,
  target_after_state jsonb default null,
  target_reason text default null,
  target_correlation_id uuid default gen_random_uuid()
)
returns uuid
language plpgsql
security definer
set search_path = audit, public, extensions
as $$
declare
  previous text;
  event_id uuid := gen_random_uuid();
  event_time timestamptz := clock_timestamp();
  payload text;
  computed text;
begin
  if target_organisation_id is null then raise exception 'audit_organisation_required'; end if;
  if target_action is null or btrim(target_action)='' then raise exception 'audit_action_required'; end if;
  if target_resource_type is null or btrim(target_resource_type)='' then raise exception 'audit_resource_type_required'; end if;

  perform pg_advisory_xact_lock(hashtext('concept_spaces_audit_' || target_organisation_id::text));
  select event_hash into previous
  from audit.events
  where organisation_id=target_organisation_id
  order by created_at desc,id desc
  limit 1;

  payload := concat_ws('|',
    coalesce(previous,''), event_id::text, target_organisation_id::text,
    coalesce(target_project_id::text,''), coalesce(auth.uid()::text,''),
    target_action, target_resource_type, coalesce(target_resource_id::text,''),
    coalesce(target_before_state::text,''), coalesce(target_after_state::text,''),
    coalesce(target_reason,''), target_correlation_id::text, event_time::text
  );
  computed := encode(extensions.digest(payload,'sha256'),'hex');

  insert into audit.events(
    id,organisation_id,project_id,actor_id,actor_type,action,resource_type,resource_id,
    before_state,after_state,reason,correlation_id,previous_hash,event_hash,created_at
  ) values (
    event_id,target_organisation_id,target_project_id,auth.uid(),'human',target_action,target_resource_type,target_resource_id,
    target_before_state,target_after_state,target_reason,target_correlation_id,previous,computed,event_time
  );
  return event_id;
end;
$$;
revoke all on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid) from public,anon,authenticated;

-- Utility: professional eligibility is separate from workspace RBAC.
create or replace function core.has_verified_professional_eligibility(target_user uuid,target_role text)
returns boolean
language sql
stable
security definer
set search_path=core,public
as $$
  select exists (
    select 1 from core.professional_credentials c
    where c.user_id=target_user
      and c.verification_status='verified'
      and (c.valid_from is null or c.valid_from<=current_date)
      and (c.valid_until is null or c.valid_until>=current_date)
      and (
        (target_role in ('architect','lead_architect') and (lower(coalesce(c.discipline,'')) like '%arch%' or lower(c.credential_type) like '%architect%'))
        or (target_role='structural_engineer' and (lower(coalesce(c.discipline,'')) like '%struct%' or lower(c.credential_type) like '%struct%'))
        or (target_role='mep_engineer' and (lower(coalesce(c.discipline,'')) like '%mep%' or lower(c.credential_type) like '%mep%'))
        or (target_role='quantity_surveyor' and (lower(coalesce(c.discipline,'')) like '%quant%' or lower(c.credential_type) like '%quantity%'))
        or (target_role='regulatory_reviewer' and (lower(coalesce(c.discipline,'')) like '%regulat%' or lower(c.credential_type) like '%regulat%'))
      )
  );
$$;
revoke all on function core.has_verified_professional_eligibility(uuid,text) from public,anon;
grant execute on function core.has_verified_professional_eligibility(uuid,text) to authenticated;

-- Narrow grants required by SECURITY INVOKER RPCs. RLS remains authoritative.
grant usage on schema operations, coordination, audit to authenticated;
grant select,insert,update on public.contacts,public.leads,public.opportunities,public.proposals,public.proposal_lines,public.contracts,public.contract_obligations,public.invoices,public.invoice_lines to authenticated;
grant select,insert,update on operations.tasks to authenticated;
grant select,insert,update on coordination.issues,coordination.issue_comments,coordination.approval_requests to authenticated;

-- Commercial write policies.
drop policy if exists contacts_operate on public.contacts;
create policy contacts_operate on public.contacts for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists leads_operate on public.leads;
create policy leads_operate on public.leads for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists opportunities_operate on public.opportunities;
create policy opportunities_operate on public.opportunities for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','project_manager']));

drop policy if exists proposals_operate on public.proposals;
create policy proposals_operate on public.proposals for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','sales','finance']));

drop policy if exists proposal_lines_operate on public.proposal_lines;
create policy proposal_lines_operate on public.proposal_lines for all to authenticated
using (exists(select 1 from public.proposals p where p.id=proposal_id and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance'])))
with check (exists(select 1 from public.proposals p where p.id=proposal_id and core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) and p.status in ('draft','internal_review'))));

drop policy if exists contracts_operate on public.contracts;
create policy contracts_operate on public.contracts for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists contract_obligations_operate on public.contract_obligations;
create policy contract_obligations_operate on public.contract_obligations for all to authenticated
using (exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])))
with check (exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','project_manager'])));

drop policy if exists invoices_operate on public.invoices;
create policy invoices_operate on public.invoices for all to authenticated
using (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']))
with check (core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists invoice_lines_operate on public.invoice_lines;
create policy invoice_lines_operate on public.invoice_lines for all to authenticated
using (exists(select 1 from public.invoices i where i.id=invoice_id and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance'])))
with check (exists(select 1 from public.invoices i where i.id=invoice_id and core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) and i.status='draft'));

-- Operations and coordination write policies.
drop policy if exists tasks_operate on operations.tasks;
create policy tasks_operate on operations.tasks for all to authenticated
using (((project_id is not null) and project.can_access_project(project_id)) or ((project_id is null) and core.is_internal_org_member(organisation_id)))
with check (((project_id is not null) and project.can_access_project(project_id)) or ((project_id is null) and core.is_internal_org_member(organisation_id)));

drop policy if exists issues_operate on coordination.issues;
create policy issues_operate on coordination.issues for all to authenticated
using (project.can_access_project(project_id))
with check (project.can_access_project(project_id));

drop policy if exists issue_comments_operate on coordination.issue_comments;
create policy issue_comments_operate on coordination.issue_comments for all to authenticated
using (exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id)))
with check (exists(select 1 from coordination.issues i where i.id=issue_id and project.can_access_project(i.project_id)));

drop policy if exists approvals_operate on coordination.approval_requests;
create policy approvals_operate on coordination.approval_requests for all to authenticated
using (project.can_access_project(project_id))
with check (project.can_access_project(project_id));

-- CRM lead creation.
create or replace function public.create_crm_lead(input_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path=public,core,extensions,audit
as $$
declare
  org_id uuid := nullif(input_payload->>'organisation_id','')::uuid;
  contact_id uuid;
  lead_id uuid;
  lead_row public.leads%rowtype;
  source_value text := lower(coalesce(nullif(btrim(input_payload->>'source'),''),'direct'));
  status_value text := lower(coalesce(nullif(btrim(input_payload->>'status'),''),'new'));
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if org_id is null then raise exception 'organisation_required'; end if;
  if not core.has_org_role(org_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  if status_value not in ('new','qualified','nurture','won','lost') then raise exception 'unsupported_lead_status'; end if;

  if nullif(btrim(input_payload#>>'{contact,full_name}'),'') is not null then
    insert into public.contacts(
      organisation_id,full_name,company_name,email,phone,role_title,consent_email,consent_whatsapp,consent_sms
    ) values (
      org_id,btrim(input_payload#>>'{contact,full_name}'),nullif(btrim(input_payload#>>'{contact,company_name}'),''),
      nullif(btrim(input_payload#>>'{contact,email}'),''),nullif(btrim(input_payload#>>'{contact,phone}'),''),
      nullif(btrim(input_payload#>>'{contact,role_title}'),''),
      coalesce((input_payload#>>'{contact,consent_email}')::boolean,false),
      coalesce((input_payload#>>'{contact,consent_whatsapp}')::boolean,false),
      coalesce((input_payload#>>'{contact,consent_sms}')::boolean,false)
    ) returning id into contact_id;
  end if;

  insert into public.leads(
    organisation_id,contact_id,source,status,project_typology,project_location,estimated_project_value,currency,owner_user_id,next_action_at,metadata
  ) values (
    org_id,contact_id,source_value,status_value,nullif(btrim(input_payload->>'project_typology'),''),nullif(btrim(input_payload->>'project_location'),''),
    nullif(input_payload->>'estimated_project_value','')::numeric,coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),auth.uid(),
    nullif(input_payload->>'next_action_at','')::timestamptz,coalesce(input_payload->'metadata','{}'::jsonb)
  ) returning * into lead_row;
  lead_id:=lead_row.id;
  perform audit.append_event(org_id,null,'crm.lead.created','lead',lead_id,null,to_jsonb(lead_row),null,gen_random_uuid());
  return jsonb_build_object('lead_id',lead_id,'contact_id',contact_id);
end;
$$;
revoke all on function public.create_crm_lead(jsonb) from public,anon;
grant execute on function public.create_crm_lead(jsonb) to authenticated;

create or replace function public.advance_lead_to_opportunity(target_lead_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare
  l public.leads%rowtype;
  o public.opportunities%rowtype;
  probability_value numeric := coalesce(nullif(input_payload->>'probability','')::numeric,25);
begin
  select * into l from public.leads where id=target_lead_id;
  if not found then raise exception 'lead_not_found'; end if;
  if not core.has_org_role(l.organisation_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  if probability_value<0 or probability_value>100 then raise exception 'probability_out_of_range'; end if;
  insert into public.opportunities(
    organisation_id,lead_id,contact_id,project_name,stage,probability,expected_fee,currency,scope_modules,decision_due_at
  ) values (
    l.organisation_id,l.id,l.contact_id,coalesce(nullif(btrim(input_payload->>'project_name'),''),coalesce(l.project_typology,'Project Opportunity')),
    coalesce(nullif(lower(btrim(input_payload->>'stage')),''),'discovery'),probability_value,nullif(input_payload->>'expected_fee','')::numeric,
    coalesce(nullif(upper(btrim(input_payload->>'currency')),''),l.currency),coalesce(input_payload->'scope_modules','[]'::jsonb),
    nullif(input_payload->>'decision_due_at','')::timestamptz
  ) returning * into o;
  update public.leads set status='qualified',updated_at=now() where id=l.id and status='new';
  perform audit.append_event(l.organisation_id,null,'crm.opportunity.created','opportunity',o.id,null,to_jsonb(o),'Advanced from lead '||l.id::text,gen_random_uuid());
  return o.id;
end;
$$;
revoke all on function public.advance_lead_to_opportunity(uuid,jsonb) from public,anon;
grant execute on function public.advance_lead_to_opportunity(uuid,jsonb) to authenticated;

create or replace function public.create_commercial_proposal(target_opportunity_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare
  o public.opportunities%rowtype;
  proposal_id uuid;
  proposal_version integer;
  line jsonb;
  q numeric;
  r numeric;
  line_amount numeric;
  proposal_subtotal numeric:=0;
  proposal_tax numeric:=coalesce(nullif(input_payload->>'tax','')::numeric,0);
  proposal_row public.proposals%rowtype;
begin
  select * into o from public.opportunities where id=target_opportunity_id;
  if not found then raise exception 'opportunity_not_found'; end if;
  if not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'commercial_write_authority_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb))=0 then raise exception 'proposal_line_required'; end if;
  select coalesce(max(version),0)+1 into proposal_version from public.proposals where opportunity_id=o.id;
  insert into public.proposals(organisation_id,opportunity_id,version,status,currency,subtotal,tax,total,valid_until,commercial_notes,created_by)
  values(o.organisation_id,o.id,proposal_version,'draft',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),o.currency),0,0,0,nullif(input_payload->>'valid_until','')::date,coalesce(input_payload->'commercial_notes','[]'::jsonb),auth.uid())
  returning id into proposal_id;

  for line in select value from jsonb_array_elements(input_payload->'lines') loop
    if nullif(btrim(line->>'title'),'') is null or nullif(btrim(line->>'scope_code'),'') is null then raise exception 'proposal_line_title_and_scope_required'; end if;
    q:=coalesce(nullif(line->>'quantity','')::numeric,1);
    r:=coalesce(nullif(line->>'rate','')::numeric,0);
    if q<0 or r<0 then raise exception 'proposal_line_negative_value_not_allowed'; end if;
    line_amount:=round(q*r,2);
    proposal_subtotal:=proposal_subtotal+line_amount;
    insert into public.proposal_lines(proposal_id,title,scope_code,pricing_model,quantity,rate,tax_code,amount,optional,sort_order)
    values(proposal_id,btrim(line->>'title'),upper(btrim(line->>'scope_code')),coalesce(nullif(lower(btrim(line->>'pricing_model')),''),'fixed'),q,r,nullif(btrim(line->>'tax_code'),''),line_amount,coalesce((line->>'optional')::boolean,false),coalesce(nullif(line->>'sort_order','')::integer,0));
  end loop;
  if proposal_tax<0 then raise exception 'proposal_tax_negative_not_allowed'; end if;
  update public.proposals set subtotal=proposal_subtotal,tax=proposal_tax,total=proposal_subtotal+proposal_tax,updated_at=now() where id=proposal_id returning * into proposal_row;
  update public.opportunities set stage='proposal',updated_at=now() where id=o.id and stage in ('discovery','briefing');
  perform audit.append_event(o.organisation_id,null,'commercial.proposal.created','proposal',proposal_id,null,to_jsonb(proposal_row),null,gen_random_uuid());
  return proposal_id;
end;
$$;
revoke all on function public.create_commercial_proposal(uuid,jsonb) from public,anon;
grant execute on function public.create_commercial_proposal(uuid,jsonb) to authenticated;

create or replace function public.submit_proposal_for_review(target_proposal_id uuid)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare p public.proposals%rowtype; before_state jsonb;
begin
  select * into p from public.proposals where id=target_proposal_id;
  if not found then raise exception 'proposal_not_found'; end if;
  if p.created_by<>auth.uid() and not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'commercial_write_authority_required'; end if;
  if p.status<>'draft' then raise exception 'proposal_not_draft'; end if;
  before_state:=to_jsonb(p);
  update public.proposals set status='internal_review',submitted_at=now(),updated_at=now() where id=p.id returning * into p;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.submitted','proposal',p.id,before_state,to_jsonb(p),null,gen_random_uuid());
end;
$$;
revoke all on function public.submit_proposal_for_review(uuid) from public,anon;
grant execute on function public.submit_proposal_for_review(uuid) to authenticated;

create or replace function public.approve_and_send_proposal(target_proposal_id uuid,review_note text default null)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare p public.proposals%rowtype; before_state jsonb;
begin
  select * into p from public.proposals where id=target_proposal_id;
  if not found then raise exception 'proposal_not_found'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'commercial_checker_authority_required'; end if;
  if p.created_by=auth.uid() then raise exception 'maker_cannot_check_own_proposal'; end if;
  if p.status<>'internal_review' then raise exception 'proposal_not_awaiting_internal_review'; end if;
  before_state:=to_jsonb(p);
  update public.proposals set status='sent',approved_by=auth.uid(),approved_at=now(),updated_at=now(),commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','internal_review','note',review_note,'by',auth.uid(),'at',now())) where id=p.id returning * into p;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.approved_sent','proposal',p.id,before_state,to_jsonb(p),review_note,gen_random_uuid());
end;
$$;
revoke all on function public.approve_and_send_proposal(uuid,text) from public,anon;
grant execute on function public.approve_and_send_proposal(uuid,text) to authenticated;

create or replace function public.record_proposal_client_decision(target_proposal_id uuid,decision text,evidence_reference text,client_counter_offer numeric default null)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare p public.proposals%rowtype; before_state jsonb; status_value text:=lower(btrim(decision));
begin
  select * into p from public.proposals where id=target_proposal_id;
  if not found then raise exception 'proposal_not_found'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales']) then raise exception 'client_decision_recording_authority_required'; end if;
  if nullif(btrim(evidence_reference),'') is null then raise exception 'client_decision_evidence_required'; end if;
  if status_value not in ('accepted','countered','rejected') then raise exception 'unsupported_client_decision'; end if;
  if p.status not in ('sent','countered') then raise exception 'proposal_not_client_decision_eligible'; end if;
  before_state:=to_jsonb(p);
  update public.proposals set status=status_value,client_counter_offer=case when status_value='countered' then client_counter_offer else client_counter_offer end,commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','client_decision','decision',status_value,'evidence_reference',evidence_reference,'recorded_by',auth.uid(),'at',now())),updated_at=now() where id=p.id returning * into p;
  update public.opportunities set stage=case when status_value='accepted' then 'contracting' when status_value='rejected' then 'lost' else 'negotiation' end,updated_at=now() where id=p.opportunity_id;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.client_decision','proposal',p.id,before_state,to_jsonb(p),evidence_reference,gen_random_uuid());
end;
$$;
revoke all on function public.record_proposal_client_decision(uuid,text,text,numeric) from public,anon;
grant execute on function public.record_proposal_client_decision(uuid,text,text,numeric) to authenticated;

create or replace function public.create_contract_from_proposal(target_proposal_id uuid,target_project_id uuid default null,contract_snapshot jsonb default '{}'::jsonb)
returns uuid
language plpgsql
security invoker
set search_path=public,core,project,audit
as $$
declare p public.proposals%rowtype; contract_id uuid; c public.contracts%rowtype;
begin
  select * into p from public.proposals where id=target_proposal_id;
  if not found then raise exception 'proposal_not_found'; end if;
  if p.status<>'accepted' then raise exception 'proposal_must_be_client_accepted'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'contract_creation_authority_required'; end if;
  if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  insert into public.contracts(organisation_id,proposal_id,project_id,status,contract_snapshot,created_by)
  values(p.organisation_id,p.id,target_project_id,'draft',coalesce(contract_snapshot,'{}'::jsonb),auth.uid()) returning * into c;
  contract_id:=c.id;
  perform audit.append_event(p.organisation_id,target_project_id,'commercial.contract.created','contract',contract_id,null,to_jsonb(c),null,gen_random_uuid());
  return contract_id;
end;
$$;
revoke all on function public.create_contract_from_proposal(uuid,uuid,jsonb) from public,anon;
grant execute on function public.create_contract_from_proposal(uuid,uuid,jsonb) to authenticated;

create or replace function public.create_invoice_draft(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=public,core,project,audit
as $$
declare
  org_id uuid:=nullif(input_payload->>'organisation_id','')::uuid;
  project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;
  contract_id_value uuid:=nullif(input_payload->>'contract_id','')::uuid;
  invoice_id uuid;
  line jsonb;
  q numeric; r numeric; gst numeric; taxable numeric; tax_amount numeric; line_total numeric;
  subtotal_value numeric:=0; tax_value numeric:=0;
  inv public.invoices%rowtype;
begin
  if org_id is null then raise exception 'organisation_required'; end if;
  if not core.has_org_role(org_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
  if project_id_value is not null and not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(btrim(input_payload->>'invoice_number'),'') is null then raise exception 'invoice_number_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb))=0 then raise exception 'invoice_line_required'; end if;

  insert into public.invoices(organisation_id,project_id,contract_id,invoice_number,status,currency,issue_date,due_date,metadata,created_by)
  values(org_id,project_id_value,contract_id_value,btrim(input_payload->>'invoice_number'),'draft',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),
    coalesce(nullif(input_payload->>'issue_date','')::date,current_date),coalesce(nullif(input_payload->>'due_date','')::date,current_date+7),coalesce(input_payload->'metadata','{}'::jsonb),auth.uid())
  returning id into invoice_id;

  for line in select value from jsonb_array_elements(input_payload->'lines') loop
    if nullif(btrim(line->>'description'),'') is null then raise exception 'invoice_line_description_required'; end if;
    q:=coalesce(nullif(line->>'quantity','')::numeric,1); r:=coalesce(nullif(line->>'rate','')::numeric,0); gst:=coalesce(nullif(line->>'gst_rate','')::numeric,0);
    if q<0 or r<0 or gst<0 then raise exception 'invoice_negative_value_not_allowed'; end if;
    taxable:=round(q*r,2); tax_amount:=round(taxable*gst/100,2); line_total:=taxable+tax_amount;
    subtotal_value:=subtotal_value+taxable; tax_value:=tax_value+tax_amount;
    insert into public.invoice_lines(invoice_id,description,quantity,rate,taxable_amount,gst_rate,tax_amount,total,sort_order)
    values(invoice_id,btrim(line->>'description'),q,r,taxable,gst,tax_amount,line_total,coalesce(nullif(line->>'sort_order','')::integer,0));
  end loop;
  update public.invoices set subtotal=subtotal_value,tax=tax_value,total=subtotal_value+tax_value,updated_at=now() where id=invoice_id returning * into inv;
  perform audit.append_event(org_id,project_id_value,'finance.invoice.draft_created','invoice',invoice_id,null,to_jsonb(inv),null,gen_random_uuid());
  return invoice_id;
end;
$$;
revoke all on function public.create_invoice_draft(jsonb) from public,anon;
grant execute on function public.create_invoice_draft(jsonb) to authenticated;

create or replace function public.issue_invoice(target_invoice_id uuid)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare i public.invoices%rowtype; before_state jsonb;
begin
  select * into i from public.invoices where id=target_invoice_id;
  if not found then raise exception 'invoice_not_found'; end if;
  if not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
  if i.created_by=auth.uid() and not core.has_org_role(i.organisation_id,array['super_admin','org_admin']) then raise exception 'maker_cannot_issue_own_invoice'; end if;
  if i.status<>'draft' then raise exception 'invoice_not_draft'; end if;
  if i.total<=0 then raise exception 'invoice_total_must_be_positive'; end if;
  before_state:=to_jsonb(i);
  update public.invoices set status='issued',updated_at=now() where id=i.id returning * into i;
  perform audit.append_event(i.organisation_id,i.project_id,'finance.invoice.issued','invoice',i.id,before_state,to_jsonb(i),null,gen_random_uuid());
end;
$$;
revoke all on function public.issue_invoice(uuid) from public,anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

-- Work queue.
create or replace function public.create_work_task(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=operations,core,project,audit,public
as $$
declare org_id uuid:=nullif(input_payload->>'organisation_id','')::uuid; project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; task_id uuid; t operations.tasks%rowtype;
begin
  if org_id is null then raise exception 'organisation_required'; end if;
  if project_id_value is not null and not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if project_id_value is null and not core.is_internal_org_member(org_id) then raise exception 'organisation_access_required'; end if;
  if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'task_title_required'; end if;
  insert into operations.tasks(organisation_id,project_id,title,task_type,state,priority,assignee_user_id,assignee_role_code,due_at,maker_user_id,evidence_refs)
  values(org_id,project_id_value,btrim(input_payload->>'title'),coalesce(nullif(lower(btrim(input_payload->>'task_type')),''),'manual'),'open',coalesce(nullif(lower(btrim(input_payload->>'priority')),''),'normal'),nullif(input_payload->>'assignee_user_id','')::uuid,nullif(btrim(input_payload->>'assignee_role_code'),''),nullif(input_payload->>'due_at','')::timestamptz,auth.uid(),coalesce(input_payload->'evidence_refs','[]'::jsonb)) returning * into t;
  task_id:=t.id;
  perform audit.append_event(org_id,project_id_value,'operations.task.created','task',task_id,null,to_jsonb(t),null,gen_random_uuid());
  return task_id;
end;
$$;
revoke all on function public.create_work_task(jsonb) from public,anon;
grant execute on function public.create_work_task(jsonb) to authenticated;

create or replace function public.transition_work_task(target_task_id uuid,new_state text,evidence_refs jsonb default '[]'::jsonb)
returns void
language plpgsql
security invoker
set search_path=operations,core,project,audit,public
as $$
declare t operations.tasks%rowtype; before_state jsonb; state_value text:=lower(btrim(new_state));
begin
  if state_value not in ('open','in_progress','submitted','approved','rejected','cancelled') then raise exception 'unsupported_task_state'; end if;
  select * into t from operations.tasks where id=target_task_id;
  if not found then raise exception 'task_not_found'; end if;
  if t.project_id is not null and not project.can_access_project(t.project_id) then raise exception 'project_access_required'; end if;
  if t.project_id is null and not core.is_internal_org_member(t.organisation_id) then raise exception 'organisation_access_required'; end if;
  if state_value in ('approved','rejected') then
    if t.maker_user_id=auth.uid() then raise exception 'maker_cannot_check_own_task'; end if;
    if t.assignee_user_id is not null and t.assignee_user_id<>auth.uid() and not core.has_org_role(t.organisation_id,array['super_admin','org_admin']) then raise exception 'task_checker_not_assigned'; end if;
  end if;
  before_state:=to_jsonb(t);
  update operations.tasks set state=state_value,checker_user_id=case when state_value in ('approved','rejected') then auth.uid() else checker_user_id end,evidence_refs=case when evidence_refs='[]'::jsonb then operations.tasks.evidence_refs else evidence_refs end,updated_at=now() where id=t.id returning * into t;
  perform audit.append_event(t.organisation_id,t.project_id,'operations.task.'||state_value,'task',t.id,before_state,to_jsonb(t),null,gen_random_uuid());
end;
$$;
revoke all on function public.transition_work_task(uuid,text,jsonb) from public,anon;
grant execute on function public.transition_work_task(uuid,text,jsonb) to authenticated;

create or replace function public.list_work_tasks(target_organisation_id uuid,target_project_id uuid default null)
returns table(id uuid,title text,task_type text,state text,priority text,assignee_user_id uuid,assignee_role_code text,due_at timestamptz,sla_breached boolean,maker_user_id uuid,checker_user_id uuid,project_id uuid,created_at timestamptz)
language sql stable security invoker set search_path=operations,public as $$
  select t.id,t.title,t.task_type,t.state,t.priority,t.assignee_user_id,t.assignee_role_code,t.due_at,t.sla_breached,t.maker_user_id,t.checker_user_id,t.project_id,t.created_at
  from operations.tasks t
  where t.organisation_id=target_organisation_id and (target_project_id is null or t.project_id=target_project_id)
  order by case t.priority when 'urgent' then 1 when 'high' then 2 when 'normal' then 3 else 4 end,t.due_at nulls last,t.created_at desc;
$$;
revoke all on function public.list_work_tasks(uuid,uuid) from public,anon;
grant execute on function public.list_work_tasks(uuid,uuid) to authenticated;

-- Coordination issues.
create or replace function public.create_coordination_issue(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=coordination,project,core,audit,public,extensions
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; org_id uuid; issue_id uuid; issue_no text; i coordination.issues%rowtype;
begin
  if project_id_value is null then raise exception 'project_required'; end if;
  if not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  select organisation_id into org_id from project.projects where id=project_id_value;
  issue_no:=coalesce(nullif(btrim(input_payload->>'issue_number'),''),'ISS-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
  insert into coordination.issues(project_id,issue_number,issue_type,title,description,status,priority,criticality,assignee_id,due_at,bcf_topic_ref,location_ref,created_by)
  values(project_id_value,issue_no,coalesce(nullif(lower(btrim(input_payload->>'issue_type')),''),'coordination'),btrim(input_payload->>'title'),coalesce(nullif(btrim(input_payload->>'description'),''),'No description provided.'),'open',coalesce(nullif(lower(btrim(input_payload->>'priority')),''),'medium'),coalesce(nullif(upper(btrim(input_payload->>'criticality')),''),'C1'),nullif(input_payload->>'assignee_id','')::uuid,nullif(input_payload->>'due_at','')::timestamptz,nullif(btrim(input_payload->>'bcf_topic_ref'),''),nullif(btrim(input_payload->>'location_ref'),''),auth.uid()) returning * into i;
  issue_id:=i.id;
  perform audit.append_event(org_id,project_id_value,'coordination.issue.created','issue',issue_id,null,to_jsonb(i),null,gen_random_uuid());
  return issue_id;
end;
$$;
revoke all on function public.create_coordination_issue(jsonb) from public,anon;
grant execute on function public.create_coordination_issue(jsonb) to authenticated;

create or replace function public.add_issue_comment(target_issue_id uuid,comment_body text,evidence_refs jsonb default '[]'::jsonb)
returns uuid
language plpgsql
security invoker
set search_path=coordination,project,audit,public
as $$
declare i coordination.issues%rowtype; org_id uuid; comment_id uuid; c coordination.issue_comments%rowtype;
begin
  select * into i from coordination.issues where id=target_issue_id;
  if not found then raise exception 'issue_not_found'; end if;
  if not project.can_access_project(i.project_id) then raise exception 'project_access_required'; end if;
  if nullif(btrim(comment_body),'') is null then raise exception 'comment_required'; end if;
  select organisation_id into org_id from project.projects where id=i.project_id;
  insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs) values(i.id,btrim(comment_body),auth.uid(),coalesce(evidence_refs,'[]'::jsonb)) returning * into c;
  comment_id:=c.id;
  perform audit.append_event(org_id,i.project_id,'coordination.issue.comment_added','issue_comment',comment_id,null,to_jsonb(c),null,gen_random_uuid());
  return comment_id;
end;
$$;
revoke all on function public.add_issue_comment(uuid,text,jsonb) from public,anon;
grant execute on function public.add_issue_comment(uuid,text,jsonb) to authenticated;

create or replace function public.list_project_issues(target_project_id uuid)
returns table(id uuid,issue_number text,issue_type text,title text,description text,status text,priority text,criticality text,assignee_id uuid,due_at timestamptz,created_by uuid,created_at timestamptz,updated_at timestamptz)
language sql stable security invoker set search_path=coordination,public as $$
 select i.id,i.issue_number::text,i.issue_type,i.title,i.description,i.status,i.priority,i.criticality,i.assignee_id,i.due_at,i.created_by,i.created_at,i.updated_at from coordination.issues i where i.project_id=target_project_id order by i.created_at desc;
$$;
revoke all on function public.list_project_issues(uuid) from public,anon;
grant execute on function public.list_project_issues(uuid) to authenticated;

-- Approval requests. C3/C4 approval cannot be conferred by administrative role alone.
create or replace function public.request_governed_approval(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path=coordination,project,audit,public
as $$
declare project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid; org_id uuid; approval_id uuid; a coordination.approval_requests%rowtype;
begin
  if project_id_value is null then raise exception 'project_required'; end if;
  if not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(input_payload->>'resource_id','') is null then raise exception 'resource_id_required'; end if;
  select organisation_id into org_id from project.projects where id=project_id_value;
  insert into coordination.approval_requests(project_id,resource_type,resource_id,requested_from,role_required,criticality,decision,comments,requested_by)
  values(project_id_value,lower(btrim(input_payload->>'resource_type')),nullif(input_payload->>'resource_id','')::uuid,nullif(input_payload->>'requested_from','')::uuid,nullif(lower(btrim(input_payload->>'role_required')),''),coalesce(nullif(upper(btrim(input_payload->>'criticality')),''),'C1'),'pending',nullif(btrim(input_payload->>'comments'),''),auth.uid()) returning * into a;
  approval_id:=a.id;
  perform audit.append_event(org_id,project_id_value,'approval.requested','approval_request',approval_id,null,to_jsonb(a),null,gen_random_uuid());
  return approval_id;
end;
$$;
revoke all on function public.request_governed_approval(jsonb) from public,anon;
grant execute on function public.request_governed_approval(jsonb) to authenticated;

create or replace function public.decide_governed_approval(target_approval_id uuid,new_decision text,decision_comments text,reviewed_resource_hash text)
returns void
language plpgsql
security invoker
set search_path=coordination,project,core,audit,public
as $$
declare a coordination.approval_requests%rowtype; org_id uuid; before_state jsonb; decision_value text:=lower(btrim(new_decision)); role_ok boolean:=false;
begin
  if decision_value not in ('approved','approved_with_comments','rejected') then raise exception 'unsupported_approval_decision'; end if;
  select * into a from coordination.approval_requests where id=target_approval_id;
  if not found then raise exception 'approval_not_found'; end if;
  if a.decision<>'pending' then raise exception 'approval_already_decided'; end if;
  if not project.can_access_project(a.project_id) then raise exception 'project_access_required'; end if;
  if a.requested_by=auth.uid() and a.criticality in ('C2','C3','C4') then raise exception 'maker_cannot_approve_own_controlled_action'; end if;
  if a.requested_from is not null and a.requested_from<>auth.uid() then raise exception 'approval_not_assigned_to_current_user'; end if;
  if nullif(btrim(reviewed_resource_hash),'') is null then raise exception 'reviewed_resource_hash_required'; end if;

  if a.role_required is null then
    role_ok:=true;
  else
    role_ok:=exists(select 1 from project.project_members pm where pm.project_id=a.project_id and pm.user_id=auth.uid() and pm.status='active' and pm.role_code=a.role_required)
      or exists(select 1 from project.projects p where p.id=a.project_id and core.has_org_role(p.organisation_id,array[a.role_required,'super_admin','org_admin']));
  end if;
  if not role_ok then raise exception 'approval_role_authority_required'; end if;

  if a.criticality in ('C3','C4') then
    if a.role_required not in ('lead_architect','architect','structural_engineer','mep_engineer','quantity_surveyor','regulatory_reviewer') then raise exception 'professional_role_required_for_c3_c4'; end if;
    if not core.has_verified_professional_eligibility(auth.uid(),a.role_required) then raise exception 'verified_professional_eligibility_required'; end if;
  end if;

  select organisation_id into org_id from project.projects where id=a.project_id;
  before_state:=to_jsonb(a);
  update coordination.approval_requests set decision=decision_value,comments=decision_comments,decided_at=now(),decision_evidence_hash=btrim(reviewed_resource_hash) where id=a.id returning * into a;
  perform audit.append_event(org_id,a.project_id,'approval.'||decision_value,'approval_request',a.id,before_state,to_jsonb(a),decision_comments,gen_random_uuid());
end;
$$;
revoke all on function public.decide_governed_approval(uuid,text,text,text) from public,anon;
grant execute on function public.decide_governed_approval(uuid,text,text,text) to authenticated;

create or replace function public.list_project_approvals(target_project_id uuid)
returns table(id uuid,resource_type text,resource_id uuid,requested_from uuid,role_required text,criticality text,decision text,comments text,requested_by uuid,requested_at timestamptz,decided_at timestamptz,decision_evidence_hash text)
language sql stable security invoker set search_path=coordination,public as $$
 select a.id,a.resource_type,a.resource_id,a.requested_from,a.role_required,a.criticality,a.decision,a.comments,a.requested_by,a.requested_at,a.decided_at,a.decision_evidence_hash from coordination.approval_requests a where a.project_id=target_project_id order by case when a.decision='pending' then 0 else 1 end,a.requested_at desc;
$$;
revoke all on function public.list_project_approvals(uuid) from public,anon;
grant execute on function public.list_project_approvals(uuid) to authenticated;

commit;
