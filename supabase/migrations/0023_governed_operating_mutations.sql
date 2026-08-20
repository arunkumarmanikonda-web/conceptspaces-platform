-- Superseded before production application by the validated split migrations:
-- 0023a_governed_operating_foundation.sql
-- 0023b_governed_commercial_mutations.sql
-- 0023c_governed_workflow_coordination.sql
--
-- The original monolithic migration failed PostgreSQL parsing and the enclosing
-- transaction rolled back completely. This stub intentionally performs no DDL.
select 1;
