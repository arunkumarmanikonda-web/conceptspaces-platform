begin;

create or replace function finance.guard_published_tax_rule()
returns trigger
language plpgsql
security definer
set search_path='finance','pg_temp'
as $$
declare phase text:=current_setting('conceptspaces.tax_phase',true);
begin
  if old.publication_status<>'published' then return new; end if;
  if phase<>'retire' then raise exception 'PUBLISHED_TAX_RULE_IMMUTABLE'; end if;
  if new.publication_status<>'retired'
     or new.rule_set is distinct from old.rule_set
     or new.code is distinct from old.code
     or new.jurisdiction is distinct from old.jurisdiction
     or new.effective_from is distinct from old.effective_from
     or new.priority is distinct from old.priority
     or new.conditions is distinct from old.conditions
     or new.outcome is distinct from old.outcome
     or new.source_reference is distinct from old.source_reference
     or new.rule_hash is distinct from old.rule_hash
     or new.created_by is distinct from old.created_by
     or new.supersedes_id is distinct from old.supersedes_id
  then raise exception 'PUBLISHED_TAX_RULE_CONTENT_IMMUTABLE'; end if;
  if new.effective_until is not null and new.effective_until<new.effective_from then raise exception 'tax_rule_retirement_date_invalid'; end if;
  return new;
end;
$$;
revoke all on function finance.guard_published_tax_rule() from public,anon,authenticated;

commit;
