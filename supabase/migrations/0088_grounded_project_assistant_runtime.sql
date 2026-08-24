begin;

create table if not exists engagement.project_conversations(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  audience text not null check(audience in ('internal','client')),
  title text not null,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists engagement.project_messages(
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references engagement.project_conversations(id) on delete cascade,
  project_id uuid not null references project.projects(id) on delete cascade,
  role text not null check(role in ('user','assistant')),
  content text not null,
  citations jsonb not null default '[]'::jsonb,
  confidence text not null default 'D' check(confidence in ('A','B','C','D')),
  response_status text not null default 'grounded' check(response_status in ('grounded','not_verified','conflict')),
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  flagged_at timestamptz,
  flagged_by uuid references auth.users(id) on delete set null,
  flag_reason text
);

create index if not exists project_conversations_user_project_idx on engagement.project_conversations(created_by,project_id,created_at desc);
create index if not exists project_messages_conversation_idx on engagement.project_messages(conversation_id,created_at);

alter table engagement.project_conversations enable row level security;
alter table engagement.project_messages enable row level security;
grant select,insert on engagement.project_conversations to authenticated;
grant select,insert,update on engagement.project_messages to authenticated;

drop policy if exists project_conversations_self_read on engagement.project_conversations;
create policy project_conversations_self_read on engagement.project_conversations for select to authenticated
using (created_by=auth.uid() and (project.can_access_project(project_id) or engagement.client_can_access_project(project_id)));

drop policy if exists project_conversations_governed_insert on engagement.project_conversations;
create policy project_conversations_governed_insert on engagement.project_conversations for insert to authenticated
with check (created_by=auth.uid() and current_setting('conceptspaces.ask_phase',true)='write' and (project.can_access_project(project_id) or engagement.client_can_access_project(project_id)));

drop policy if exists project_messages_self_read on engagement.project_messages;
create policy project_messages_self_read on engagement.project_messages for select to authenticated
using (exists(select 1 from engagement.project_conversations c where c.id=conversation_id and c.created_by=auth.uid() and c.project_id=project_messages.project_id));

drop policy if exists project_messages_governed_insert on engagement.project_messages;
create policy project_messages_governed_insert on engagement.project_messages for insert to authenticated
with check (created_by=auth.uid() and current_setting('conceptspaces.ask_phase',true)='write' and exists(select 1 from engagement.project_conversations c where c.id=conversation_id and c.created_by=auth.uid() and c.project_id=project_messages.project_id));

drop policy if exists project_messages_governed_flag on engagement.project_messages;
create policy project_messages_governed_flag on engagement.project_messages for update to authenticated
using (role='assistant' and current_setting('conceptspaces.ask_phase',true)='flag' and exists(select 1 from engagement.project_conversations c where c.id=conversation_id and c.created_by=auth.uid()))
with check (role='assistant' and flagged_by=auth.uid() and flagged_at is not null);

create or replace function engagement.authorized_project_organisation_id(target_project_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path='engagement','project','auth','pg_temp'
as $$
declare org_id uuid;
begin
  if auth.uid() is null or not (project.can_access_project(target_project_id) or engagement.client_can_access_project(target_project_id)) then raise exception 'PROJECT_ASSISTANT_PERMISSION_DENIED'; end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  return org_id;
end;
$$;
revoke all on function engagement.authorized_project_organisation_id(uuid) from public,anon;
grant execute on function engagement.authorized_project_organisation_id(uuid) to authenticated;

create or replace function engagement.build_project_evidence_pack(target_project_id uuid,target_question text,target_client_mode boolean,target_allow_documents boolean,target_allow_commercial boolean)
returns jsonb
language plpgsql
stable
security definer
set search_path='project','coordination','cde','governance','operations','integration','engineering','public','engagement','auth','pg_temp'
as $$
declare q text:=lower(coalesce(target_question,'')); evidence jsonb:='[]'::jsonb;
begin
  evidence:=evidence||coalesce((select jsonb_agg(x) from (
    select jsonb_build_object('domain','project','resource_type','project','resource_id',p.id,'label',p.code::text||' · '||p.name,'status',p.status,'confidence','B','summary','Current stage: '||p.stage||'; typology: '||p.typology) x
    from project.projects p where p.id=target_project_id
  ) s),'[]'::jsonb);

  if q ~ '(stage|progress|milestone|where are we|current)' or q !~ '(approval|decision|document|drawing|invoice|payment|contract|risk|issue|block|change|changed|release|model|architecture|structure)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','stage','resource_type','project_stage','resource_id',s.id,'label',s.stage_code||' · '||s.title,'status',s.state,'confidence','B','summary','Planned '||coalesce(s.planned_start::text,'—')||' to '||coalesce(s.planned_finish::text,'—')||'; actual '||coalesce(s.actual_start::text,'—')||' to '||coalesce(s.actual_finish::text,'—')) x
      from project.project_stages s where s.project_id=target_project_id order by s.sequence limit 12
    ) s),'[]'::jsonb);
  end if;

  if q ~ '(approval|decision|pending|block|blocking|next)' or q !~ '(document|drawing|invoice|payment|contract|change|changed|release|model|architecture|structure)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','approval','resource_type',a.resource_type,'resource_id',a.resource_id,'label','Approval '||a.id::text,'status',a.decision,'confidence','A','hash',a.requested_resource_hash,'summary','Criticality '||a.criticality||'; required role '||coalesce(a.role_required,'unspecified')||'; requested '||a.requested_at::text) x
      from coordination.approval_requests a where a.project_id=target_project_id and a.decision='pending' and (not target_client_mode or a.requested_from=auth.uid() or coalesce(a.role_required,'') like 'client%') order by a.requested_at desc limit 10
    ) s),'[]'::jsonb);
  end if;

  if target_allow_documents and q ~ '(document|drawing|revision|issued|release|model|architecture|structure)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','document','resource_type','document','resource_id',d.id,'label',d.document_number::text||' · '||d.title,'status',d.status,'confidence','A','hash',fv.checksum,'summary','Discipline '||d.discipline||'; revision '||d.revision||'; CDE state '||d.cde_state) x
      from cde.documents d join cde.file_versions fv on fv.id=d.current_version_id
      where d.project_id=target_project_id and d.status in ('approved','issued') and (not target_client_mode or d.cde_state='published')
      order by d.updated_at desc limit 10
    ) s),'[]'::jsonb);
  end if;

  if target_allow_commercial and q ~ '(invoice|payment|contract|commercial|amount|outstanding|due)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','invoice','resource_type','invoice','resource_id',i.id,'label',i.invoice_number,'status',i.status,'confidence','A','summary','Total '||i.currency||' '||i.total::text||'; paid '||i.amount_paid::text||'; outstanding '||greatest(i.total-i.amount_paid,0)::text||'; due '||i.due_date::text,'amount',greatest(i.total-i.amount_paid,0),'currency',i.currency) x
      from public.invoices i where i.project_id=target_project_id and i.status in ('issued','part_paid','paid','overdue') order by i.issue_date desc limit 10
    ) s),'[]'::jsonb);
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','contract','resource_type','contract','resource_id',c.id,'label','Contract v'||c.version::text,'status',c.status,'confidence','A','hash',coalesce(c.execution_hash,c.draft_hash),'summary','Type '||coalesce(c.contract_type,'—')||'; effective '||coalesce(c.effective_at::date::text,'—')||'; expires '||coalesce(c.expires_at::date::text,'—')) x
      from public.contracts c join project.projects p on p.contract_id=c.id where p.id=target_project_id and c.status not in ('draft','superseded') limit 1
    ) s),'[]'::jsonb);
  end if;

  if q ~ '(risk|issue|block|blocking|critical|warning)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','risk','resource_type','risk','resource_id',r.id,'label',r.code::text||' · '||r.title,'status',r.status,'confidence','B','summary','Category '||r.category||'; inherent '||r.inherent_level||'; residual '||coalesce(r.residual_level,'—')||'; '||r.description) x
      from operations.risks r where r.project_id=target_project_id and r.status<>'closed' and (not target_client_mode or r.client_visible=true) order by case r.inherent_level when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,r.updated_at desc limit 10
    ) s),'[]'::jsonb);
  end if;

  if q ~ '(change|changed|this week|recent|updated|impact)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','change','resource_type','project_change_request','resource_id',cr.id,'label',cr.change_ref||' · '||cr.title,'status',cr.status,'confidence','B','hash',cr.applied_commit_hash,'summary',cr.description||'; updated '||cr.updated_at::text) x
      from public.project_change_requests cr where cr.project_id=target_project_id and cr.updated_at>=now()-interval '7 days' and (not target_client_mode or cr.status in ('approved','applied')) order by cr.updated_at desc limit 10
    ) s),'[]'::jsonb);
  end if;

  if q ~ '(release|issued|package)' then
    evidence:=evidence||coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('domain','release','resource_type','release','resource_id',r.id,'label',r.package_type||' · '||r.package_reference,'status',r.state,'confidence','A','hash',r.content_hash,'summary','Issued '||coalesce(r.issued_at::text,'—')) x
      from governance.release_safety_cases r where r.project_id=target_project_id and r.state='issued' order by r.issued_at desc nulls last limit 10
    ) s),'[]'::jsonb);
  end if;

  return evidence;
