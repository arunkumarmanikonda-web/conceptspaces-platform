begin;

-- Contract state transitions are explicit. An accepted proposal creates a draft;
-- active state requires evidence of signature/execution and authorised finance/admin action.
create or replace function public.transition_contract_state(target_contract_id uuid,new_status text,evidence_reference text default null)
returns void
language plpgsql
security invoker
set search_path=public,core,audit
as $$
declare
  c public.contracts%rowtype;
  before_state jsonb;
  next_status text:=lower(btrim(new_status));
begin
  select * into c from public.contracts where id=target_contract_id;
  if not found then raise exception 'contract_not_found'; end if;
  if not core.has_org_role(c.organisation_id,array['super_admin','org_admin','finance']) then raise exception 'contract_transition_authority_required'; end if;
  if next_status not in ('negotiation','signature_pending','active','suspended','completed','terminated') then raise exception 'unsupported_contract_status'; end if;
  if c.status='draft' and next_status not in ('negotiation','signature_pending') then raise exception 'draft_contract_must_enter_negotiation_or_signature'; end if;
  if c.status='negotiation' and next_status not in ('signature_pending','terminated') then raise exception 'invalid_contract_transition'; end if;
  if c.status='signature_pending' and next_status='active' and nullif(btrim(evidence_reference),'') is null then raise exception 'signature_evidence_required'; end if;
  if c.status='active' and next_status not in ('suspended','completed','terminated') then raise exception 'invalid_contract_transition'; end if;
  if c.status in ('completed','terminated') then raise exception 'terminal_contract_state'; end if;
  before_state:=to_jsonb(c);
  update public.contracts
    set status=next_status,
        effective_at=case when next_status='active' and effective_at is null then now() else effective_at end,
        contract_snapshot=case when nullif(btrim(evidence_reference),'') is not null then contract_snapshot||jsonb_build_object('state_evidence',evidence_reference,'state_evidence_at',now(),'state_evidence_by',auth.uid()) else contract_snapshot end,
        updated_at=now()
  where id=c.id returning * into c;
  perform audit.append_event(c.organisation_id,c.project_id,'commercial.contract.'||next_status,'contract',c.id,before_state,to_jsonb(c),evidence_reference,gen_random_uuid());
end;
$$;
revoke all on function public.transition_contract_state(uuid,text,text) from public,anon;
grant execute on function public.transition_contract_state(uuid,text,text) to authenticated;

-- Invoice drafts linked to a contract must reference an active contract in the same organisation.
create or replace function public.assert_invoice_contract_eligible(target_organisation_id uuid,target_contract_id uuid)
returns boolean
language sql
stable
security invoker
set search_path=public
as $$
  select target_contract_id is null or exists(
    select 1 from public.contracts c
    where c.id=target_contract_id and c.organisation_id=target_organisation_id and c.status='active'
  );
$$;
revoke all on function public.assert_invoice_contract_eligible(uuid,uuid) from public,anon;
grant execute on function public.assert_invoice_contract_eligible(uuid,uuid) to authenticated;

create or replace function public.transition_coordination_issue(target_issue_id uuid,new_status text,resolution_note text default null)
returns void
language plpgsql
security invoker
set search_path=coordination,project,audit,public
as $$
declare
  i coordination.issues%rowtype;
  before_state jsonb;
  org_id uuid;
  next_status text:=lower(btrim(new_status));
begin
  select * into i from coordination.issues where id=target_issue_id;
  if not found then raise exception 'issue_not_found'; end if;
  if not project.can_access_project(i.project_id) then raise exception 'project_access_required'; end if;
  if next_status not in ('open','in_progress','answered','resolved','closed') then raise exception 'unsupported_issue_status'; end if;
  if i.status='closed' then raise exception 'closed_issue_is_terminal'; end if;
  if next_status='closed' and nullif(btrim(resolution_note),'') is null then raise exception 'closure_note_required'; end if;
  select organisation_id into org_id from project.projects where id=i.project_id;
  before_state:=to_jsonb(i);
  update coordination.issues
     set status=next_status,
         closed_at=case when next_status='closed' then now() else null end,
         updated_at=now()
   where id=i.id returning * into i;
  if nullif(btrim(resolution_note),'') is not null then
    insert into coordination.issue_comments(issue_id,body,author_id,evidence_refs)
    values(i.id,btrim(resolution_note),auth.uid(),'[]'::jsonb);
  end if;
  perform audit.append_event(org_id,i.project_id,'coordination.issue.'||next_status,'issue',i.id,before_state,to_jsonb(i),resolution_note,gen_random_uuid());
end;
$$;
revoke all on function public.transition_coordination_issue(uuid,text,text) from public,anon;
grant execute on function public.transition_coordination_issue(uuid,text,text) to authenticated;

commit;
