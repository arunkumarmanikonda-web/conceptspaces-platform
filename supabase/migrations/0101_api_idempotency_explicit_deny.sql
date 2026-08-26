begin;

drop policy if exists api_idempotency_authenticated_deny on integration.api_idempotency_keys;
create policy api_idempotency_authenticated_deny on integration.api_idempotency_keys
for all to authenticated using(false) with check(false);

commit;
