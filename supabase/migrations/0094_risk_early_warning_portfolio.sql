begin;

alter table operations.risks
 add column if not exists source_hash text,
 add column if not exists source_signal_id uuid,
 add column if not exists created_by uuid references auth.users(id) on delete set null,
 add column if not exists accepted_by uuid references auth.users(id) on delete set null,
 add column if not exists accepted_at timestamptz,
 add column if not exists acceptance_reason text;

create table if not exists operations.risk_signals(
 id uuid primary key default gen_random_uuid(),
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 project_id uuid references project.projects(id) on delete cascade,
 category text not null,
 title text not null,
 evidence_refs jsonb not null default '[]'::jsonb,
 evidence_hash text not null,
 predicted_consequence text not null,
 confidence text not null check(confidence in ('A','B','C','D')),
 recommended_action text,
 status text not null default 'open' check(status in ('open','acknowledged','converted','dismissed')),
 generated_by text not null check(generated_by in ('human','rule','model')),
 created_by uuid not null references auth.users(id),
 created_at timestamptz not null default now(),
 acknowledged_by uuid references auth.users(id),
 acknowledged_at timestamptz,
 dismissed_by uuid references auth.users(id),
 dismissed_at timestamptz,
 dismissal_reason text,
 converted_risk_id uuid references operations.risks(id) on delete set null
);

create table if not exists operations.risk_events(
 id uuid primary key default gen_random_uuid(),
 risk_id uuid references operations.risks(id) on delete cascade,
 signal_id uuid references operations.risk_signals(id) on delete cascade,
 organisation_id uuid not null references core.organisations(id) on delete cascade,
 project_id uuid references project.projects(id) on delete cascade,
 event_type text not null,
 reason text,
 actor_id uuid not null references auth.users(id),
 snapshot jsonb not null,
 created_at timestamptz not null default now(),
 check(risk_id is not null or signal_id is not null)
);

create index if not exists risk_signals_project_status_idx on operations.risk_signals(project_id,status,created_at desc);
create index if not exists risk_events_project_idx on operations.risk_events(project_id,created_at desc);

alter table operations.risk_signals enable row level security;
alter table operations.risk_events enable row level security;
grant select,insert,update on operations.risk_signals to authenticated;
grant select,insert on operations.risk_events to authenticated;
grant insert,update on operations.risks to authenticated;

drop policy if exists risk_signals_read on operations.risk_signals;
create policy risk_signals_read on operations.risk_signals for select to authenticated
using((project_id is not null and project.can_access_project(project_id)) or (project_id is null and core.is_internal_org_member(organisation_id)));
drop policy if exists risk_signals_insert on operations.risk_signals;
create policy risk_signals_insert on operations.risk_signals for insert to authenticated
with check(current_setting('conceptspaces.risk_phase',true)='signal_create' and created_by=auth.uid() and ((project_id is not null and project.can_access_project(project_id)) or (project_id is null and core.is_internal_org_member(organisation_id))));
drop policy if exists risk_signals_update on operations.risk_signals;
create policy risk_signals_update on operations.risk_signals for update to authenticated
using((project_id is not null and project.can_manage_project(project_id)) or (project_id is null and core.has_org_role(organisation_id,array['super_admin','org_admin'])))
with check(current_setting('conceptspaces.risk_phase',true) in ('signal_decide','signal_convert') and ((project_id is not null and project.can_manage_project(project_id)) or (project_id is null and core.has_org_role(organisation_id,array['super_admin','org_admin']))));

drop policy if exists risk_events_read on operations.risk_events;
create policy risk_events_read on operations.risk_events for select to authenticated
using((project_id is not null and project.can_access_project(project_id)) or (project_id is null and core.is_internal_org_member(organisation_id)));
drop policy if exists risk_events_insert on operations.risk_events;
create policy risk_events_insert on operations.risk_events for insert to authenticated
with check(actor_id=auth.uid() and current_setting('conceptspaces.risk_phase',true) in ('signal_create','signal_decide','signal_convert','risk_create','risk_transition'));

