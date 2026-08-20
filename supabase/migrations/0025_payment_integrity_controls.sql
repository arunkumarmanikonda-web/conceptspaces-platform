begin;

alter table public.invoices add column if not exists issued_by uuid references auth.users(id);
alter table public.invoices add column if not exists issued_at timestamptz;
alter table public.payment_transactions add column if not exists applied_at timestamptz;

-- Audit events invoked by trusted service processes are labelled system rather than human.
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
  actor uuid:=auth.uid();
begin
  if target_organisation_id is null then raise exception 'audit_organisation_required'; end if;
  if target_action is null or btrim(target_action)='' then raise exception 'audit_action_required'; end if;
  if target_resource_type is null or btrim(target_resource_type)='' then raise exception 'audit_resource_type_required'; end if;
  perform pg_advisory_xact_lock(hashtext('concept_spaces_audit_' || target_organisation_id::text));
  select event_hash into previous from audit.events where organisation_id=target_organisation_id order by created_at desc,id desc limit 1;
  payload := concat_ws('|',coalesce(previous,''),event_id::text,target_organisation_id::text,coalesce(target_project_id::text,''),coalesce(actor::text,''),target_action,target_resource_type,coalesce(target_resource_id::text,''),coalesce(target_before_state::text,''),coalesce(target_after_state::text,''),coalesce(target_reason,''),target_correlation_id::text,event_time::text);
  computed := encode(extensions.digest(payload,'sha256'),'hex');
  insert into audit.events(id,organisation_id,project_id,actor_id,actor_type,action,resource_type,resource_id,before_state,after_state,reason,correlation_id,previous_hash,event_hash,created_at)
  values(event_id,target_organisation_id,target_project_id,actor,case when actor is null then 'system' else 'human' end,target_action,target_resource_type,target_resource_id,target_before_state,target_after_state,target_reason,target_correlation_id,previous,computed,event_time);
  return event_id;
end;
$$;
revoke all on function audit.append_event(uuid,uuid,text,text,uuid,jsonb,jsonb,text,uuid) from public,anon,authenticated;

-- Any invoice linked to a contract must reference the same organisation and an active contract.
create or replace function finance.guard_invoice_contract_state()
returns trigger
language plpgsql
security definer
set search_path=public,finance
as $$
begin
  if new.contract_id is not null and not exists(
    select 1 from public.contracts c
    where c.id=new.contract_id and c.organisation_id=new.organisation_id and c.status='active'
  ) then
    raise exception 'invoice_contract_must_be_active_and_same_organisation';
  end if;
  return new;
end;
$$;

drop trigger if exists concept_spaces_invoice_contract_guard on public.invoices;
create trigger concept_spaces_invoice_contract_guard
before insert or update of contract_id,organisation_id on public.invoices
for each row execute function finance.guard_invoice_contract_state();

-- Paid states can only be reached inside the verified payment application function.
create or replace function finance.guard_invoice_paid_state()
returns trigger
language plpgsql
security definer
set search_path=public,finance
as $$
begin
  if old.status is distinct from new.status and new.status in ('part_paid','paid') then
    if coalesce(current_setting('conceptspaces.verified_payment_event',true),'off')<>'on' then
      raise exception 'invoice_paid_state_requires_verified_payment_event';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists concept_spaces_invoice_paid_state_guard on public.invoices;
create trigger concept_spaces_invoice_paid_state_guard
before update of status on public.invoices
for each row execute function finance.guard_invoice_paid_state();

-- Strict maker-checker for invoice issue. Administrative role does not collapse the checker boundary.
create or replace function public.issue_invoice(target_invoice_id uuid)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare i public.invoices%rowtype; before_state jsonb;
begin
  select * into i from public.invoices where id=target_invoice_id for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
  if i.created_by=auth.uid() then raise exception 'maker_cannot_issue_own_invoice'; end if;
  if i.status<>'draft' then raise exception 'invoice_not_draft'; end if;
  if i.total<=0 then raise exception 'invoice_total_must_be_positive'; end if;
  before_state:=to_jsonb(i);
  update public.invoices set status='issued',issued_by=auth.uid(),issued_at=now(),updated_at=now() where id=i.id returning * into i;
  perform audit.append_event(i.organisation_id,i.project_id,'finance.invoice.issued','invoice',i.id,before_state,to_jsonb(i),null,gen_random_uuid());
end;
$$;
revoke all on function public.issue_invoice(uuid) from public,anon;
grant execute on function public.issue_invoice(uuid) to authenticated;

-- Service-only application of a captured provider payment. Idempotent via applied_at.
create or replace function finance.apply_captured_payment(target_payment_transaction_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=finance,public,audit
as $$
declare
  tx public.payment_transactions%rowtype;
  inv public.invoices%rowtype;
  before_state jsonb;
  new_paid numeric;
  new_status text;
begin
  select * into tx from public.payment_transactions where id=target_payment_transaction_id for update;
  if not found then raise exception 'payment_transaction_not_found'; end if;
  if tx.applied_at is not null then
    return jsonb_build_object('invoice_id',tx.invoice_id,'already_applied',true,'applied_at',tx.applied_at);
  end if;
  if tx.status<>'captured' then raise exception 'payment_transaction_not_captured'; end if;
  if tx.invoice_id is null then raise exception 'captured_payment_invoice_required'; end if;
  select * into inv from public.invoices where id=tx.invoice_id for update;
  if not found then raise exception 'invoice_not_found'; end if;
  if inv.organisation_id<>tx.organisation_id then raise exception 'payment_invoice_organisation_mismatch'; end if;
  if upper(inv.currency)<>upper(tx.currency) then raise exception 'payment_invoice_currency_mismatch'; end if;
  if inv.status not in ('issued','part_paid','overdue') then raise exception 'invoice_not_payment_eligible'; end if;
  if tx.amount<=0 then raise exception 'captured_payment_amount_invalid'; end if;

  before_state:=to_jsonb(inv);
  new_paid:=least(inv.total,inv.amount_paid+tx.amount);
  new_status:=case when new_paid>=inv.total then 'paid' else 'part_paid' end;
  perform set_config('conceptspaces.verified_payment_event','on',true);
  update public.invoices set amount_paid=new_paid,status=new_status,updated_at=now() where id=inv.id returning * into inv;
  update public.payment_transactions set applied_at=now(),updated_at=now() where id=tx.id;
  perform audit.append_event(inv.organisation_id,inv.project_id,'finance.payment.applied','invoice',inv.id,before_state,to_jsonb(inv),'Captured provider transaction '||tx.id::text,gen_random_uuid());
  return jsonb_build_object('invoice_id',inv.id,'amount_paid',inv.amount_paid,'status',inv.status,'already_applied',false);
end;
$$;
revoke all on function finance.apply_captured_payment(uuid) from public,anon,authenticated;
grant execute on function finance.apply_captured_payment(uuid) to service_role;

comment on function finance.apply_captured_payment(uuid) is 'Service-only, idempotent application of a captured provider payment to invoice state. Authenticated users cannot call this function.';

commit;
