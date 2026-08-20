begin;

create or replace function public.create_crm_lead(input_payload jsonb)
returns jsonb
language plpgsql
security invoker
set search_path = public, core, extensions, audit
as $$
declare
  org_id uuid := nullif(input_payload->>'organisation_id','')::uuid;
  contact_id uuid;
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
      organisation_id, full_name, company_name, email, phone, role_title,
      consent_email, consent_whatsapp, consent_sms
    ) values (
      org_id,
      btrim(input_payload#>>'{contact,full_name}'),
      nullif(btrim(input_payload#>>'{contact,company_name}'),''),
      nullif(btrim(input_payload#>>'{contact,email}'),''),
      nullif(btrim(input_payload#>>'{contact,phone}'),''),
      nullif(btrim(input_payload#>>'{contact,role_title}'),''),
      coalesce((input_payload#>>'{contact,consent_email}')::boolean,false),
      coalesce((input_payload#>>'{contact,consent_whatsapp}')::boolean,false),
      coalesce((input_payload#>>'{contact,consent_sms}')::boolean,false)
    ) returning id into contact_id;
  end if;

  insert into public.leads(
    organisation_id, contact_id, source, status, project_typology, project_location,
    estimated_project_value, currency, owner_user_id, next_action_at, metadata
  ) values (
    org_id, contact_id, source_value, status_value,
    nullif(btrim(input_payload->>'project_typology'),''),
    nullif(btrim(input_payload->>'project_location'),''),
    nullif(input_payload->>'estimated_project_value','')::numeric,
    coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),
    auth.uid(), nullif(input_payload->>'next_action_at','')::timestamptz,
    coalesce(input_payload->'metadata','{}'::jsonb)
  ) returning * into lead_row;

  perform audit.append_event(org_id,null,'crm.lead.created','lead',lead_row.id,null,to_jsonb(lead_row),null,gen_random_uuid());
  return jsonb_build_object('lead_id',lead_row.id,'contact_id',contact_id);
end;
$$;
revoke all on function public.create_crm_lead(jsonb) from public, anon;
grant execute on function public.create_crm_lead(jsonb) to authenticated;

create or replace function public.advance_lead_to_opportunity(target_lead_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  l public.leads%rowtype;
  o public.opportunities%rowtype;
  probability_value numeric := coalesce(nullif(input_payload->>'probability','')::numeric,25);
  stage_value text := lower(coalesce(nullif(btrim(input_payload->>'stage'),''),'discovery'));
begin
  select * into l from public.leads where id = target_lead_id;
  if not found then raise exception 'lead_not_found'; end if;
  if not core.has_org_role(l.organisation_id,array['super_admin','org_admin','sales','project_manager']) then raise exception 'crm_write_authority_required'; end if;
  if probability_value < 0 or probability_value > 100 then raise exception 'probability_out_of_range'; end if;
  if stage_value not in ('discovery','briefing','proposal','negotiation','contracting','won','lost') then raise exception 'unsupported_opportunity_stage'; end if;

  insert into public.opportunities(
    organisation_id, lead_id, contact_id, project_name, stage, probability,
    expected_fee, currency, scope_modules, decision_due_at
  ) values (
    l.organisation_id, l.id, l.contact_id,
    coalesce(nullif(btrim(input_payload->>'project_name'),''),coalesce(l.project_typology,'Project Opportunity')),
    stage_value, probability_value, nullif(input_payload->>'expected_fee','')::numeric,
    coalesce(nullif(upper(btrim(input_payload->>'currency')),''),l.currency),
    coalesce(input_payload->'scope_modules','[]'::jsonb),
    nullif(input_payload->>'decision_due_at','')::timestamptz
  ) returning * into o;

  update public.leads set status='qualified',updated_at=now()
  where id=l.id and status='new';
  perform audit.append_event(l.organisation_id,null,'crm.opportunity.created','opportunity',o.id,null,to_jsonb(o),'Advanced from lead '||l.id::text,gen_random_uuid());
  return o.id;
end;
$$;
revoke all on function public.advance_lead_to_opportunity(uuid,jsonb) from public, anon;
grant execute on function public.advance_lead_to_opportunity(uuid,jsonb) to authenticated;

create or replace function public.create_commercial_proposal(target_opportunity_id uuid,input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  o public.opportunities%rowtype;
  proposal_id uuid;
  proposal_version integer;
  line jsonb;
  q numeric;
  r numeric;
  line_amount numeric;
  proposal_subtotal numeric := 0;
  proposal_tax numeric := coalesce(nullif(input_payload->>'tax','')::numeric,0);
  proposal_row public.proposals%rowtype;
  pricing_value text;
begin
  select * into o from public.opportunities where id=target_opportunity_id;
  if not found then raise exception 'opportunity_not_found'; end if;
  if not core.has_org_role(o.organisation_id,array['super_admin','org_admin','sales','finance']) then raise exception 'commercial_write_authority_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb)) = 0 then
    raise exception 'proposal_line_required';
  end if;
  if proposal_tax < 0 then raise exception 'proposal_tax_negative_not_allowed'; end if;

  select coalesce(max(version),0)+1 into proposal_version
  from public.proposals where opportunity_id=o.id;

  insert into public.proposals(
    organisation_id, opportunity_id, version, status, currency, subtotal, tax,
    total, valid_until, commercial_notes, created_by
  ) values (
    o.organisation_id,o.id,proposal_version,'draft',
    coalesce(nullif(upper(btrim(input_payload->>'currency')),''),o.currency),
    0,0,0,nullif(input_payload->>'valid_until','')::date,
    coalesce(input_payload->'commercial_notes','[]'::jsonb),auth.uid()
  ) returning id into proposal_id;

  for line in select value from jsonb_array_elements(input_payload->'lines') loop
    if nullif(btrim(line->>'title'),'') is null or nullif(btrim(line->>'scope_code'),'') is null then
      raise exception 'proposal_line_title_and_scope_required';
    end if;
    q := coalesce(nullif(line->>'quantity','')::numeric,1);
    r := coalesce(nullif(line->>'rate','')::numeric,0);
    pricing_value := lower(coalesce(nullif(btrim(line->>'pricing_model'),''),'fixed'));
    if q < 0 or r < 0 then raise exception 'proposal_line_negative_value_not_allowed'; end if;
    if pricing_value not in ('fixed','percent','sqft','per_key','hourly','retainer','milestone','subscription','hybrid') then raise exception 'unsupported_pricing_model'; end if;
    line_amount := round(q*r,2);
    proposal_subtotal := proposal_subtotal + line_amount;
    insert into public.proposal_lines(
      proposal_id,title,scope_code,pricing_model,quantity,rate,tax_code,amount,optional,sort_order
    ) values (
      proposal_id,btrim(line->>'title'),upper(btrim(line->>'scope_code')),pricing_value,
      q,r,nullif(btrim(line->>'tax_code'),''),line_amount,
      coalesce((line->>'optional')::boolean,false),coalesce(nullif(line->>'sort_order','')::integer,0)
    );
  end loop;

  update public.proposals
  set subtotal=proposal_subtotal,tax=proposal_tax,total=proposal_subtotal+proposal_tax,updated_at=now()
  where id=proposal_id returning * into proposal_row;
  update public.opportunities set stage='proposal',updated_at=now()
  where id=o.id and stage in ('discovery','briefing');
  perform audit.append_event(o.organisation_id,null,'commercial.proposal.created','proposal',proposal_id,null,to_jsonb(proposal_row),null,gen_random_uuid());
  return proposal_id;
end;
$$;
revoke all on function public.create_commercial_proposal(uuid,jsonb) from public, anon;
grant execute on function public.create_commercial_proposal(uuid,jsonb) to authenticated;

create or replace function public.submit_proposal_for_review(target_proposal_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  p public.proposals%rowtype;
  before_state jsonb;
begin
  select * into p from public.proposals where id=target_proposal_id for update;
  if not found then raise exception 'proposal_not_found'; end if;
  if p.created_by <> auth.uid()
     and not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales','finance']) then
    raise exception 'commercial_write_authority_required';
  end if;
  if p.status <> 'draft' then raise exception 'proposal_not_draft'; end if;
  before_state := to_jsonb(p);
  update public.proposals set status='internal_review',submitted_at=now(),updated_at=now()
  where id=p.id returning * into p;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.submitted','proposal',p.id,before_state,to_jsonb(p),null,gen_random_uuid());
end;
$$;
revoke all on function public.submit_proposal_for_review(uuid) from public, anon;
grant execute on function public.submit_proposal_for_review(uuid) to authenticated;

create or replace function public.approve_and_send_proposal(target_proposal_id uuid,review_note text default null)
returns void
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  p public.proposals%rowtype;
  before_state jsonb;
begin
  select * into p from public.proposals where id=target_proposal_id for update;
  if not found then raise exception 'proposal_not_found'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'commercial_checker_authority_required'; end if;
  if p.created_by = auth.uid() then raise exception 'maker_cannot_check_own_proposal'; end if;
  if p.status <> 'internal_review' then raise exception 'proposal_not_awaiting_internal_review'; end if;
  before_state := to_jsonb(p);
  update public.proposals
  set status='sent',approved_by=auth.uid(),approved_at=now(),updated_at=now(),
      commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','internal_review','note',review_note,'by',auth.uid(),'at',now()))
  where id=p.id returning * into p;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.approved_sent','proposal',p.id,before_state,to_jsonb(p),review_note,gen_random_uuid());
end;
$$;
revoke all on function public.approve_and_send_proposal(uuid,text) from public, anon;
grant execute on function public.approve_and_send_proposal(uuid,text) to authenticated;

create or replace function public.record_proposal_client_decision(
  target_proposal_id uuid,
  decision text,
  evidence_reference text,
  client_counter_offer numeric default null
)
returns void
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  p public.proposals%rowtype;
  before_state jsonb;
  status_value text := lower(btrim(decision));
  counter_value numeric := client_counter_offer;
begin
  select * into p from public.proposals where id=target_proposal_id for update;
  if not found then raise exception 'proposal_not_found'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','sales']) then raise exception 'client_decision_recording_authority_required'; end if;
  if nullif(btrim(evidence_reference),'') is null then raise exception 'client_decision_evidence_required'; end if;
  if status_value not in ('accepted','countered','rejected') then raise exception 'unsupported_client_decision'; end if;
  if p.status not in ('sent','countered') then raise exception 'proposal_not_client_decision_eligible'; end if;
  if status_value='countered' and (counter_value is null or counter_value < 0) then raise exception 'counter_offer_required'; end if;
  before_state := to_jsonb(p);
  update public.proposals
  set status=status_value,
      client_counter_offer=case when status_value='countered' then counter_value else null end,
      commercial_notes=commercial_notes||jsonb_build_array(jsonb_build_object('type','client_decision','decision',status_value,'evidence_reference',evidence_reference,'recorded_by',auth.uid(),'at',now())),
      updated_at=now()
  where id=p.id returning * into p;
  update public.opportunities
  set stage=case when status_value='accepted' then 'contracting' when status_value='rejected' then 'lost' else 'negotiation' end,
      updated_at=now()
  where id=p.opportunity_id;
  perform audit.append_event(p.organisation_id,null,'commercial.proposal.client_decision','proposal',p.id,before_state,to_jsonb(p),evidence_reference,gen_random_uuid());
end;
$$;
revoke all on function public.record_proposal_client_decision(uuid,text,text,numeric) from public, anon;
grant execute on function public.record_proposal_client_decision(uuid,text,text,numeric) to authenticated;

create or replace function public.create_contract_from_proposal(
  target_proposal_id uuid,
  target_project_id uuid default null,
  contract_snapshot jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security invoker
set search_path = public, core, project, audit
as $$
declare
  p public.proposals%rowtype;
  c public.contracts%rowtype;
begin
  select * into p from public.proposals where id=target_proposal_id;
  if not found then raise exception 'proposal_not_found'; end if;
  if p.status <> 'accepted' then raise exception 'proposal_must_be_client_accepted'; end if;
  if not core.has_org_role(p.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'contract_creation_authority_required'; end if;
  if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  insert into public.contracts(organisation_id,proposal_id,project_id,status,contract_snapshot,created_by)
  values(p.organisation_id,p.id,target_project_id,'draft',coalesce(contract_snapshot,'{}'::jsonb),auth.uid())
  returning * into c;
  perform audit.append_event(p.organisation_id,target_project_id,'commercial.contract.created','contract',c.id,null,to_jsonb(c),null,gen_random_uuid());
  return c.id;
end;
$$;
revoke all on function public.create_contract_from_proposal(uuid,uuid,jsonb) from public, anon;
grant execute on function public.create_contract_from_proposal(uuid,uuid,jsonb) to authenticated;

create or replace function public.create_invoice_draft(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = public, core, project, audit
as $$
declare
  org_id uuid := nullif(input_payload->>'organisation_id','')::uuid;
  project_id_value uuid := nullif(input_payload->>'project_id','')::uuid;
  contract_id_value uuid := nullif(input_payload->>'contract_id','')::uuid;
  invoice_id uuid;
  line jsonb;
  q numeric;
  r numeric;
  gst numeric;
  taxable numeric;
  tax_amount numeric;
  line_total numeric;
  subtotal_value numeric := 0;
  tax_value numeric := 0;
  inv public.invoices%rowtype;
begin
  if org_id is null then raise exception 'organisation_required'; end if;
  if not core.has_org_role(org_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
  if project_id_value is not null and not project.can_access_project(project_id_value) then raise exception 'project_access_required'; end if;
  if nullif(btrim(input_payload->>'invoice_number'),'') is null then raise exception 'invoice_number_required'; end if;
  if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb)) = 0 then raise exception 'invoice_line_required'; end if;

  insert into public.invoices(
    organisation_id,project_id,contract_id,invoice_number,status,currency,
    issue_date,due_date,metadata,created_by
  ) values (
    org_id,project_id_value,contract_id_value,btrim(input_payload->>'invoice_number'),'draft',
    coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),
    coalesce(nullif(input_payload->>'issue_date','')::date,current_date),
    coalesce(nullif(input_payload->>'due_date','')::date,current_date+7),
    coalesce(input_payload->'metadata','{}'::jsonb),auth.uid()
  ) returning id into invoice_id;

  for line in select value from jsonb_array_elements(input_payload->'lines') loop
    if nullif(btrim(line->>'description'),'') is null then raise exception 'invoice_line_description_required'; end if;
    q := coalesce(nullif(line->>'quantity','')::numeric,1);
    r := coalesce(nullif(line->>'rate','')::numeric,0);
    gst := coalesce(nullif(line->>'gst_rate','')::numeric,0);
    if q < 0 or r < 0 or gst < 0 then raise exception 'invoice_negative_value_not_allowed'; end if;
    taxable := round(q*r,2);
    tax_amount := round(taxable*gst/100,2);
    line_total := taxable+tax_amount;
    subtotal_value := subtotal_value+taxable;
    tax_value := tax_value+tax_amount;
    insert into public.invoice_lines(invoice_id,description,quantity,rate,taxable_amount,gst_rate,tax_amount,total,sort_order)
    values(invoice_id,btrim(line->>'description'),q,r,taxable,gst,tax_amount,line_total,coalesce(nullif(line->>'sort_order','')::integer,0));
  end loop;

  update public.invoices set subtotal=subtotal_value,tax=tax_value,total=subtotal_value+tax_value,updated_at=now()
  where id=invoice_id returning * into inv;
  perform audit.append_event(org_id,project_id_value,'finance.invoice.draft_created','invoice',invoice_id,null,to_jsonb(inv),null,gen_random_uuid());
  return invoice_id;
end;
$$;
revoke all on function public.create_invoice_draft(jsonb) from public, anon;
grant execute on function public.create_invoice_draft(jsonb) to authenticated;

create or replace function public.issue_invoice(target_invoice_id uuid)
returns void
language plpgsql
security invoker
set search_path = public, core, audit
as $$
declare
  i public.invoices%rowtype;
  before_state jsonb;
begin
  select * into i from public.invoices where id=target_invoice_id for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
  if i.created_by = auth.uid() then raise exception 'maker_cannot_issue_own_invoice'; end if;
  if i.status <> 'draft' then raise exception 'invoice_not_draft'; end if;
  if i.total <= 0 then raise exception 'invoice_total_must_be_positive'; end if;
  before_state := to_jsonb(i);
  update public.invoices set status='issued',updated_at=now() where id=i.id returning * into i;
  perform audit.append_event(i.organisation_id,i.project_id,'finance.invoice.issued','invoice',i.id,before_state,to_jsonb(i),null,gen_random_uuid());
end;
$$;
revoke all on function public.issue_invoice(uuid) from public, anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

commit;