drop policy if exists risks_governed_insert on operations.risks;
create policy risks_governed_insert on operations.risks for insert to authenticated
with check(current_setting('conceptspaces.risk_phase',true)='risk_create' and created_by=auth.uid() and ((project_id is not null and project.can_access_project(project_id)) or (project_id is null and core.is_internal_org_member(organisation_id))));
drop policy if exists risks_governed_update on operations.risks;
create policy risks_governed_update on operations.risks for update to authenticated
using((project_id is not null and project.can_manage_project(project_id)) or (project_id is null and core.has_org_role(organisation_id,array['super_admin','org_admin'])))
with check(current_setting('conceptspaces.risk_phase',true)='risk_transition' and ((project_id is not null and project.can_manage_project(project_id)) or (project_id is null and core.has_org_role(organisation_id,array['super_admin','org_admin']))));

create or replace function operations.risk_level(target_probability int,target_impact int)
returns text language sql immutable security invoker set search_path='pg_temp' as $$
 select case when target_probability*target_impact>=16 then 'critical' when target_probability*target_impact>=10 then 'high' when target_probability*target_impact>=5 then 'medium' else 'low' end;
$$;
revoke all on function operations.risk_level(int,int) from public,anon;grant execute on function operations.risk_level(int,int) to authenticated;

