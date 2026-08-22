begin;

alter table finance.journals add column if not exists memo text;
alter table finance.journals add column if not exists posted_hash text;
alter table finance.journals add column if not exists reversal_reason text;
alter table finance.journals add column if not exists updated_at timestamptz not null default now();

create table if not exists finance.fiscal_periods(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 period_code text not null,
 start_date date not null,
 end_date date not null,
 status text not null default 'open' check(status in ('open','closed')),
 closed_by uuid references auth.users(id),
 closed_at timestamptz,
 created_by uuid references auth.users(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(organisation_id,period_code),
 check(end_date>=start_date)
);
alter table finance.journals add column if not exists fiscal_period_id uuid references finance.fiscal_periods(id) on delete restrict;

alter table finance.fiscal_periods enable row level security;
alter table finance.ledger_accounts enable row level security;
alter table finance.journals enable row level security;
alter table finance.journal_lines enable row level security;

grant select,insert,update on finance.fiscal_periods to authenticated;
grant select,insert,update on finance.ledger_accounts to authenticated;
grant select,insert,update on finance.journals to authenticated;
grant select,insert,update,delete on finance.journal_lines to authenticated;

drop policy if exists fiscal_periods_read on finance.fiscal_periods;
create policy fiscal_periods_read on finance.fiscal_periods for select to authenticated using(core.is_internal_org_member(organisation_id));
drop policy if exists fiscal_periods_write on finance.fiscal_periods;
create policy fiscal_periods_write on finance.fiscal_periods for all to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin','finance'])) with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']));

drop policy if exists ledger_accounts_write on finance.ledger_accounts;
create policy ledger_accounts_write on finance.ledger_accounts for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true)='account');
drop policy if exists ledger_accounts_update on finance.ledger_accounts;
create policy ledger_accounts_update on finance.ledger_accounts for update to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin','finance'])) with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true)='account');

drop policy if exists journals_write on finance.journals;
create policy journals_write on finance.journals for insert to authenticated with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true) in ('journal_create','journal_reversal'));
drop policy if exists journals_update on finance.journals;
create policy journals_update on finance.journals for update to authenticated using(core.has_org_role(organisation_id,array['super_admin','org_admin','finance'])) with check(core.has_org_role(organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true) in ('journal_post','journal_reversal','journal_create'));

drop policy if exists journal_lines_write on finance.journal_lines;
create policy journal_lines_write on finance.journal_lines for insert to authenticated with check(exists(select 1 from finance.journals j where j.id=journal_lines.journal_id and core.has_org_role(j.organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true) in ('journal_create','journal_reversal')));
drop policy if exists journal_lines_update on finance.journal_lines;
create policy journal_lines_update on finance.journal_lines for update to authenticated using(exists(select 1 from finance.journals j where j.id=journal_lines.journal_id and j.status='draft' and core.has_org_role(j.organisation_id,array['super_admin','org_admin','finance']))) with check(exists(select 1 from finance.journals j where j.id=journal_lines.journal_id and j.status='draft' and core.has_org_role(j.organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true)='journal_create'));
drop policy if exists journal_lines_delete on finance.journal_lines;
create policy journal_lines_delete on finance.journal_lines for delete to authenticated using(exists(select 1 from finance.journals j where j.id=journal_lines.journal_id and j.status='draft' and core.has_org_role(j.organisation_id,array['super_admin','org_admin','finance']) and current_setting('conceptspaces.finance_phase',true)='journal_create'));

create or replace function finance.guard_posted_journal_mutation()
returns trigger language plpgsql security definer set search_path='finance','pg_temp' as $$
begin
 if tg_op='DELETE' and old.status in ('posted','reversed') then raise exception 'posted_journal_immutable'; end if;
 if tg_op='UPDATE' and old.status in ('posted','reversed') then
   if not (old.status='posted' and new.status='reversed' and current_setting('conceptspaces.finance_phase',true)='journal_post') then
     raise exception 'posted_journal_immutable';
   end if;
   if (to_jsonb(new)-array['status','reversal_reason','updated_at']) <> (to_jsonb(old)-array['status','reversal_reason','updated_at']) then raise exception 'posted_journal_content_immutable'; end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end;$$;
