begin;

-- Version statutory rules explicitly so determinations retain exact rule/source/version provenance.
alter table finance.tax_rules add column if not exists version integer;
with ranked as (
  select id,row_number() over(partition by rule_set,code order by effective_from,created_at,id)::int as v
  from finance.tax_rules
)
update finance.tax_rules t set version=r.v from ranked r where r.id=t.id and t.version is null;
alter table finance.tax_rules alter column version set not null;
create unique index if not exists tax_rules_rule_set_code_version_uidx on finance.tax_rules(rule_set,code,version);

create or replace function finance.guard_published_tax_rule()
returns trigger language plpgsql security definer set search_path='finance','pg_temp' as $$
begin
 if old.publication_status='published' and current_setting('conceptspaces.tax_phase',true)<>'retire' then raise exception 'PUBLISHED_TAX_RULE_IMMUTABLE';end if;
 if old.publication_status='published' and (new.rule_set is distinct from old.rule_set or new.code is distinct from old.code or new.version is distinct from old.version or new.jurisdiction is distinct from old.jurisdiction or new.effective_from is distinct from old.effective_from or new.effective_until is distinct from old.effective_until or new.priority is distinct from old.priority or new.conditions is distinct from old.conditions or new.outcome is distinct from old.outcome or new.source_reference is distinct from old.source_reference or new.rule_hash is distinct from old.rule_hash) then raise exception 'PUBLISHED_TAX_RULE_CONTENT_IMMUTABLE';end if;
 return new;
end;$$;

