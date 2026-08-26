begin;

drop policy if exists comms_update_minutes_drafts on engagement.meeting_minutes_drafts;
create policy comms_update_minutes_drafts on engagement.meeting_minutes_drafts for update to authenticated
using(project.can_access_project(project_id))
with check(
  project.can_access_project(project_id)
  and current_setting('conceptspaces.meeting_phase',true) in ('draft_minutes','review_minutes','publish')
);

commit;
