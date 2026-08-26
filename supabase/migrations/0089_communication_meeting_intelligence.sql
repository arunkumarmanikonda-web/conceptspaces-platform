begin;

create table if not exists engagement.project_communications(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  thread_key text,
  channel text not null check(channel in ('email','whatsapp','sms','in_app')),
  recipient text not null,
  subject text,
  body text not null,
  body_hash text not null,
  policy_class text not null check(policy_class in ('routine','sensitive','legal','critical')),
  approval_state text not null check(approval_state in ('not_required','pending','approved','rejected')),
  status text not null default 'draft' check(status in ('draft','approved','queued','sent','failed','archived')),
  consent_basis text,
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  queued_intent_id uuid references public.communication_intents(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists project_communications_project_idx on engagement.project_communications(project_id,created_at desc);

create table if not exists engagement.project_meetings(
  id uuid primary key default gen_random_uuid(),
  organisation_id uuid not null references core.organisations(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  title text not null,
  scheduled_at timestamptz,
  participants jsonb not null default '[]'::jsonb,
  agenda jsonb not null default '[]'::jsonb,
  recording_ref text,
  status text not null default 'draft' check(status in ('draft','held','minutes_draft','published','cancelled')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.meeting_transcripts(
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references engagement.project_meetings(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  source_ref text not null,
  transcript_text text not null,
  transcript_hash text not null,
  confidence numeric not null check(confidence between 0 and 1),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists engagement.meeting_minutes_drafts(
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references engagement.project_meetings(id) on delete cascade,
  transcript_id uuid references engagement.meeting_transcripts(id) on delete restrict,
  project_id uuid not null references project.projects(id) on delete cascade,
  extraction_mode text not null check(extraction_mode in ('ai','human')),
  decision_drafts jsonb not null default '[]'::jsonb,
  action_drafts jsonb not null default '[]'::jsonb,
  source_hash text not null,
  draft_hash text not null,
  status text not null default 'draft' check(status in ('draft','reviewed','published','superseded')),
  created_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  published_by uuid references auth.users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.meeting_decisions(
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references engagement.project_meetings(id) on delete cascade,
  minute_draft_id uuid not null references engagement.meeting_minutes_drafts(id) on delete restrict,
  project_id uuid not null references project.projects(id) on delete cascade,
  decision_text text not null,
  decision_type text not null default 'project_decision',
  impact_summary text,
  source_hash text not null,
  decision_hash text not null,
  confirmed_by uuid not null references auth.users(id),
  created_at timestamptz not null default now()
);

create table if not exists engagement.meeting_action_links(
  id uuid primary key default gen_random_uuid(),
  meeting_id uuid not null references engagement.project_meetings(id) on delete cascade,
  minute_draft_id uuid not null references engagement.meeting_minutes_drafts(id) on delete restrict,
  project_id uuid not null references project.projects(id) on delete cascade,
  task_id uuid not null references operations.tasks(id) on delete restrict,
  source_hash text not null,
  created_at timestamptz not null default now(),
  unique(minute_draft_id,task_id)
);

alter table engagement.project_communications enable row level security;
alter table engagement.project_meetings enable row level security;
alter table engagement.meeting_transcripts enable row level security;
alter table engagement.meeting_minutes_drafts enable row level security;
alter table engagement.meeting_decisions enable row level security;
alter table engagement.meeting_action_links enable row level security;

grant select,insert,update on engagement.project_communications,engagement.project_meetings,engagement.meeting_minutes_drafts to authenticated;
grant select,insert on engagement.meeting_transcripts to authenticated;
grant select,insert on engagement.meeting_decisions,engagement.meeting_action_links to authenticated;

do $$
declare t text;
begin
 foreach t in array array['project_communications','project_meetings','meeting_transcripts','meeting_minutes_drafts','meeting_decisions','meeting_action_links'] loop
  execute format('drop policy if exists %I on engagement.%I','comms_read_'||t,t);
  execute format('create policy %I on engagement.%I for select to authenticated using (project.can_access_project(project_id))','comms_read_'||t,t);
 end loop;
end $$;

drop policy if exists comms_write_project_communications on engagement.project_communications;
create policy comms_write_project_communications on engagement.project_communications for insert to authenticated
with check(project.can_access_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.comms_phase',true)='draft');
drop policy if exists comms_update_project_communications on engagement.project_communications;
create policy comms_update_project_communications on engagement.project_communications for update to authenticated
using(project.can_access_project(project_id))
with check(project.can_access_project(project_id) and current_setting('conceptspaces.comms_phase',true) in ('approve','queue','archive'));

drop policy if exists comms_write_project_meetings on engagement.project_meetings;
create policy comms_write_project_meetings on engagement.project_meetings for insert to authenticated
with check(project.can_access_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.meeting_phase',true)='create');
drop policy if exists comms_update_project_meetings on engagement.project_meetings;
create policy comms_update_project_meetings on engagement.project_meetings for update to authenticated
using(project.can_access_project(project_id))
with check(project.can_access_project(project_id) and current_setting('conceptspaces.meeting_phase',true) in ('transcript','draft_minutes','publish','cancel'));

drop policy if exists comms_write_meeting_transcripts on engagement.meeting_transcripts;
create policy comms_write_meeting_transcripts on engagement.meeting_transcripts for insert to authenticated
with check(project.can_access_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.meeting_phase',true)='transcript');

drop policy if exists comms_write_minutes_drafts on engagement.meeting_minutes_drafts;
create policy comms_write_minutes_drafts on engagement.meeting_minutes_drafts for insert to authenticated
with check(project.can_access_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.meeting_phase',true)='draft_minutes');
drop policy if exists comms_update_minutes_drafts on engagement.meeting_minutes_drafts;
create policy comms_update_minutes_drafts on engagement.meeting_minutes_drafts for update to authenticated
using(project.can_access_project(project_id))
with check(project.can_access_project(project_id) and current_setting('conceptspaces.meeting_phase',true) in ('review_minutes','publish'));

drop policy if exists comms_write_decisions on engagement.meeting_decisions;
create policy comms_write_decisions on engagement.meeting_decisions for insert to authenticated
with check(project.can_manage_project(project_id) and confirmed_by=auth.uid() and current_setting('conceptspaces.meeting_phase',true)='publish');
drop policy if exists comms_write_action_links on engagement.meeting_action_links;
create policy comms_write_action_links on engagement.meeting_action_links for insert to authenticated
with check(project.can_manage_project(project_id) and current_setting('conceptspaces.meeting_phase',true)='publish');

drop policy if exists communication_intents_governed_queue on public.communication_intents;
create policy communication_intents_governed_queue on public.communication_intents for insert to authenticated
with check(
 current_setting('conceptspaces.comms_phase',true)='queue'
 and project_id is not null
 and project.can_access_project(project_id)
 and exists(select 1 from project.projects p where p.id=project_id and p.organisation_id=organisation_id)
);

create or replace function public.create_project_communication(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='public','engagement','project','audit','extensions','auth','pg_temp' as $$
declare p project.projects%rowtype; r engagement.project_communications%rowtype; cls text:=lower(coalesce(nullif(btrim(input_payload->>'policy_class'),''),'routine')); ch text:=lower(btrim(input_payload->>'channel')); body_value text:=btrim(input_payload->>'body'); approval text; h text;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 if ch not in ('email','whatsapp','sms','in_app') then raise exception 'communication_channel_invalid'; end if;
 if cls not in ('routine','sensitive','legal','critical') then raise exception 'communication_policy_class_invalid'; end if;
 if nullif(btrim(input_payload->>'recipient'),'') is null or nullif(body_value,'') is null then raise exception 'communication_recipient_and_body_required'; end if;
 select * into p from project.projects where id=target_project_id;if not found then raise exception 'project_not_found'; end if;
 approval:=case when cls='routine' then 'not_required' else 'pending' end;
 h:=encode(extensions.digest(jsonb_build_object('project_id',p.id,'channel',ch,'recipient',btrim(input_payload->>'recipient'),'subject',coalesce(input_payload->>'subject',''),'body',body_value,'policy_class',cls)::text,'sha256'),'hex');
 perform set_config('conceptspaces.comms_phase','draft',true);
 insert into engagement.project_communications(organisation_id,project_id,thread_key,channel,recipient,subject,body,body_hash,policy_class,approval_state,status,consent_basis,created_by)
 values(p.organisation_id,p.id,nullif(btrim(input_payload->>'thread_key'),''),ch,btrim(input_payload->>'recipient'),nullif(btrim(input_payload->>'subject'),''),body_value,h,cls,approval,'draft',nullif(btrim(input_payload->>'consent_basis'),''),auth.uid()) returning * into r;
 perform audit.append_event(p.organisation_id,p.id,'communication.drafted','project_communication',r.id,null,to_jsonb(r),h,gen_random_uuid());
 return r.id;
end;$$;
revoke all on function public.create_project_communication(uuid,jsonb) from public,anon;grant execute on function public.create_project_communication(uuid,jsonb) to authenticated;

create or replace function public.approve_project_communication(target_communication_id uuid,target_decision text,target_reason text)
returns text language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare r engagement.project_communications%rowtype; p project.projects%rowtype; d text:=lower(btrim(target_decision)); before_state jsonb;
begin
 select * into r from engagement.project_communications where id=target_communication_id for update;if not found then raise exception 'communication_not_found'; end if;
 if auth.uid() is null or not project.can_manage_project(r.project_id) then raise exception 'communication_approval_authority_required'; end if;
 if r.approval_state<>'pending' then raise exception 'communication_not_pending_approval'; end if;
 if d not in ('approved','rejected') then raise exception 'communication_decision_invalid'; end if;
 if r.created_by=auth.uid() then raise exception 'maker_cannot_approve_own_sensitive_communication'; end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'communication_decision_reason_required'; end if;
 select * into p from project.projects where id=r.project_id;before_state:=to_jsonb(r);
 perform set_config('conceptspaces.comms_phase','approve',true);
 update engagement.project_communications set approval_state=d,status=case when d='approved' then 'approved' else 'archived' end,approved_by=auth.uid(),approved_at=now(),updated_at=now() where id=r.id returning * into r;
 perform audit.append_event(p.organisation_id,p.id,'communication.'||d,'project_communication',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());
 return r.approval_state;
end;$$;
revoke all on function public.approve_project_communication(uuid,text,text) from public,anon;grant execute on function public.approve_project_communication(uuid,text,text) to authenticated;

create or replace function public.queue_project_communication(target_communication_id uuid)
returns uuid language plpgsql security invoker
set search_path='public','engagement','project','audit','auth','pg_temp' as $$
declare r engagement.project_communications%rowtype; p project.projects%rowtype; c public.contacts%rowtype; consent_ok boolean:=false; intent public.communication_intents%rowtype;
begin
 select * into r from engagement.project_communications where id=target_communication_id for update;if not found then raise exception 'communication_not_found'; end if;
 if auth.uid() is null or not project.can_access_project(r.project_id) then raise exception 'project_access_required'; end if;
 if r.status not in ('draft','approved') then raise exception 'communication_not_queueable'; end if;
 if r.policy_class<>'routine' and r.approval_state<>'approved' then raise exception 'COMMUNICATION_APPROVAL_REQUIRED'; end if;
 if r.approval_state='rejected' then raise exception 'communication_rejected'; end if;
 select * into p from project.projects where id=r.project_id;
 if r.channel='in_app' then consent_ok:=true;
 elsif r.channel='email' then select * into c from public.contacts where organisation_id=p.organisation_id and lower(email)=lower(r.recipient) limit 1; consent_ok:=not found or c.consent_email;
 elsif r.channel='whatsapp' then select * into c from public.contacts where organisation_id=p.organisation_id and phone=r.recipient limit 1; consent_ok:=not found or c.consent_whatsapp;
 elsif r.channel='sms' then select * into c from public.contacts where organisation_id=p.organisation_id and phone=r.recipient limit 1; consent_ok:=not found or c.consent_sms;
 end if;
 if not consent_ok and nullif(btrim(r.consent_basis),'') is null then raise exception 'RECIPIENT_POLICY_BLOCK'; end if;
 perform set_config('conceptspaces.comms_phase','queue',true);
 insert into public.communication_intents(organisation_id,channel,recipient,template_code,locale,project_id,payload,consent_basis,status)
 values(p.organisation_id,r.channel,r.recipient,'project_communication','en-IN',p.id,jsonb_build_object('communication_id',r.id,'subject',r.subject,'body',r.body,'body_hash',r.body_hash,'policy_class',r.policy_class),r.consent_basis,'queued') returning * into intent;
 update engagement.project_communications set status='queued',queued_intent_id=intent.id,updated_at=now() where id=r.id returning * into r;
 perform audit.append_event(p.organisation_id,p.id,'communication.queued','project_communication',r.id,null,to_jsonb(r),r.body_hash,gen_random_uuid());
 return intent.id;
end;$$;
revoke all on function public.queue_project_communication(uuid) from public,anon;grant execute on function public.queue_project_communication(uuid) to authenticated;

create or replace function public.create_project_meeting(target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare p project.projects%rowtype; m engagement.project_meetings%rowtype;
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 if nullif(btrim(input_payload->>'title'),'') is null then raise exception 'meeting_title_required'; end if;
 select * into p from project.projects where id=target_project_id;
 perform set_config('conceptspaces.meeting_phase','create',true);
 insert into engagement.project_meetings(organisation_id,project_id,title,scheduled_at,participants,agenda,recording_ref,created_by)
 values(p.organisation_id,p.id,btrim(input_payload->>'title'),nullif(input_payload->>'scheduled_at','')::timestamptz,coalesce(input_payload->'participants','[]'::jsonb),coalesce(input_payload->'agenda','[]'::jsonb),nullif(btrim(input_payload->>'recording_ref'),''),auth.uid()) returning * into m;
 perform audit.append_event(p.organisation_id,p.id,'meeting.created','project_meeting',m.id,null,to_jsonb(m),null,gen_random_uuid());return m.id;
end;$$;
revoke all on function public.create_project_meeting(uuid,jsonb) from public,anon;grant execute on function public.create_project_meeting(uuid,jsonb) to authenticated;

create or replace function public.record_meeting_transcript(target_meeting_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','extensions','auth','pg_temp' as $$
declare m engagement.project_meetings%rowtype; t engagement.meeting_transcripts%rowtype; txt text:=btrim(input_payload->>'transcript_text'); conf numeric:=coalesce(nullif(input_payload->>'confidence','')::numeric,0); h text; before_state jsonb;
begin
 select * into m from engagement.project_meetings where id=target_meeting_id for update;if not found then raise exception 'meeting_not_found'; end if;
 if auth.uid() is null or not project.can_access_project(m.project_id) then raise exception 'project_access_required'; end if;
 if nullif(input_payload->>'source_ref','') is null or nullif(txt,'') is null then raise exception 'transcript_source_and_text_required'; end if;
 if conf<0 or conf>1 then raise exception 'transcript_confidence_invalid'; end if;
 h:=encode(extensions.digest(jsonb_build_object('meeting_id',m.id,'source_ref',input_payload->>'source_ref','transcript',txt)::text,'sha256'),'hex');before_state:=to_jsonb(m);
 perform set_config('conceptspaces.meeting_phase','transcript',true);
 insert into engagement.meeting_transcripts(meeting_id,project_id,source_ref,transcript_text,transcript_hash,confidence,created_by)
 values(m.id,m.project_id,btrim(input_payload->>'source_ref'),txt,h,conf,auth.uid()) returning * into t;
 update engagement.project_meetings set status='held',recording_ref=coalesce(recording_ref,nullif(btrim(input_payload->>'recording_ref'),'')),updated_at=now() where id=m.id returning * into m;
 perform audit.append_event(m.organisation_id,m.project_id,'meeting.transcribed','project_meeting',m.id,before_state,to_jsonb(m),h,gen_random_uuid());return t.id;
end;$$;
revoke all on function public.record_meeting_transcript(uuid,jsonb) from public,anon;grant execute on function public.record_meeting_transcript(uuid,jsonb) to authenticated;

create or replace function public.create_meeting_minutes_draft(target_meeting_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='engagement','project','audit','extensions','auth','pg_temp' as $$
declare m engagement.project_meetings%rowtype; t engagement.meeting_transcripts%rowtype; d engagement.meeting_minutes_drafts%rowtype; mode text:=lower(coalesce(nullif(btrim(input_payload->>'extraction_mode'),''),'human')); source_hash_value text; h text; before_state jsonb;
begin
 select * into m from engagement.project_meetings where id=target_meeting_id for update;if not found then raise exception 'meeting_not_found'; end if;
 if auth.uid() is null or not project.can_access_project(m.project_id) then raise exception 'project_access_required'; end if;
 if mode not in ('ai','human') then raise exception 'minutes_extraction_mode_invalid'; end if;
 if nullif(input_payload->>'transcript_id','') is not null then
  select * into t from engagement.meeting_transcripts where id=(input_payload->>'transcript_id')::uuid and meeting_id=m.id;
  if not found then raise exception 'meeting_transcript_not_found'; end if;source_hash_value:=t.transcript_hash;
 else source_hash_value:=encode(extensions.digest((m.id::text||':'||coalesce(m.recording_ref,'')||':'||coalesce(input_payload->>'source_ref','manual'))::text,'sha256'),'hex'); end if;
 h:=encode(extensions.digest(jsonb_build_object('meeting_id',m.id,'source_hash',source_hash_value,'decisions',coalesce(input_payload->'decisions','[]'::jsonb),'actions',coalesce(input_payload->'actions','[]'::jsonb),'mode',mode)::text,'sha256'),'hex');before_state:=to_jsonb(m);
 perform set_config('conceptspaces.meeting_phase','draft_minutes',true);
 update engagement.meeting_minutes_drafts set status='superseded',updated_at=now() where meeting_id=m.id and status in ('draft','reviewed');
 insert into engagement.meeting_minutes_drafts(meeting_id,transcript_id,project_id,extraction_mode,decision_drafts,action_drafts,source_hash,draft_hash,status,created_by)
 values(m.id,t.id,m.project_id,mode,coalesce(input_payload->'decisions','[]'::jsonb),coalesce(input_payload->'actions','[]'::jsonb),source_hash_value,h,'draft',auth.uid()) returning * into d;
 update engagement.project_meetings set status='minutes_draft',updated_at=now() where id=m.id returning * into m;
 perform audit.append_event(m.organisation_id,m.project_id,'meeting.minutes_drafted','meeting_minutes_draft',d.id,null,to_jsonb(d),h,gen_random_uuid());return d.id;
end;$$;
revoke all on function public.create_meeting_minutes_draft(uuid,jsonb) from public,anon;grant execute on function public.create_meeting_minutes_draft(uuid,jsonb) to authenticated;

create or replace function public.review_meeting_minutes(target_minutes_id uuid,target_reason text)
returns text language plpgsql security invoker
set search_path='engagement','project','audit','auth','pg_temp' as $$
declare d engagement.meeting_minutes_drafts%rowtype; m engagement.project_meetings%rowtype; before_state jsonb;
begin
 select * into d from engagement.meeting_minutes_drafts where id=target_minutes_id for update;if not found then raise exception 'minutes_not_found'; end if;
 if auth.uid() is null or not project.can_manage_project(d.project_id) then raise exception 'minutes_review_authority_required'; end if;
 if d.status<>'draft' then raise exception 'minutes_not_draft'; end if;
 if d.created_by=auth.uid() and d.extraction_mode='ai' then null; end if;
 select * into m from engagement.project_meetings where id=d.meeting_id;before_state:=to_jsonb(d);
 perform set_config('conceptspaces.meeting_phase','review_minutes',true);
 update engagement.meeting_minutes_drafts set status='reviewed',reviewed_by=auth.uid(),reviewed_at=now(),updated_at=now() where id=d.id returning * into d;
 perform audit.append_event(m.organisation_id,m.project_id,'meeting.minutes_reviewed','meeting_minutes_draft',d.id,before_state,to_jsonb(d),target_reason,gen_random_uuid());return d.status;
end;$$;
revoke all on function public.review_meeting_minutes(uuid,text) from public,anon;grant execute on function public.review_meeting_minutes(uuid,text) to authenticated;

create or replace function public.publish_meeting_minutes(target_minutes_id uuid,target_reason text)
returns jsonb language plpgsql security invoker
set search_path='engagement','operations','project','audit','extensions','auth','pg_temp' as $$
declare d engagement.meeting_minutes_drafts%rowtype; m engagement.project_meetings%rowtype; j jsonb; decision_row engagement.meeting_decisions%rowtype; task_row operations.tasks%rowtype; decision_ids jsonb:='[]'::jsonb; task_ids jsonb:='[]'::jsonb; decision_text_value text; action_title text; before_state jsonb;
begin
 select * into d from engagement.meeting_minutes_drafts where id=target_minutes_id for update;if not found then raise exception 'minutes_not_found'; end if;
 if auth.uid() is null or not project.can_manage_project(d.project_id) then raise exception 'minutes_publish_authority_required'; end if;
 if d.status<>'reviewed' then raise exception 'minutes_human_review_required'; end if;
 if d.reviewed_by is null then raise exception 'minutes_human_review_required'; end if;
 select * into m from engagement.project_meetings where id=d.meeting_id for update;before_state:=to_jsonb(d);
 perform set_config('conceptspaces.meeting_phase','publish',true);
 for j in select value from jsonb_array_elements(d.decision_drafts) loop
  decision_text_value:=btrim(coalesce(j->>'text',j->>'decision',''));
  if decision_text_value<>'' then
   insert into engagement.meeting_decisions(meeting_id,minute_draft_id,project_id,decision_text,decision_type,impact_summary,source_hash,decision_hash,confirmed_by)
   values(m.id,d.id,d.project_id,decision_text_value,coalesce(nullif(btrim(j->>'type'),''),'project_decision'),nullif(btrim(j->>'impact'),''),d.source_hash,encode(extensions.digest(jsonb_build_object('minutes',d.id,'source_hash',d.source_hash,'decision',decision_text_value,'type',coalesce(j->>'type','project_decision'),'impact',coalesce(j->>'impact',''))::text,'sha256'),'hex'),auth.uid()) returning * into decision_row;
   decision_ids:=decision_ids||jsonb_build_array(decision_row.id);
  end if;
 end loop;
 for j in select value from jsonb_array_elements(d.action_drafts) loop
  action_title:=btrim(coalesce(j->>'title',''));
  if action_title<>'' then
   insert into operations.tasks(organisation_id,project_id,title,task_type,state,priority,assignee_user_id,assignee_role_code,due_at,maker_user_id,evidence_refs)
   values(m.organisation_id,m.project_id,action_title,'meeting_action','open',coalesce(nullif(lower(btrim(j->>'priority')),''),'normal'),nullif(j->>'assignee_user_id','')::uuid,nullif(lower(btrim(j->>'assignee_role_code')),''),nullif(j->>'due_at','')::timestamptz,auth.uid(),jsonb_build_array(jsonb_build_object('meeting_id',m.id,'minutes_id',d.id,'source_hash',d.source_hash))) returning * into task_row;
   insert into engagement.meeting_action_links(meeting_id,minute_draft_id,project_id,task_id,source_hash) values(m.id,d.id,m.project_id,task_row.id,d.source_hash);
   task_ids:=task_ids||jsonb_build_array(task_row.id);
  end if;
 end loop;
 update engagement.meeting_minutes_drafts set status='published',published_by=auth.uid(),published_at=now(),updated_at=now() where id=d.id returning * into d;
 update engagement.project_meetings set status='published',updated_at=now() where id=m.id returning * into m;
 perform audit.append_event(m.organisation_id,m.project_id,'meeting.minutes_published','meeting_minutes_draft',d.id,before_state,to_jsonb(d),target_reason,gen_random_uuid());
 return jsonb_build_object('minutes_id',d.id,'decision_ids',decision_ids,'action_task_ids',task_ids,'draft_hash',d.draft_hash,'source_hash',d.source_hash);
end;$$;
revoke all on function public.publish_meeting_minutes(uuid,text) from public,anon;grant execute on function public.publish_meeting_minutes(uuid,text) to authenticated;

create or replace function public.list_communication_meeting_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker
set search_path='engagement','operations','project','public','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
 return jsonb_build_object(
  'communications',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from engagement.project_communications c where c.project_id=target_project_id),'[]'::jsonb),
  'meetings',coalesce((select jsonb_agg(to_jsonb(m) order by coalesce(m.scheduled_at,m.created_at) desc) from engagement.project_meetings m where m.project_id=target_project_id),'[]'::jsonb),
  'transcripts',coalesce((select jsonb_agg(jsonb_build_object('id',t.id,'meeting_id',t.meeting_id,'source_ref',t.source_ref,'transcript_hash',t.transcript_hash,'confidence',t.confidence,'created_at',t.created_at) order by t.created_at desc) from engagement.meeting_transcripts t where t.project_id=target_project_id),'[]'::jsonb),
  'minutes',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from engagement.meeting_minutes_drafts d where d.project_id=target_project_id),'[]'::jsonb),
  'decisions',coalesce((select jsonb_agg(to_jsonb(d) order by d.created_at desc) from engagement.meeting_decisions d where d.project_id=target_project_id),'[]'::jsonb),
  'actions',coalesce((select jsonb_agg(jsonb_build_object('link_id',l.id,'meeting_id',l.meeting_id,'minutes_id',l.minute_draft_id,'task_id',t.id,'title',t.title,'state',t.state,'priority',t.priority,'assignee_user_id',t.assignee_user_id,'assignee_role_code',t.assignee_role_code,'due_at',t.due_at,'source_hash',l.source_hash) order by t.created_at desc) from engagement.meeting_action_links l join operations.tasks t on t.id=l.task_id where l.project_id=target_project_id),'[]'::jsonb)
 );
end;$$;
revoke all on function public.list_communication_meeting_workspace(uuid) from public,anon;grant execute on function public.list_communication_meeting_workspace(uuid) to authenticated;

commit;