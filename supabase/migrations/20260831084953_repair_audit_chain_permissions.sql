begin;

-- The audit chain verifier is SECURITY INVOKER and therefore intentionally
-- honours the existing audit.events RLS policy.  The policy existed, but the
-- authenticated role did not have the table-level SELECT privilege required
-- for PostgreSQL to evaluate it.
grant usage on schema audit to authenticated;
grant select on table audit.events to authenticated;

commit;
