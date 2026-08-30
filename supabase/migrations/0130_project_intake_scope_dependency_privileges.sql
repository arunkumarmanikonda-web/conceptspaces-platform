begin;

-- Project intake inserts governed scope rows. The deferred dependency trigger
-- evaluates the canonical catalogue and any approved dependency overrides at
-- transaction commit, so the invoker needs read access to every relation in
-- that validation path. RLS continues to govern tenant-owned rows.
grant select on engagement.scope_catalogue,
                engagement.scope_selections,
                engagement.scope_dependency_overrides
to authenticated;

commit;