create or replace function public.create_tax_rule(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='finance','core','audit','extensions','auth','pg_temp' as $$
declare r finance.tax_rules%rowtype;prior finance.tax_rules%rowtype;h text;ef date:=nullif(input_payload->>'effective_from','')::date;eu date:=nullif(input_payload->>'effective_until','')::date;v int;
begin
 if auth.uid() is null or not core.is_platform_admin() then raise exception 'platform_admin_required';end if;
 if nullif(btrim(input_payload->>'rule_set'),'') is null or nullif(btrim(input_payload->>'code'),'') is null or ef is null or nullif(btrim(input_payload->>'source_reference'),'') is null then raise exception 'tax_rule_core_fields_required';end if;
 if eu is not null and eu<ef then raise exception 'tax_rule_effective_range_invalid';end if;
 if coalesce(input_payload->'outcome','{}'::jsonb)='{}'::jsonb then raise exception 'tax_rule_outcome_required';end if;
 select * into prior from finance.tax_rules where rule_set=btrim(input_payload->>'rule_set') and code::text=btrim(input_payload->>'code') and publication_status='published' order by version desc,effective_from desc limit 1;
 select coalesce(max(version),0)+1 into v from finance.tax_rules where rule_set=btrim(input_payload->>'rule_set') and code::text=btrim(input_payload->>'code');
 h:=encode(extensions.digest(jsonb_build_object('rule_set',btrim(input_payload->>'rule_set'),'code',btrim(input_payload->>'code'),'version',v,'jurisdiction',coalesce(nullif(btrim(input_payload->>'jurisdiction'),''),'IN'),'effective_from',ef,'effective_until',eu,'priority',coalesce(nullif(input_payload->>'priority','')::int,100),'conditions',coalesce(input_payload->'conditions','{}'::jsonb),'outcome',input_payload->'outcome','source_reference',btrim(input_payload->>'source_reference'),'supersedes_id',prior.id)::text,'sha256'),'hex');
 perform set_config('conceptspaces.tax_phase','draft',true);
 insert into finance.tax_rules(rule_set,code,version,jurisdiction,effective_from,effective_until,priority,conditions,outcome,source_reference,publication_status,created_by,rule_hash,supersedes_id)
 values(btrim(input_payload->>'rule_set'),btrim(input_payload->>'code'),v,coalesce(nullif(btrim(input_payload->>'jurisdiction'),''),'IN'),ef,eu,coalesce(nullif(input_payload->>'priority','')::int,100),coalesce(input_payload->'conditions','{}'::jsonb),input_payload->'outcome',btrim(input_payload->>'source_reference'),'draft',auth.uid(),h,prior.id) returning * into r;
 perform audit.append_event((select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1),null,'tax.rule_drafted','tax_rule',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;

-- Determinations are append-only evidence records derived from published effective-dated rules.
grant insert on finance.tax_determinations to authenticated;
drop policy if exists tax_determinations_governed_insert on finance.tax_determinations;
create policy tax_determinations_governed_insert on finance.tax_determinations for insert to authenticated
with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.tax_phase',true)='determine');

create or replace function public.determine_tax(target_organisation_id uuid,target_transaction_date date,target_source_type text,target_source_id uuid,target_context jsonb)
returns uuid language plpgsql security invoker set search_path='finance','core','audit','auth','pg_temp' as $$
declare d finance.tax_determinations%rowtype;rules jsonb;components jsonb;explanation jsonb;status_value text;jur text:=coalesce(nullif(btrim(target_context->>'jurisdiction'),''),'IN');
begin
 if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required';end if;
 if target_transaction_date is null or nullif(btrim(target_source_type),'') is null then raise exception 'tax_transaction_date_source_required';end if;
 select coalesce(jsonb_agg(jsonb_build_object('rule_id',r.id,'rule_set',r.rule_set,'code',r.code::text,'version',r.version,'rule_hash',r.rule_hash,'source_reference',r.source_reference,'effective_from',r.effective_from,'effective_until',r.effective_until,'priority',r.priority,'conditions',r.conditions,'outcome',r.outcome) order by r.priority,r.rule_set,r.code::text,r.version),'[]'::jsonb),
        coalesce(jsonb_agg(r.outcome order by r.priority,r.rule_set,r.code::text,r.version),'[]'::jsonb),
        coalesce(jsonb_agg(jsonb_build_object('rule_id',r.id,'reason','Published rule matched transaction context','source_reference',r.source_reference,'version',r.version,'rule_hash',r.rule_hash) order by r.priority,r.rule_set,r.code::text,r.version),'[]'::jsonb)
 into rules,components,explanation
 from finance.tax_rules r
 where r.publication_status='published' and upper(r.jurisdiction)=upper(jur) and r.effective_from<=target_transaction_date and (r.effective_until is null or r.effective_until>=target_transaction_date) and coalesce(target_context,'{}'::jsonb) @> r.conditions;
 status_value:=case when jsonb_array_length(rules)=0 then 'not_verified' else 'determined' end;
 perform set_config('conceptspaces.tax_phase','determine',true);
 insert into finance.tax_determinations(organisation_id,transaction_date,source_type,source_id,context,rule_ids,components,status,explanation)
 values(target_organisation_id,target_transaction_date,btrim(target_source_type),target_source_id,coalesce(target_context,'{}'::jsonb),rules,components,status_value,case when status_value='not_verified' then jsonb_build_array(jsonb_build_object('reason','No published effective rule matched the supplied context','jurisdiction',jur)) else explanation end) returning * into d;
 perform audit.append_event(target_organisation_id,null,'tax.rule_resolved','tax_determination',d.id,null,to_jsonb(d),case when status_value='determined' then rules::text else 'NOT_VERIFIED' end,gen_random_uuid());return d.id;
end;$$;
revoke all on function public.determine_tax(uuid,date,text,uuid,jsonb) from public,anon;grant execute on function public.determine_tax(uuid,date,text,uuid,jsonb) to authenticated;

-- Contract milestone authority at invoice issue.
alter table public.invoices add column if not exists milestone_code text;
alter table public.invoices add column if not exists milestone_authority_id uuid;
alter table public.invoices add column if not exists milestone_gate_snapshot jsonb not null default '{}'::jsonb;
alter table public.invoices add column if not exists milestone_gate_hash text;
alter table public.invoices add column if not exists tax_determination_id uuid references finance.tax_determinations(id) on delete restrict;

create table if not exists finance.invoice_milestone_authorities(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 invoice_id uuid not null references public.invoices(id) on delete cascade,
 contract_id uuid not null references public.contracts(id) on delete restrict,
 milestone_code text not null,
 authority_type text not null check(authority_type in ('evidence_satisfied','exception_approved')),
 evidence_reference text not null,
 evidence_hash text not null,
 reason text not null,
 created_by uuid references auth.users(id) on delete set null,
 created_at timestamptz not null default now(),
 unique(invoice_id,authority_type)
);
alter table finance.invoice_milestone_authorities enable row level security;
grant select,insert on finance.invoice_milestone_authorities to authenticated;
drop policy if exists invoice_milestone_authorities_read on finance.invoice_milestone_authorities;
create policy invoice_milestone_authorities_read on finance.invoice_milestone_authorities for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists invoice_milestone_authorities_insert on finance.invoice_milestone_authorities;
create policy invoice_milestone_authorities_insert on finance.invoice_milestone_authorities for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true)='milestone_authority');

