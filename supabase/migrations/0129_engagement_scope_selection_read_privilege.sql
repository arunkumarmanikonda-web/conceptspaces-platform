begin;

-- submit_project_intake uses INSERT ... ON CONFLICT DO NOTHING for governed
-- scope modules. PostgreSQL requires SELECT alongside INSERT for this guarded
-- conflict path; row visibility remains constrained by scope_selections RLS.
grant select on engagement.scope_selections to authenticated;

commit;