end;
$$;
revoke all on function engagement.build_project_evidence_pack(uuid,text,boolean,boolean,boolean) from public,anon;
grant execute on function engagement.build_project_evidence_pack(uuid,text,boolean,boolean,boolean) to authenticated;

create or replace function public.ask_project_grounded(target_project_id uuid,target_question text,target_conversation_id uuid default null)
returns jsonb
language plpgsql
security invoker
set search_path='public','engagement','project','audit','auth','pg_temp'
as $$
declare internal_mode boolean; access_row engagement.client_portal_access%rowtype; client_mode boolean; allow_documents boolean:=true; allow_commercial boolean:=true; conversation engagement.project_conversations%rowtype; user_message engagement.project_messages%rowtype; assistant_message engagement.project_messages%rowtype; evidence jsonb; q text:=lower(btrim(target_question)); answer text; status_value text:='grounded'; confidence_value text:='B'; matched_count int; approval_count int; risk_count int; document_count int; invoice_count int; change_count int; stage_count int; release_count int; outstanding numeric; org_id uuid;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if nullif(q,'') is null or length(q)>2000 then raise exception 'project_question_invalid'; end if;
  internal_mode:=project.can_access_project(target_project_id);client_mode:=not internal_mode;
  if client_mode then
    select * into access_row from engagement.client_portal_access where project_id=target_project_id and user_id=auth.uid() and status='active' order by activated_at desc limit 1;
    if not found or not coalesce((access_row.permissions->>'ask_project')::boolean,false) then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
    allow_documents:=coalesce((access_row.permissions->>'view_documents')::boolean,false);
    allow_commercial:=coalesce((access_row.permissions->>'view_commercial')::boolean,false);
    if q ~ '(document|drawing|revision|issued)' and not allow_documents then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
    if q ~ '(invoice|payment|contract|commercial|amount|outstanding|due)' and not allow_commercial then raise exception 'CLIENT_PERMISSION_DENIED'; end if;
  end if;
  org_id:=engagement.authorized_project_organisation_id(target_project_id);
  perform set_config('conceptspaces.ask_phase','write',true);
  if target_conversation_id is null then
    insert into engagement.project_conversations(project_id,audience,title,created_by) values(target_project_id,case when client_mode then 'client' else 'internal' end,left(btrim(target_question),120),auth.uid()) returning * into conversation;
  else
    select * into conversation from engagement.project_conversations where id=target_conversation_id and project_id=target_project_id and created_by=auth.uid();
    if not found then raise exception 'conversation_not_found'; end if;
  end if;
  insert into engagement.project_messages(conversation_id,project_id,role,content,citations,confidence,response_status,created_by) values(conversation.id,target_project_id,'user',btrim(target_question),'[]'::jsonb,'B','grounded',auth.uid()) returning * into user_message;
  evidence:=engagement.build_project_evidence_pack(target_project_id,target_question,client_mode,allow_documents,allow_commercial);
  select count(*) into matched_count from jsonb_array_elements(evidence);
  select count(*) into approval_count from jsonb_array_elements(evidence) e where e->>'domain'='approval';
  select count(*) into risk_count from jsonb_array_elements(evidence) e where e->>'domain'='risk';
  select count(*) into document_count from jsonb_array_elements(evidence) e where e->>'domain'='document';
  select count(*),coalesce(sum((e->>'amount')::numeric),0) into invoice_count,outstanding from jsonb_array_elements(evidence) e where e->>'domain'='invoice';
  select count(*) into change_count from jsonb_array_elements(evidence) e where e->>'domain'='change';
  select count(*) into stage_count from jsonb_array_elements(evidence) e where e->>'domain'='stage';
  select count(*) into release_count from jsonb_array_elements(evidence) e where e->>'domain'='release';

  if q ~ '(approval|decision|pending|block|blocking|next)' then
    if approval_count=0 and risk_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no authorised pending approval or visible blocking-risk record currently supports an answer to this question.';
    else answer:='Grounded project state: '||approval_count::text||' pending governed approval(s) and '||risk_count::text||' visible open risk(s) match this question. Each approval citation is bound to its submitted resource hash.';end if;
  elsif q ~ '(invoice|payment|contract|commercial|amount|outstanding|due)' then
    if invoice_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no authorised issued invoice record currently supports the requested commercial answer.';
    else confidence_value:='A';answer:='Grounded commercial state: '||invoice_count::text||' visible invoice(s) with aggregate outstanding amount '||outstanding::text||' in the cited invoice currencies. Use the cited invoice records for exact currency and due-date context.';end if;
  elsif q ~ '(document|drawing|revision|issued)' then
    if document_count=0 and release_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no authorised published approved/issued document or issued release matches this question.';
    else confidence_value:='A';answer:='Grounded document state: '||document_count::text||' approved/issued document(s) and '||release_count::text||' issued release package(s) match this question. Exact revisions and hashes are cited below.';end if;
  elsif q ~ '(change|changed|this week|recent|updated|impact)' then
    if change_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no authorised governed project change updated in the last seven days matches this question.';
    else answer:='Grounded change state: '||change_count::text||' governed project change(s) were updated in the last seven days and are cited below.';end if;
  elsif q ~ '(risk|issue|critical|warning)' then
    if risk_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no authorised open risk record matches this question.';
    else answer:='Grounded risk state: '||risk_count::text||' authorised open risk(s) match this question. Only explicitly client-visible risks are included for client users.';end if;
  elsif q ~ '(stage|progress|milestone|where are we|current)' then
    if stage_count=0 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: no governed project-stage record is currently available.';
    else answer:='Grounded programme state: '||stage_count::text||' governed project-stage record(s) are available. Current and planned/actual stage evidence is cited below.';end if;
  else
    if matched_count<=1 then status_value:='not_verified';confidence_value:='D';answer:='Not Verified: the authorised Project Graph does not contain enough matching evidence to answer this question without inference.';
    else answer:='Grounded project summary: '||approval_count::text||' pending approval(s), '||risk_count::text||' visible open risk(s), '||document_count::text||' matching approved/issued document(s), '||change_count::text||' recent governed change(s), and '||release_count::text||' issued release package(s) are represented in the cited Project Graph records.';end if;
  end if;

  insert into engagement.project_messages(conversation_id,project_id,role,content,citations,confidence,response_status,created_by) values(conversation.id,target_project_id,'assistant',answer,evidence,confidence_value,status_value,auth.uid()) returning * into assistant_message;
  update engagement.project_conversations set updated_at=now() where id=conversation.id;
  perform audit.append_event(org_id,target_project_id,case when status_value='not_verified' then 'assistant.answer_not_verified' else 'assistant.answer_grounded' end,'project_message',assistant_message.id,null,jsonb_build_object('conversation_id',conversation.id,'confidence',confidence_value,'response_status',status_value,'citation_count',matched_count),null,gen_random_uuid());
  return jsonb_build_object('conversation_id',conversation.id,'message_id',assistant_message.id,'answer',answer,'citations',evidence,'confidence',confidence_value,'response_status',status_value);
