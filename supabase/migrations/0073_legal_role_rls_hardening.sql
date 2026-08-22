begin;

create policy contracts_legal_insert on public.contracts for insert to authenticated with check(
 core.has_org_role(organisation_id,array['legal']) and current_setting('conceptspaces.legal_phase',true)='contract_generate'
);
create policy contracts_legal_update on public.contracts for update to authenticated using(
 core.has_org_role(organisation_id,array['legal'])
) with check(
 core.has_org_role(organisation_id,array['legal']) and current_setting('conceptspaces.legal_phase',true) in ('contract_generate','contract_state')
);
create policy contract_obligations_legal_insert on public.contract_obligations for insert to authenticated with check(
 current_setting('conceptspaces.legal_phase',true)='contract_generate' and exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['legal']))
);
create policy contract_obligations_legal_update on public.contract_obligations for update to authenticated using(
 exists(select 1 from public.contracts c where c.id=contract_id and core.has_org_role(c.organisation_id,array['legal']))
) with check(current_setting('conceptspaces.legal_phase',true)='obligation_transition');

create or replace function public.transition_contract_obligation(target_obligation_id uuid,target_status text,input_payload jsonb default '{}'::jsonb)
returns text
language plpgsql security invoker
set search_path=public,core,audit,auth,pg_temp
as $$
declare o public.contract_obligations%rowtype; c public.contracts%rowtype; status_value text:=lower(btrim(target_status)); before_state jsonb;
begin
 select * into o from public.contract_obligations where id=target_obligation_id for update;
 if not found then raise exception 'obligation_not_found'; end if;
 select * into c from public.contracts where id=o.contract_id;
 if auth.uid() is null or not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance','legal','project_manager']) then raise exception 'obligation_authority_required'; end if;
 if status_value not in ('open','completed','waived') then raise exception 'obligation_status_invalid'; end if;
 if status_value='completed' and nullif(btrim(input_payload->>'evidence_reference'),'') is null then raise exception 'obligation_completion_evidence_required'; end if;
 if status_value='waived' and nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'obligation_waiver_reason_required'; end if;
 before_state:=to_jsonb(o);
 perform set_config('conceptspaces.legal_phase','obligation_transition',true);
 update public.contract_obligations set status=status_value,completed_at=case when status_value='completed' then now() else completed_at end,waiver_reason=case when status_value='waived' then btrim(input_payload->>'reason') else waiver_reason end,waived_by=case when status_value='waived' then auth.uid() else waived_by end,waived_at=case when status_value='waived' then now() else waived_at end where id=o.id returning * into o;
 perform audit.append_event(c.organisation_id,c.project_id,'commercial.obligation.'||status_value,'contract_obligation',o.id,before_state,to_jsonb(o),coalesce(input_payload->>'evidence_reference',input_payload->>'reason'),gen_random_uuid());
 return o.status;
end;$$;
revoke all on function public.transition_contract_obligation(uuid,text,jsonb) from public,anon;
grant execute on function public.transition_contract_obligation(uuid,text,jsonb) to authenticated;

commit;