create or replace function public.record_invoice_milestone_authority(target_invoice_id uuid,target_authority_type text,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','finance','core','audit','extensions','auth','pg_temp' as $$
declare i public.invoices%rowtype;c public.contracts%rowtype;m jsonb;a finance.invoice_milestone_authorities%rowtype;t text:=lower(btrim(target_authority_type));h text;
begin
 select * into i from public.invoices where id=target_invoice_id for update;if not found or i.status<>'draft' then raise exception 'draft_invoice_required';end if;
 if i.contract_id is null or nullif(btrim(i.milestone_code),'') is null then raise exception 'contract_milestone_invoice_required';end if;
 if auth.uid() is null or not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required';end if;
 select * into c from public.contracts where id=i.contract_id and organisation_id=i.organisation_id and status='active';if not found then raise exception 'active_contract_required';end if;
 select value into m from jsonb_array_elements(coalesce(c.contract_snapshot->'milestones','[]'::jsonb)) where value->>'code'=i.milestone_code limit 1;if m is null then raise exception 'invoice_milestone_not_in_executed_contract';end if;
 if t not in ('evidence_satisfied','exception_approved') then raise exception 'milestone_authority_type_invalid';end if;
 if nullif(btrim(input_payload->>'evidence_reference'),'') is null or lower(coalesce(input_payload->>'evidence_hash','')) !~ '^[0-9a-f]{64}$' or nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'milestone_authority_evidence_reason_required';end if;
 if t='exception_approved' and i.created_by=auth.uid() then raise exception 'independent_milestone_exception_approval_required';end if;
 h:=lower(input_payload->>'evidence_hash');perform set_config('conceptspaces.finance_phase','milestone_authority',true);
 insert into finance.invoice_milestone_authorities(organisation_id,invoice_id,contract_id,milestone_code,authority_type,evidence_reference,evidence_hash,reason,created_by)
 values(i.organisation_id,i.id,c.id,i.milestone_code,t,btrim(input_payload->>'evidence_reference'),h,btrim(input_payload->>'reason'),auth.uid()) returning * into a;
 perform audit.append_event(i.organisation_id,i.project_id,'finance.invoice_milestone_authority_recorded','invoice_milestone_authority',a.id,null,to_jsonb(a),h,gen_random_uuid());return a.id;
end;$$;
revoke all on function public.record_invoice_milestone_authority(uuid,text,jsonb) from public,anon;grant execute on function public.record_invoice_milestone_authority(uuid,text,jsonb) to authenticated;

create or replace function finance.evaluate_invoice_milestone_gate(target_invoice_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','finance','core','auth','pg_temp' as $$
declare i public.invoices%rowtype;c public.contracts%rowtype;m jsonb;tr jsonb;kind text;ref text;a finance.invoice_milestone_authorities%rowtype;satisfied boolean:=false;reason text;authority_id uuid;
begin
 select * into i from public.invoices where id=target_invoice_id;if not found then raise exception 'invoice_not_found';end if;
 if i.contract_id is null then return jsonb_build_object('passed',true,'reason','non_contract_invoice');end if;
 if nullif(btrim(i.milestone_code),'') is null then return jsonb_build_object('passed',false,'reason','contract_invoice_milestone_code_required');end if;
 select * into c from public.contracts where id=i.contract_id and organisation_id=i.organisation_id and status='active';if not found then return jsonb_build_object('passed',false,'reason','active_contract_required');end if;
 select value into m from jsonb_array_elements(coalesce(c.contract_snapshot->'milestones','[]'::jsonb)) where value->>'code'=i.milestone_code limit 1;if m is null then return jsonb_build_object('passed',false,'reason','milestone_not_in_executed_contract','milestone_code',i.milestone_code);end if;
 tr:=coalesce(m->'trigger','{}'::jsonb);kind:=lower(coalesce(tr->>'kind',''));ref:=tr->>'ref';
 select * into a from finance.invoice_milestone_authorities x where x.invoice_id=i.id and x.authority_type='exception_approved' order by x.created_at desc limit 1;
 if found then return jsonb_build_object('passed',true,'reason','authorised_exception','authority_id',a.id,'milestone',m,'trigger',tr,'evidence_reference',a.evidence_reference,'evidence_hash',a.evidence_hash);end if;
 if kind='date' then satisfied:=nullif(tr->>'date','')::date is not null and current_date>=nullif(tr->>'date','')::date;reason:=case when satisfied then 'contractual_date_reached' else 'contractual_date_not_reached' end;
 elsif kind='obligation' then satisfied:=exists(select 1 from public.contract_obligations o where o.contract_id=c.id and (o.trigger_ref=ref or o.clause_ref=ref or o.id::text=ref) and (o.status='met' or (o.status='waived' and o.waiver_reason is not null and o.waived_by is not null)));reason:=case when satisfied then 'contract_obligation_satisfied' else 'contract_obligation_not_satisfied' end;
 elsif kind='evidence' then select * into a from finance.invoice_milestone_authorities x where x.invoice_id=i.id and x.authority_type='evidence_satisfied' order by x.created_at desc limit 1;satisfied:=found;authority_id:=case when found then a.id else null end;reason:=case when satisfied then 'contractual_evidence_recorded' else 'contractual_evidence_missing' end;
 else reason:='milestone_trigger_kind_missing_or_unsupported';end if;
 return jsonb_build_object('passed',satisfied,'reason',reason,'authority_id',coalesce(authority_id,a.id),'milestone',m,'trigger',tr,'contract_id',c.id,'contract_execution_hash',c.execution_hash);
end;$$;
revoke all on function finance.evaluate_invoice_milestone_gate(uuid) from public,anon;grant execute on function finance.evaluate_invoice_milestone_gate(uuid) to authenticated;

create or replace function public.create_invoice_draft(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','finance','core','project','audit','auth','pg_temp' as $$
declare org_id uuid:=nullif(input_payload->>'organisation_id','')::uuid;project_id_value uuid:=nullif(input_payload->>'project_id','')::uuid;contract_id_value uuid:=nullif(input_payload->>'contract_id','')::uuid;tax_det_id uuid:=nullif(input_payload->>'tax_determination_id','')::uuid;invoice_id uuid;line jsonb;q numeric;r numeric;gst numeric;taxable numeric;tax_amount numeric;line_total numeric;subtotal_value numeric:=0;tax_value numeric:=0;inv public.invoices%rowtype;
begin
 if org_id is null then raise exception 'organisation_required';end if;if not core.has_org_role(org_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required';end if;if project_id_value is not null and not project.can_access_project(project_id_value) then raise exception 'project_access_required';end if;if nullif(btrim(input_payload->>'invoice_number'),'') is null then raise exception 'invoice_number_required';end if;if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb))=0 then raise exception 'invoice_line_required';end if;
 if contract_id_value is not null and nullif(btrim(input_payload->>'milestone_code'),'') is null then raise exception 'contract_invoice_milestone_code_required';end if;
 if tax_det_id is not null and not exists(select 1 from finance.tax_determinations t where t.id=tax_det_id and t.organisation_id=org_id and t.status='determined') then raise exception 'verified_tax_determination_required';end if;
 insert into public.invoices(organisation_id,project_id,contract_id,invoice_number,status,currency,issue_date,due_date,metadata,created_by,milestone_code,tax_determination_id)
 values(org_id,project_id_value,contract_id_value,btrim(input_payload->>'invoice_number'),'draft',coalesce(nullif(upper(btrim(input_payload->>'currency')),''),'INR'),coalesce(nullif(input_payload->>'issue_date','')::date,current_date),coalesce(nullif(input_payload->>'due_date','')::date,current_date+7),coalesce(input_payload->'metadata','{}'::jsonb),auth.uid(),nullif(btrim(input_payload->>'milestone_code'),''),tax_det_id) returning id into invoice_id;
 for line in select value from jsonb_array_elements(input_payload->'lines') loop if nullif(btrim(line->>'description'),'') is null then raise exception 'invoice_line_description_required';end if;q:=coalesce(nullif(line->>'quantity','')::numeric,1);r:=coalesce(nullif(line->>'rate','')::numeric,0);gst:=coalesce(nullif(line->>'gst_rate','')::numeric,0);if q<0 or r<0 or gst<0 then raise exception 'invoice_negative_value_not_allowed';end if;taxable:=round(q*r,2);tax_amount:=round(taxable*gst/100,2);line_total:=taxable+tax_amount;subtotal_value:=subtotal_value+taxable;tax_value:=tax_value+tax_amount;insert into public.invoice_lines(invoice_id,description,quantity,rate,taxable_amount,gst_rate,tax_amount,total,sort_order) values(invoice_id,btrim(line->>'description'),q,r,taxable,gst,tax_amount,line_total,coalesce(nullif(line->>'sort_order','')::integer,0));end loop;
 update public.invoices set subtotal=subtotal_value,tax=tax_value,total=subtotal_value+tax_value,updated_at=now() where id=invoice_id returning * into inv;perform audit.append_event(org_id,project_id_value,'finance.invoice.draft_created','invoice',invoice_id,null,to_jsonb(inv),null,gen_random_uuid());return invoice_id;
end;$$;

create or replace function public.issue_invoice(target_invoice_id uuid)
returns void language plpgsql security invoker set search_path='public','finance','core','audit','extensions','auth','pg_temp' as $$
declare i public.invoices%rowtype;before_state jsonb;gate jsonb;gate_hash text;authority_id uuid;
begin
 select * into i from public.invoices where id=target_invoice_id for update;if not found then raise exception 'invoice_not_found';end if;
 if not core.has_org_role(i.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required';end if;if i.created_by=auth.uid() then raise exception 'maker_cannot_issue_own_invoice';end if;if i.status<>'draft' then raise exception 'invoice_not_draft';end if;if i.total<=0 then raise exception 'invoice_total_must_be_positive';end if;
 gate:=finance.evaluate_invoice_milestone_gate(i.id);if coalesce((gate->>'passed')::boolean,false)=false then raise exception 'CONTRACTUAL_MILESTONE_NOT_SATISFIED:%',gate->>'reason';end if;
 if i.tax_determination_id is not null and not exists(select 1 from finance.tax_determinations t where t.id=i.tax_determination_id and t.organisation_id=i.organisation_id and t.status='determined') then raise exception 'TAX_RULE_UNRESOLVED';end if;
 authority_id:=nullif(gate->>'authority_id','')::uuid;gate_hash:=encode(extensions.digest(gate::text,'sha256'),'hex');before_state:=to_jsonb(i);
 update public.invoices set status='issued',issued_by=auth.uid(),issued_at=now(),milestone_authority_id=authority_id,milestone_gate_snapshot=gate,milestone_gate_hash=gate_hash,updated_at=now() where id=i.id returning * into i;
 perform audit.append_event(i.organisation_id,i.project_id,'finance.invoice.issued','invoice',i.id,before_state,to_jsonb(i),gate_hash,gen_random_uuid());
end;$$;

-- Ledger-derived project P&L. No stored/dashboard figures are used.
create or replace function public.get_project_pnl(target_project_id uuid,target_from date default null,target_to date default null)
returns jsonb language plpgsql stable security invoker set search_path='finance','project','core','auth','extensions','pg_temp' as $$
declare p project.projects%rowtype;income_total numeric;expense_total numeric;detail jsonb;from_date date:=coalesce(target_from,'0001-01-01'::date);to_date date:=coalesce(target_to,'9999-12-31'::date);recon_hash text;
begin
 select * into p from project.projects where id=target_project_id;if not found or not project.can_access_project(p.id) then raise exception 'project_access_required';end if;
 if from_date>to_date then raise exception 'pnl_date_range_invalid';end if;
 select coalesce(sum(case when a.account_type='income' then l.credit-l.debit else 0 end),0),coalesce(sum(case when a.account_type='expense' then l.debit-l.credit else 0 end),0),
        coalesce(jsonb_agg(jsonb_build_object('journal_id',j.id,'journal_number',j.journal_number::text,'posting_date',j.posting_date,'posted_hash',j.posted_hash,'line_id',l.id,'account_id',a.id,'account_code',a.code::text,'account_name',a.name,'account_type',a.account_type,'debit',l.debit,'credit',l.credit,'currency',l.currency,'cost_code',l.cost_code) order by j.posting_date,j.journal_number::text,l.id) filter(where a.account_type in ('income','expense')),'[]'::jsonb)
 into income_total,expense_total,detail
 from finance.journal_lines l join finance.journals j on j.id=l.journal_id join finance.ledger_accounts a on a.id=l.account_id
 where l.project_id=p.id and j.organisation_id=p.organisation_id and j.status='posted' and j.posting_date between from_date and to_date;
 recon_hash:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'from',target_from,'to',target_to,'income',income_total,'expense',expense_total,'net_profit',income_total-expense_total,'ledger_lines',detail)::text,'sha256'),'hex');
 return jsonb_build_object('project_id',p.id,'project_code',p.code::text,'from',target_from,'to',target_to,'income',income_total,'expense',expense_total,'net_profit',income_total-expense_total,'ledger_lines',detail,'reconciliation_hash',recon_hash,'source','posted_general_ledger');
end;$$;
revoke all on function public.get_project_pnl(uuid,date,date) from public,anon;grant execute on function public.get_project_pnl(uuid,date,date) to authenticated;

commit;