end;
$$;
revoke all on function public.ask_project_grounded(uuid,text,uuid) from public,anon;
grant execute on function public.ask_project_grounded(uuid,text,uuid) to authenticated;

create or replace function public.list_project_conversation(target_conversation_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path='engagement','auth','pg_temp'
as $$
declare c engagement.project_conversations%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  select * into c from engagement.project_conversations where id=target_conversation_id and created_by=auth.uid();if not found then raise exception 'conversation_not_found'; end if;
  return jsonb_build_object('conversation',to_jsonb(c),'messages',coalesce((select jsonb_agg(to_jsonb(m) order by m.created_at) from engagement.project_messages m where m.conversation_id=c.id),'[]'::jsonb));
end;
$$;
revoke all on function public.list_project_conversation(uuid) from public,anon;
grant execute on function public.list_project_conversation(uuid) to authenticated;

create or replace function public.flag_project_answer(target_message_id uuid,target_reason text)
returns text
language plpgsql
security invoker
set search_path='engagement','audit','auth','pg_temp'
as $$
declare m engagement.project_messages%rowtype; c engagement.project_conversations%rowtype; org_id uuid; before_state jsonb;
begin
  if auth.uid() is null or nullif(btrim(target_reason),'') is null then raise exception 'answer_flag_reason_required'; end if;
  select * into m from engagement.project_messages where id=target_message_id and role='assistant' for update;if not found then raise exception 'assistant_answer_not_found'; end if;
  select * into c from engagement.project_conversations where id=m.conversation_id and created_by=auth.uid();if not found then raise exception 'conversation_not_found'; end if;
  org_id:=engagement.authorized_project_organisation_id(m.project_id);before_state:=to_jsonb(m);
  perform set_config('conceptspaces.ask_phase','flag',true);
  update engagement.project_messages set flagged_at=now(),flagged_by=auth.uid(),flag_reason=btrim(target_reason) where id=m.id returning * into m;
  perform audit.append_event(org_id,m.project_id,'assistant.answer_flagged','project_message',m.id,before_state,to_jsonb(m),target_reason,gen_random_uuid());
  return 'flagged';
end;
$$;
revoke all on function public.flag_project_answer(uuid,text) from public,anon;
grant execute on function public.flag_project_answer(uuid,text) to authenticated;

commit;