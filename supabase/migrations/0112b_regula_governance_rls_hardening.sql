begin;

-- Authorised rule governors must be able to review draft packs/rules without broadening published public read.
drop policy if exists regula_packs_governance_read on regula.packs;
create policy regula_packs_governance_read on regula.packs for select to authenticated using(regula.can_govern_rules());

drop policy if exists regula_rules_governance_read on regula.rules;
create policy regula_rules_governance_read on regula.rules for select to authenticated using(regula.can_govern_rules());

grant insert,update on regula.project_rule_impacts to authenticated;
drop policy if exists regula_project_impacts_governance_read on regula.project_rule_impacts;
create policy regula_project_impacts_governance_read on regula.project_rule_impacts for select to authenticated using(regula.can_govern_rules());
drop policy if exists regula_project_impacts_publish_insert on regula.project_rule_impacts;
create policy regula_project_impacts_publish_insert on regula.project_rule_impacts for insert to authenticated
with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true)='publish' and status='proposed');
drop policy if exists regula_project_impacts_publish_update on regula.project_rule_impacts;
create policy regula_project_impacts_publish_update on regula.project_rule_impacts for update to authenticated
using(regula.can_govern_rules())
with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true)='publish' and status='proposed');

commit;