create or replace function public.create_early_warning(target_organisation_id uuid,target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='operations','project','core','audit','extensions','auth','pg_temp' as $$
declare s operations.risk_signals%rowtype; h text; generator text:=lower(coalesce(nullif(btrim(input_payload->>'generated_by'),''),'human'));
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if target_project_id is not null then
  if not project.can_access_project(target_project_id) or not exists(select 1 from project.projects p where p.id=target_project_id and p.organisation_id=target_organisation_id) then raise exception 'project_access_required';end if;
 elsif not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 if generator not in ('human','rule','model') then raise exception 'warning_generator_invalid';end if;
 if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'category'),'') is null or nullif(btrim(input_payload->>'predicted_consequence'),'') is null then raise exception 'warning_core_fields_required';end if;
 if upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'D')) not in ('A','B','C','D') then raise exception 'warning_confidence_invalid';end if;
 if jsonb_array_length(coalesce(input_payload->'evidence_refs','[]'::jsonb))=0 then raise exception 'warning_evidence_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'project_id',target_project_id,'category',lower(btrim(input_payload->>'category')),'title',btrim(input_payload->>'title'),'evidence',input_payload->'evidence_refs','consequence',btrim(input_payload->>'predicted_consequence'),'confidence',upper(coalesce(input_payload->>'confidence','D')),'recommended_action',coalesce(input_payload->>'recommended_action',''))::text,'sha256'),'hex');
 perform set_config('conceptspaces.risk_phase','signal_create',true);
 insert into operations.risk_signals(organisation_id,project_id,category,title,evidence_refs,evidence_hash,predicted_consequence,confidence,recommended_action,generated_by,created_by)
 values(target_organisation_id,target_project_id,lower(btrim(input_payload->>'category')),btrim(input_payload->>'title'),input_payload->'evidence_refs',h,btrim(input_payload->>'predicted_consequence'),upper(coalesce(nullif(btrim(input_payload->>'confidence'),''),'D')),nullif(btrim(input_payload->>'recommended_action'),''),generator,auth.uid()) returning * into s;
 insert into operations.risk_events(signal_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(s.id,s.organisation_id,s.project_id,'warning.generated',null,auth.uid(),to_jsonb(s));
 perform audit.append_event(s.organisation_id,s.project_id,'warning.generated','risk_signal',s.id,null,to_jsonb(s),h,gen_random_uuid());return s.id;
end;$$;
revoke all on function public.create_early_warning(uuid,uuid,jsonb) from public,anon;grant execute on function public.create_early_warning(uuid,uuid,jsonb) to authenticated;

create or replace function public.create_project_risk(target_organisation_id uuid,target_project_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker
set search_path='operations','project','core','audit','extensions','auth','pg_temp' as $$
declare r operations.risks%rowtype; prob int:=nullif(input_payload->>'probability','')::int; imp int:=nullif(input_payload->>'impact','')::int; h text; code_value text:=coalesce(nullif(btrim(input_payload->>'code'),''),'RSK-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)));
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if target_project_id is not null then if not project.can_access_project(target_project_id) or not exists(select 1 from project.projects p where p.id=target_project_id and p.organisation_id=target_organisation_id) then raise exception 'project_access_required';end if; elsif not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 if prob not between 1 and 5 or imp not between 1 and 5 then raise exception 'risk_probability_impact_invalid';end if;
 if nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'category'),'') is null or nullif(btrim(input_payload->>'description'),'') is null or nullif(btrim(input_payload->>'treatment'),'') is null then raise exception 'risk_core_fields_required';end if;
 if jsonb_array_length(coalesce(input_payload->'source_refs','[]'::jsonb))=0 then raise exception 'risk_source_evidence_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('organisation_id',target_organisation_id,'project_id',target_project_id,'code',code_value,'title',btrim(input_payload->>'title'),'category',lower(btrim(input_payload->>'category')),'description',btrim(input_payload->>'description'),'probability',prob,'impact',imp,'treatment',btrim(input_payload->>'treatment'),'source_refs',input_payload->'source_refs')::text,'sha256'),'hex');
 perform set_config('conceptspaces.risk_phase','risk_create',true);
 insert into operations.risks(organisation_id,project_id,code,title,category,description,probability,impact,inherent_level,owner_user_id,treatment,residual_level,status,source_refs,review_due_at,client_visible,source_hash,source_signal_id,created_by)
 values(target_organisation_id,target_project_id,code_value,btrim(input_payload->>'title'),lower(btrim(input_payload->>'category')),btrim(input_payload->>'description'),prob,imp,operations.risk_level(prob,imp),nullif(input_payload->>'owner_user_id','')::uuid,btrim(input_payload->>'treatment'),null,'open',input_payload->'source_refs',nullif(input_payload->>'review_due_at','')::timestamptz,coalesce((input_payload->>'client_visible')::boolean,false),h,nullif(input_payload->>'source_signal_id','')::uuid,auth.uid()) returning * into r;
 insert into operations.risk_events(risk_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(r.id,r.organisation_id,r.project_id,'risk.created',null,auth.uid(),to_jsonb(r));
 perform audit.append_event(r.organisation_id,r.project_id,'risk.created','risk',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.create_project_risk(uuid,uuid,jsonb) from public,anon;grant execute on function public.create_project_risk(uuid,uuid,jsonb) to authenticated;

create or replace function public.decide_early_warning(target_signal_id uuid,target_action text,target_reason text,input_payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security invoker
set search_path='operations','project','core','audit','auth','pg_temp' as $$
declare s operations.risk_signals%rowtype; a text:=lower(btrim(target_action)); before_state jsonb; risk_id uuid;
begin
 select * into s from operations.risk_signals where id=target_signal_id for update;if not found then raise exception 'warning_not_found';end if;
 if auth.uid() is null or not ((s.project_id is not null and project.can_manage_project(s.project_id)) or (s.project_id is null and core.has_org_role(s.organisation_id,array['super_admin','org_admin']))) then raise exception 'warning_decision_authority_required';end if;
 if s.status not in ('open','acknowledged') then raise exception 'warning_already_finalised';end if;
 if a not in ('acknowledge','dismiss','convert') then raise exception 'warning_action_invalid';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'warning_decision_reason_required';end if;before_state:=to_jsonb(s);
 if a='convert' then
  risk_id:=public.create_project_risk(s.organisation_id,s.project_id,jsonb_build_object('title',coalesce(input_payload->>'title',s.title),'category',coalesce(input_payload->>'category',s.category),'description',coalesce(input_payload->>'description',s.predicted_consequence),'probability',coalesce(input_payload->>'probability','3'),'impact',coalesce(input_payload->>'impact','3'),'treatment',coalesce(input_payload->>'treatment',s.recommended_action,'Review and mitigate'),'source_refs',s.evidence_refs||jsonb_build_array(jsonb_build_object('warning_id',s.id,'warning_hash',s.evidence_hash)),'source_signal_id',s.id,'review_due_at',input_payload->>'review_due_at','client_visible',coalesce(input_payload->>'client_visible','false')));
  perform set_config('conceptspaces.risk_phase','signal_convert',true);
  update operations.risk_signals set status='converted',acknowledged_by=auth.uid(),acknowledged_at=coalesce(acknowledged_at,now()),converted_risk_id=risk_id where id=s.id returning * into s;
  insert into operations.risk_events(signal_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(s.id,s.organisation_id,s.project_id,'warning.converted',target_reason,auth.uid(),to_jsonb(s));
 elsif a='dismiss' then
  perform set_config('conceptspaces.risk_phase','signal_decide',true);update operations.risk_signals set status='dismissed',dismissed_by=auth.uid(),dismissed_at=now(),dismissal_reason=btrim(target_reason) where id=s.id returning * into s;
  insert into operations.risk_events(signal_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(s.id,s.organisation_id,s.project_id,'warning.dismissed',target_reason,auth.uid(),to_jsonb(s));
 else
  perform set_config('conceptspaces.risk_phase','signal_decide',true);update operations.risk_signals set status='acknowledged',acknowledged_by=auth.uid(),acknowledged_at=now() where id=s.id returning * into s;
  insert into operations.risk_events(signal_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(s.id,s.organisation_id,s.project_id,'warning.acknowledged',target_reason,auth.uid(),to_jsonb(s));
 end if;
 perform audit.append_event(s.organisation_id,s.project_id,'warning.'||case when a='acknowledge' then 'acknowledged' when a='dismiss' then 'dismissed' else 'converted' end,'risk_signal',s.id,before_state,to_jsonb(s),target_reason,gen_random_uuid());return jsonb_build_object('signal_id',s.id,'status',s.status,'risk_id',risk_id);
end;$$;
revoke all on function public.decide_early_warning(uuid,text,text,jsonb) from public,anon;grant execute on function public.decide_early_warning(uuid,text,text,jsonb) to authenticated;

create or replace function public.transition_project_risk(target_risk_id uuid,target_status text,target_reason text,input_payload jsonb default '{}'::jsonb)
returns text language plpgsql security invoker
set search_path='operations','project','core','audit','auth','pg_temp' as $$
declare r operations.risks%rowtype; s text:=lower(btrim(target_status)); before_state jsonb; allowed boolean:=false;
begin
 select * into r from operations.risks where id=target_risk_id for update;if not found then raise exception 'risk_not_found';end if;
 if auth.uid() is null or not ((r.project_id is not null and project.can_manage_project(r.project_id)) or (r.project_id is null and core.has_org_role(r.organisation_id,array['super_admin','org_admin']))) then raise exception 'risk_transition_authority_required';end if;
 allowed:=(r.status='open' and s in ('mitigating','accepted','closed')) or (r.status='mitigating' and s in ('accepted','closed','open')) or (r.status='accepted' and s in ('open','closed'));
 if not allowed then raise exception 'risk_transition_invalid';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'risk_transition_reason_required';end if;
 if s='accepted' and (r.created_by=auth.uid() or nullif(btrim(input_payload->>'acceptance_reason'),'') is null) then raise exception 'risk_acceptance_requires_independent_reasoned_authority';end if;
 before_state:=to_jsonb(r);perform set_config('conceptspaces.risk_phase','risk_transition',true);
 update operations.risks set status=s,treatment=coalesce(nullif(btrim(input_payload->>'treatment'),''),treatment),residual_level=coalesce(nullif(lower(btrim(input_payload->>'residual_level')),''),residual_level),accepted_by=case when s='accepted' then auth.uid() else accepted_by end,accepted_at=case when s='accepted' then now() else accepted_at end,acceptance_reason=case when s='accepted' then btrim(input_payload->>'acceptance_reason') else acceptance_reason end,updated_at=now() where id=r.id returning * into r;
 insert into operations.risk_events(risk_id,organisation_id,project_id,event_type,reason,actor_id,snapshot) values(r.id,r.organisation_id,r.project_id,'risk.'||s,target_reason,auth.uid(),to_jsonb(r));
 perform audit.append_event(r.organisation_id,r.project_id,'risk.'||s,'risk',r.id,before_state,to_jsonb(r),target_reason,gen_random_uuid());return r.status;
end;$$;
revoke all on function public.transition_project_risk(uuid,text,text,jsonb) from public,anon;grant execute on function public.transition_project_risk(uuid,text,text,jsonb) to authenticated;

create or replace function public.list_risk_portfolio_workspace(target_organisation_id uuid,target_project_id uuid default null)
returns jsonb language plpgsql stable security invoker
set search_path='operations','project','coordination','public','core','auth','pg_temp' as $$
declare financial_visible boolean:=core.has_org_role(target_organisation_id,array['super_admin','org_admin','finance']);
begin
 if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_access_required';end if;
 if target_project_id is not null and not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return jsonb_build_object(
  'risks',coalesce((select jsonb_agg(to_jsonb(r) order by case r.inherent_level when 'critical' then 0 when 'high' then 1 when 'medium' then 2 else 3 end,r.updated_at desc) from operations.risks r where r.organisation_id=target_organisation_id and (target_project_id is null or r.project_id=target_project_id) and (r.project_id is null or project.can_access_project(r.project_id))),'[]'::jsonb),
  'warnings',coalesce((select jsonb_agg(to_jsonb(s) order by case s.status when 'open' then 0 when 'acknowledged' then 1 else 2 end,s.created_at desc) from operations.risk_signals s where s.organisation_id=target_organisation_id and (target_project_id is null or s.project_id=target_project_id) and (s.project_id is null or project.can_access_project(s.project_id))),'[]'::jsonb),
  'portfolio',jsonb_build_object(
   'project_count',(select count(*) from project.projects p where p.organisation_id=target_organisation_id and project.can_access_project(p.id)),
   'active_project_count',(select count(*) from project.projects p where p.organisation_id=target_organisation_id and p.status='active' and project.can_access_project(p.id)),
   'pending_approvals',(select count(*) from coordination.approval_requests a join project.projects p on p.id=a.project_id where p.organisation_id=target_organisation_id and a.decision='pending' and project.can_access_project(p.id)),
   'open_high_critical_risks',(select count(*) from operations.risks r where r.organisation_id=target_organisation_id and r.status<>'closed' and r.inherent_level in ('high','critical') and (r.project_id is null or project.can_access_project(r.project_id))),
   'open_warnings',(select count(*) from operations.risk_signals s where s.organisation_id=target_organisation_id and s.status in ('open','acknowledged') and (s.project_id is null or project.can_access_project(s.project_id))),
   'invoice_outstanding_by_currency',case when financial_visible then coalesce((select jsonb_agg(jsonb_build_object('currency',x.currency,'outstanding',x.outstanding)) from (select i.currency,sum(greatest(i.total-i.amount_paid,0)) outstanding from public.invoices i where i.organisation_id=target_organisation_id and i.status in ('issued','part_paid','overdue') and (i.project_id is null or project.can_access_project(i.project_id)) group by i.currency) x),'[]'::jsonb) else jsonb_build_object('masked',true,'reason','finance_role_required') end,
   'sources',jsonb_build_array('project.projects','coordination.approval_requests','operations.risks','operations.risk_signals',case when financial_visible then 'public.invoices' else 'public.invoices:masked' end)
  ),
  'financial_visible',financial_visible
 );
end;$$;
revoke all on function public.list_risk_portfolio_workspace(uuid,uuid) from public,anon;grant execute on function public.list_risk_portfolio_workspace(uuid,uuid) to authenticated;

commit;