revoke all on function finance.guard_posted_journal_mutation() from public,anon,authenticated;
drop trigger if exists trg_guard_posted_journal on finance.journals;
create trigger trg_guard_posted_journal before update or delete on finance.journals for each row execute function finance.guard_posted_journal_mutation();

create or replace function finance.guard_posted_journal_line_mutation()
returns trigger language plpgsql security definer set search_path='finance','pg_temp' as $$
declare status_value text;
begin
 select status into status_value from finance.journals where id=coalesce(new.journal_id,old.journal_id);
 if status_value in ('posted','reversed') then raise exception 'posted_journal_lines_immutable'; end if;
 return case when tg_op='DELETE' then old else new end;
end;$$;
revoke all on function finance.guard_posted_journal_line_mutation() from public,anon,authenticated;
drop trigger if exists trg_guard_posted_journal_line on finance.journal_lines;
create trigger trg_guard_posted_journal_line before update or delete on finance.journal_lines for each row execute function finance.guard_posted_journal_line_mutation();

create or replace function public.create_finance_account(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','finance','core','audit','auth','pg_temp' as $$
declare account finance.ledger_accounts%rowtype; type_value text:=lower(btrim(input_payload->>'account_type'));
begin
 if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if nullif(btrim(input_payload->>'code'),'') is null or nullif(btrim(input_payload->>'name'),'') is null then raise exception 'account_identity_required'; end if;
 if type_value not in ('asset','liability','equity','income','expense') then raise exception 'account_type_invalid'; end if;
 if nullif(input_payload->>'parent_id','') is not null and not exists(select 1 from finance.ledger_accounts a where a.id=(input_payload->>'parent_id')::uuid and a.organisation_id=target_organisation_id) then raise exception 'parent_account_invalid'; end if;
 perform set_config('conceptspaces.finance_phase','account',true);
 insert into finance.ledger_accounts(organisation_id,code,name,account_type,parent_id,currency,active,metadata)
 values(target_organisation_id,upper(btrim(input_payload->>'code')),btrim(input_payload->>'name'),type_value,nullif(input_payload->>'parent_id','')::uuid,nullif(upper(btrim(input_payload->>'currency')),''),coalesce((input_payload->>'active')::boolean,true),coalesce(input_payload->'metadata','{}'::jsonb)) returning * into account;
 perform audit.append_event(target_organisation_id,null,'finance.account.created','ledger_account',account.id,null,to_jsonb(account),null,gen_random_uuid());
 return account.id;
end;$$;
revoke all on function public.create_finance_account(uuid,jsonb) from public,anon;
grant execute on function public.create_finance_account(uuid,jsonb) to authenticated;

create or replace function public.create_fiscal_period(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','finance','core','audit','auth','pg_temp' as $$
declare period finance.fiscal_periods%rowtype; start_value date:=nullif(input_payload->>'start_date','')::date; end_value date:=nullif(input_payload->>'end_date','')::date;
begin
 if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if nullif(btrim(input_payload->>'period_code'),'') is null or start_value is null or end_value is null or end_value<start_value then raise exception 'fiscal_period_invalid'; end if;
 if exists(select 1 from finance.fiscal_periods p where p.organisation_id=target_organisation_id and daterange(p.start_date,p.end_date,'[]') && daterange(start_value,end_value,'[]')) then raise exception 'fiscal_period_overlap'; end if;
 insert into finance.fiscal_periods(organisation_id,period_code,start_date,end_date,status,created_by) values(target_organisation_id,upper(btrim(input_payload->>'period_code')),start_value,end_value,'open',auth.uid()) returning * into period;
 perform audit.append_event(target_organisation_id,null,'finance.period.created','fiscal_period',period.id,null,to_jsonb(period),null,gen_random_uuid()); return period.id;
end;$$;
revoke all on function public.create_fiscal_period(uuid,jsonb) from public,anon;
grant execute on function public.create_fiscal_period(uuid,jsonb) to authenticated;

create or replace function public.set_fiscal_period_status(target_period_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker set search_path='public','finance','core','audit','auth','pg_temp' as $$
declare period finance.fiscal_periods%rowtype; before_state jsonb; value text:=lower(btrim(target_status));
begin
 select * into period from finance.fiscal_periods where id=target_period_id for update;
 if not found or auth.uid() is null or not core.has_org_role(period.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if value not in ('open','closed') or nullif(btrim(target_reason),'') is null then raise exception 'fiscal_period_transition_invalid'; end if;
 before_state:=to_jsonb(period);
 update finance.fiscal_periods set status=value,closed_by=case when value='closed' then auth.uid() else null end,closed_at=case when value='closed' then now() else null end,updated_at=now() where id=period.id returning * into period;
 perform audit.append_event(period.organisation_id,null,'finance.period.'||value,'fiscal_period',period.id,before_state,to_jsonb(period),target_reason,gen_random_uuid()); return period.status;
end;$$;
revoke all on function public.set_fiscal_period_status(uuid,text,text) from public,anon;
grant execute on function public.set_fiscal_period_status(uuid,text,text) to authenticated;

create or replace function public.create_finance_journal(target_organisation_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='public','finance','project','core','audit','auth','pg_temp' as $$
declare journal finance.journals%rowtype; line jsonb; debit_total numeric:=0; credit_total numeric:=0; debit_value numeric; credit_value numeric; account finance.ledger_accounts%rowtype; project_id_value uuid; posting_value date:=coalesce(nullif(input_payload->>'posting_date','')::date,current_date); number_value text;
begin
 if auth.uid() is null or not core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if nullif(btrim(input_payload->>'source_type'),'') is null then raise exception 'journal_source_required'; end if;
 if jsonb_typeof(coalesce(input_payload->'lines','[]'::jsonb))<>'array' or jsonb_array_length(coalesce(input_payload->'lines','[]'::jsonb))<2 then raise exception 'journal_requires_two_lines'; end if;
 number_value:='JV-'||to_char(posting_value,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 perform set_config('conceptspaces.finance_phase','journal_create',true);
 insert into finance.journals(organisation_id,journal_number,posting_date,status,source_type,source_id,created_by,memo)
 values(target_organisation_id,number_value,posting_value,'draft',lower(btrim(input_payload->>'source_type')),nullif(input_payload->>'source_id','')::uuid,auth.uid(),nullif(btrim(input_payload->>'memo'),'')) returning * into journal;
 for line in select value from jsonb_array_elements(input_payload->'lines') loop
   select * into account from finance.ledger_accounts where id=nullif(line->>'account_id','')::uuid and organisation_id=target_organisation_id and active;
   if not found then raise exception 'journal_account_invalid'; end if;
   debit_value:=coalesce(nullif(line->>'debit','')::numeric,0); credit_value:=coalesce(nullif(line->>'credit','')::numeric,0);
   if debit_value<0 or credit_value<0 or (debit_value>0 and credit_value>0) or (debit_value=0 and credit_value=0) then raise exception 'journal_line_value_invalid'; end if;
   project_id_value:=nullif(line->>'project_id','')::uuid;
   if project_id_value is not null and not exists(select 1 from project.projects p where p.id=project_id_value and p.organisation_id=target_organisation_id and project.can_access_project(p.id)) then raise exception 'journal_project_invalid'; end if;
   insert into finance.journal_lines(journal_id,account_id,project_id,cost_code,counterparty_id,debit,credit,currency,tax_determination_id,memo)
   values(journal.id,account.id,project_id_value,nullif(btrim(line->>'cost_code'),''),nullif(line->>'counterparty_id','')::uuid,debit_value,credit_value,coalesce(nullif(upper(btrim(line->>'currency')),''),coalesce(account.currency,'INR')),nullif(line->>'tax_determination_id','')::uuid,nullif(btrim(line->>'memo'),''));
   debit_total:=debit_total+debit_value; credit_total:=credit_total+credit_value;
 end loop;
 if debit_total<=0 or debit_total<>credit_total then raise exception 'journal_not_balanced'; end if;
 perform audit.append_event(target_organisation_id,null,'finance.journal.created','journal',journal.id,null,jsonb_build_object('journal',to_jsonb(journal),'debit',debit_total,'credit',credit_total),null,gen_random_uuid()); return journal.id;
end;$$;
revoke all on function public.create_finance_journal(uuid,jsonb) from public,anon;
grant execute on function public.create_finance_journal(uuid,jsonb) to authenticated;

create or replace function public.post_finance_journal(target_journal_id uuid,target_reason text)
returns text language plpgsql security invoker set search_path='public','finance','core','audit','extensions','auth','pg_temp' as $$
declare journal finance.journals%rowtype; period finance.fiscal_periods%rowtype; debit_total numeric; credit_total numeric; hash_value text; before_state jsonb;
begin
 select * into journal from finance.journals where id=target_journal_id for update;
 if not found or auth.uid() is null or not core.has_org_role(journal.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if journal.status<>'draft' then raise exception 'journal_not_draft'; end if;
 if journal.created_by=auth.uid() then raise exception 'maker_cannot_post_own_journal'; end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'journal_post_reason_required'; end if;
 select * into period from finance.fiscal_periods where organisation_id=journal.organisation_id and journal.posting_date between start_date and end_date and status='open' order by start_date desc limit 1;
 if not found then raise exception 'open_fiscal_period_required'; end if;
 select coalesce(sum(debit),0),coalesce(sum(credit),0) into debit_total,credit_total from finance.journal_lines where journal_id=journal.id;
 if debit_total<=0 or debit_total<>credit_total then raise exception 'journal_not_balanced'; end if;
 hash_value:=encode(extensions.digest((jsonb_build_object('journal_id',journal.id,'number',journal.journal_number,'posting_date',journal.posting_date,'source_type',journal.source_type,'source_id',journal.source_id,'memo',journal.memo,'lines',(select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]'::jsonb) from finance.journal_lines l where l.journal_id=journal.id)))::text,'sha256'),'hex');
 before_state:=to_jsonb(journal); perform set_config('conceptspaces.finance_phase','journal_post',true);
 update finance.journals set status='posted',posted_by=auth.uid(),posted_at=now(),posted_hash=hash_value,fiscal_period_id=period.id,updated_at=now() where id=journal.id returning * into journal;
 if journal.reversal_of_id is not null then update finance.journals set status='reversed',reversal_reason=target_reason,updated_at=now() where id=journal.reversal_of_id; end if;
 perform audit.append_event(journal.organisation_id,null,'finance.journal.posted','journal',journal.id,before_state,to_jsonb(journal),target_reason,gen_random_uuid()); return journal.status;
end;$$;
revoke all on function public.post_finance_journal(uuid,text) from public,anon;
grant execute on function public.post_finance_journal(uuid,text) to authenticated;

create or replace function public.create_finance_reversal(target_journal_id uuid,target_posting_date date,target_reason text)
returns uuid language plpgsql security invoker set search_path='public','finance','core','audit','auth','pg_temp' as $$
declare original finance.journals%rowtype; reversal finance.journals%rowtype; line finance.journal_lines%rowtype; number_value text; posting_value date:=coalesce(target_posting_date,current_date);
begin
 select * into original from finance.journals where id=target_journal_id for update;
 if not found or auth.uid() is null or not core.has_org_role(original.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'finance_authority_required'; end if;
 if original.status<>'posted' then raise exception 'only_posted_journal_reversible'; end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'reversal_reason_required'; end if;
 if exists(select 1 from finance.journals j where j.reversal_of_id=original.id and j.status in ('draft','posted')) then raise exception 'journal_reversal_already_exists'; end if;
 number_value:='RV-'||to_char(posting_value,'YYYYMMDD')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
 perform set_config('conceptspaces.finance_phase','journal_reversal',true);
 insert into finance.journals(organisation_id,journal_number,posting_date,status,source_type,source_id,reversal_of_id,created_by,memo,reversal_reason)
 values(original.organisation_id,number_value,posting_value,'draft','reversal',original.id,original.id,auth.uid(),'Reversal of '||original.journal_number,target_reason) returning * into reversal;
 for line in select * from finance.journal_lines where journal_id=original.id order by id loop
   insert into finance.journal_lines(journal_id,account_id,project_id,cost_code,counterparty_id,debit,credit,currency,tax_determination_id,memo)
   values(reversal.id,line.account_id,line.project_id,line.cost_code,line.counterparty_id,line.credit,line.debit,line.currency,line.tax_determination_id,'Reversal: '||coalesce(line.memo,''));
 end loop;
 perform audit.append_event(original.organisation_id,null,'finance.journal.reversal_created','journal',reversal.id,null,to_jsonb(reversal),target_reason,gen_random_uuid()); return reversal.id;
end;$$;
revoke all on function public.create_finance_reversal(uuid,date,text) from public,anon;
grant execute on function public.create_finance_reversal(uuid,date,text) to authenticated;

create or replace function public.list_finance_workspace(target_organisation_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='public','finance','project','core','auth','pg_temp' as $$
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required'; end if;
 return jsonb_build_object(
  'accounts',coalesce((select jsonb_agg(to_jsonb(a) order by a.code) from finance.ledger_accounts a where a.organisation_id=target_organisation_id),'[]'::jsonb),
  'periods',coalesce((select jsonb_agg(to_jsonb(p) order by p.start_date desc) from finance.fiscal_periods p where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'journals',coalesce((select jsonb_agg(to_jsonb(j) order by j.posting_date desc,j.created_at desc) from finance.journals j where j.organisation_id=target_organisation_id),'[]'::jsonb),
  'journal_lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.journal_id,l.id) from finance.journal_lines l join finance.journals j on j.id=l.journal_id where j.organisation_id=target_organisation_id),'[]'::jsonb),
  'invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.issue_date desc,i.created_at desc) from public.invoices i where i.organisation_id=target_organisation_id),'[]'::jsonb),
  'invoice_lines',coalesce((select jsonb_agg(to_jsonb(l) order by l.invoice_id,l.sort_order,l.id) from public.invoice_lines l join public.invoices i on i.id=l.invoice_id where i.organisation_id=target_organisation_id),'[]'::jsonb),
  'payments',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from public.payment_transactions p where p.organisation_id=target_organisation_id),'[]'::jsonb),
  'tax_determinations',coalesce((select jsonb_agg(to_jsonb(t) order by t.determined_at desc) from finance.tax_determinations t where t.organisation_id=target_organisation_id),'[]'::jsonb),
  'projects',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'code',p.code,'name',p.name) order by p.code) from project.projects p where p.organisation_id=target_organisation_id and project.can_access_project(p.id)),'[]'::jsonb),
  'contracts',coalesce((select jsonb_agg(jsonb_build_object('id',c.id,'project_id',c.project_id,'status',c.status,'contract_type',c.contract_type,'execution_hash',c.execution_hash) order by c.created_at desc) from public.contracts c where c.organisation_id=target_organisation_id and c.status in ('active','suspended')),'[]'::jsonb),
  'summary',jsonb_build_object(
    'receivables',coalesce((select sum(greatest(i.total-i.amount_paid,0)) from public.invoices i where i.organisation_id=target_organisation_id and i.status in ('issued','part_paid','overdue')),0),
    'tds_receivable',coalesce((select sum(i.tds_receivable) from public.invoices i where i.organisation_id=target_organisation_id and i.status not in ('cancelled','credited')),0),
    'cash_received',coalesce((select sum(p.amount) from public.payment_transactions p where p.organisation_id=target_organisation_id and p.status='captured' and p.applied_at is not null),0),
    'posted_debits',coalesce((select sum(l.debit) from finance.journal_lines l join finance.journals j on j.id=l.journal_id where j.organisation_id=target_organisation_id and j.status in ('posted','reversed')),0),
    'posted_credits',coalesce((select sum(l.credit) from finance.journal_lines l join finance.journals j on j.id=l.journal_id where j.organisation_id=target_organisation_id and j.status in ('posted','reversed')),0)
  )
 );
end;$$;
revoke all on function public.list_finance_workspace(uuid) from public,anon;
grant execute on function public.list_finance_workspace(uuid) to authenticated;

commit;