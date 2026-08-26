begin;

alter table regula.packs add column if not exists version integer;
alter table regula.packs add column if not exists content_hash text;
alter table regula.packs add column if not exists created_by uuid references auth.users(id) on delete set null;
alter table regula.packs add column if not exists submitted_by uuid references auth.users(id) on delete set null;
alter table regula.packs add column if not exists submitted_at timestamptz;
alter table regula.packs add column if not exists technical_reviewed_by uuid references auth.users(id) on delete set null;
alter table regula.packs add column if not exists technical_reviewed_at timestamptz;
alter table regula.packs add column if not exists published_by uuid references auth.users(id) on delete set null;
alter table regula.packs add column if not exists published_at timestamptz;
alter table regula.rules add column if not exists clause_reference text;
alter table regula.rules add column if not exists rule_hash text;

with ranked as (
 select id,row_number() over(partition by code order by effective_from,created_at,id)::int as v from regula.packs
) update regula.packs p set version=r.v from ranked r where r.id=p.id and p.version is null;
alter table regula.packs alter column version set not null;
create unique index if not exists regula_pack_code_version_uidx on regula.packs(code,version);

create table if not exists regula.project_rule_impacts(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 pack_id uuid not null references regula.packs(id) on delete cascade,
 impact_type text not null default 'published_pack_candidate',
 status text not null check(status in ('proposed','confirmed','not_applicable','superseded')) default 'proposed',
 reason text not null,
 evidence_hash text not null,
 detected_at timestamptz not null default now(),
 reviewed_by uuid references auth.users(id) on delete set null,
 reviewed_at timestamptz,
 unique(project_id,pack_id)
);
alter table regula.project_rule_impacts enable row level security;
grant select on regula.project_rule_impacts to authenticated;
create policy regula_project_impacts_read on regula.project_rule_impacts for select to authenticated using(project.can_access_project(project_id));

create or replace function regula.can_govern_rules()
returns boolean language sql stable security definer set search_path='core','pg_temp' as $$
 select core.is_platform_admin() or exists(select 1 from core.memberships m where m.user_id=auth.uid() and m.status='active' and m.role_code='regulatory_reviewer');
$$;
revoke all on function regula.can_govern_rules() from public,anon;
grant execute on function regula.can_govern_rules() to authenticated;

grant insert,update on regula.packs,regula.rules to authenticated;
drop policy if exists regula_pack_governed_insert on regula.packs;
create policy regula_pack_governed_insert on regula.packs for insert to authenticated with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true)='draft_pack' and publication_status='draft' and created_by=auth.uid());
drop policy if exists regula_pack_governed_update on regula.packs;
create policy regula_pack_governed_update on regula.packs for update to authenticated using(regula.can_govern_rules()) with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true) in ('submit','technical_review','publish','retire'));
drop policy if exists regula_rule_governed_insert on regula.rules;
create policy regula_rule_governed_insert on regula.rules for insert to authenticated with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true)='draft_rule');
drop policy if exists regula_rule_governed_update on regula.rules;
create policy regula_rule_governed_update on regula.rules for update to authenticated using(regula.can_govern_rules()) with check(regula.can_govern_rules() and current_setting('conceptspaces.regula_admin_phase',true)='draft_rule');

create or replace function regula.guard_published_pack()
returns trigger language plpgsql security definer set search_path='regula','pg_temp' as $$
begin
 if old.publication_status='published' and current_setting('conceptspaces.regula_admin_phase',true)<>'retire' then raise exception 'PUBLISHED_REGULA_PACK_IMMUTABLE'; end if;
 if old.publication_status='published' and (new.code is distinct from old.code or new.version is distinct from old.version or new.authority is distinct from old.authority or new.title is distinct from old.title or new.jurisdiction_country is distinct from old.jurisdiction_country or new.jurisdiction_state is distinct from old.jurisdiction_state or new.jurisdiction_city is distinct from old.jurisdiction_city or new.effective_from is distinct from old.effective_from or new.source_uri is distinct from old.source_uri or new.source_hash is distinct from old.source_hash or new.content_hash is distinct from old.content_hash) then raise exception 'PUBLISHED_REGULA_PACK_CONTENT_IMMUTABLE'; end if;
 return new;
end;$$;
drop trigger if exists regula_published_pack_immutable on regula.packs;
create trigger regula_published_pack_immutable before update on regula.packs for each row execute function regula.guard_published_pack();

create or replace function regula.guard_rule_under_published_pack()
returns trigger language plpgsql security definer set search_path='regula','pg_temp' as $$
begin
 if exists(select 1 from regula.packs p where p.id=old.pack_id and p.publication_status='published') then raise exception 'PUBLISHED_REGULA_RULE_IMMUTABLE'; end if;
 return new;
end;$$;
drop trigger if exists regula_published_rule_immutable on regula.rules;
create trigger regula_published_rule_immutable before update or delete on regula.rules for each row execute function regula.guard_rule_under_published_pack();

create or replace function public.create_regula_pack(input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='regula','audit','extensions','auth','pg_temp' as $$
declare p regula.packs%rowtype;v int;ef date:=nullif(input_payload->>'effective_from','')::date;h text;
begin
 if auth.uid() is null or not regula.can_govern_rules() then raise exception 'regula_governance_authority_required'; end if;
 if nullif(btrim(input_payload->>'code'),'') is null or nullif(btrim(input_payload->>'title'),'') is null or nullif(btrim(input_payload->>'authority'),'') is null or nullif(btrim(input_payload->>'jurisdiction_country'),'') is null or ef is null or nullif(btrim(input_payload->>'source_uri'),'') is null or lower(coalesce(input_payload->>'source_hash','')) !~ '^[0-9a-f]{64}$' then raise exception 'regula_pack_authority_source_effective_hash_required'; end if;
 select coalesce(max(version),0)+1 into v from regula.packs where code::text=btrim(input_payload->>'code');
 h:=encode(extensions.digest(jsonb_build_object('code',btrim(input_payload->>'code'),'version',v,'title',btrim(input_payload->>'title'),'authority',btrim(input_payload->>'authority'),'jurisdiction_country',upper(btrim(input_payload->>'jurisdiction_country')),'jurisdiction_state',nullif(btrim(input_payload->>'jurisdiction_state'),''),'jurisdiction_city',nullif(btrim(input_payload->>'jurisdiction_city'),''),'effective_from',ef,'effective_until',nullif(input_payload->>'effective_until','')::date,'source_uri',btrim(input_payload->>'source_uri'),'source_hash',lower(input_payload->>'source_hash'))::text,'sha256'),'hex');
 perform set_config('conceptspaces.regula_admin_phase','draft_pack',true);
 insert into regula.packs(jurisdiction_country,jurisdiction_state,jurisdiction_city,authority,code,title,effective_from,effective_until,supersedes_pack_id,publication_status,source_uri,source_hash,version,content_hash,created_by)
 values(upper(btrim(input_payload->>'jurisdiction_country')),nullif(btrim(input_payload->>'jurisdiction_state'),''),nullif(btrim(input_payload->>'jurisdiction_city'),''),btrim(input_payload->>'authority'),btrim(input_payload->>'code'),btrim(input_payload->>'title'),ef,nullif(input_payload->>'effective_until','')::date,nullif(input_payload->>'supersedes_pack_id','')::uuid,'draft',btrim(input_payload->>'source_uri'),lower(input_payload->>'source_hash'),v,h,auth.uid()) returning * into p;
 perform audit.append_event((select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1),null,'regula.pack.drafted','regula_pack',p.id,null,to_jsonb(p),h,gen_random_uuid());return p.id;
end;$$;
revoke all on function public.create_regula_pack(jsonb) from public,anon;grant execute on function public.create_regula_pack(jsonb) to authenticated;

create or replace function public.add_regula_rule(target_pack_id uuid,input_payload jsonb)
returns uuid language plpgsql security invoker set search_path='regula','audit','extensions','auth','pg_temp' as $$
declare p regula.packs%rowtype;r regula.rules%rowtype;h text;
begin
 select * into p from regula.packs where id=target_pack_id for update;if not found or p.publication_status<>'draft' then raise exception 'draft_regula_pack_required';end if;
 if auth.uid() is null or not regula.can_govern_rules() then raise exception 'regula_governance_authority_required';end if;
 if nullif(btrim(input_payload->>'rule_code'),'') is null or nullif(btrim(input_payload->>'subject'),'') is null or nullif(btrim(input_payload->>'narrative'),'') is null or nullif(btrim(input_payload->>'source_reference'),'') is null or nullif(btrim(input_payload->>'clause_reference'),'') is null or nullif(input_payload->>'effective_from','')::date is null then raise exception 'regula_rule_source_clause_effective_required';end if;
 h:=encode(extensions.digest(jsonb_build_object('pack_id',p.id,'pack_hash',p.content_hash,'rule_code',btrim(input_payload->>'rule_code'),'subject',btrim(input_payload->>'subject'),'expression',nullif(btrim(input_payload->>'expression'),''),'narrative',btrim(input_payload->>'narrative'),'source_reference',btrim(input_payload->>'source_reference'),'clause_reference',btrim(input_payload->>'clause_reference'),'effective_from',(input_payload->>'effective_from')::date,'disposition',lower(coalesce(nullif(btrim(input_payload->>'disposition'),''),'amber')),'requires_professional_interpretation',coalesce((input_payload->>'requires_professional_interpretation')::boolean,false))::text,'sha256'),'hex');
 perform set_config('conceptspaces.regula_admin_phase','draft_rule',true);
 insert into regula.rules(pack_id,rule_code,subject,expression,narrative,source_reference,effective_from,disposition,requires_professional_interpretation,metadata,clause_reference,rule_hash)
 values(p.id,btrim(input_payload->>'rule_code'),btrim(input_payload->>'subject'),nullif(btrim(input_payload->>'expression'),''),btrim(input_payload->>'narrative'),btrim(input_payload->>'source_reference'),(input_payload->>'effective_from')::date,lower(coalesce(nullif(btrim(input_payload->>'disposition'),''),'amber')),coalesce((input_payload->>'requires_professional_interpretation')::boolean,false),coalesce(input_payload->'metadata','{}'::jsonb),btrim(input_payload->>'clause_reference'),h) returning * into r;
 perform audit.append_event((select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1),null,'regula.rule.drafted','regula_rule',r.id,null,to_jsonb(r),h,gen_random_uuid());return r.id;
end;$$;
revoke all on function public.add_regula_rule(uuid,jsonb) from public,anon;grant execute on function public.add_regula_rule(uuid,jsonb) to authenticated;

create or replace function public.transition_regula_pack(target_pack_id uuid,target_status text,target_reason text)
returns text language plpgsql security invoker set search_path='regula','project','core','audit','extensions','auth','pg_temp' as $$
declare p regula.packs%rowtype;s text:=lower(btrim(target_status));before_state jsonb;rules_payload jsonb;final_hash text;proj record;
begin
 select * into p from regula.packs where id=target_pack_id for update;if not found then raise exception 'regula_pack_not_found';end if;
 if auth.uid() is null or not regula.can_govern_rules() then raise exception 'regula_governance_authority_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'regula_transition_reason_required';end if;
 before_state:=to_jsonb(p);
 if s='technical_review' then
   if p.publication_status<>'draft' or p.created_by is distinct from auth.uid() then raise exception 'regula_pack_creator_submission_required';end if;
   perform set_config('conceptspaces.regula_admin_phase','submit',true);update regula.packs set publication_status='technical_review',submitted_by=auth.uid(),submitted_at=now(),updated_at=now() where id=p.id returning * into p;
 elsif s='legal_review' then
   if p.publication_status<>'technical_review' or p.created_by=auth.uid() then raise exception 'independent_technical_review_required';end if;
   if not exists(select 1 from regula.rules r where r.pack_id=p.id) then raise exception 'regula_pack_rule_required';end if;
   if exists(select 1 from regula.rules r where r.pack_id=p.id and (nullif(btrim(r.source_reference),'') is null or nullif(btrim(r.clause_reference),'') is null or r.rule_hash is null)) then raise exception 'regula_rule_provenance_incomplete';end if;
   perform set_config('conceptspaces.regula_admin_phase','technical_review',true);update regula.packs set publication_status='legal_review',technical_reviewed_by=auth.uid(),technical_reviewed_at=now(),updated_at=now() where id=p.id returning * into p;
 elsif s='published' then
   if p.publication_status<>'legal_review' or p.created_by=auth.uid() or p.technical_reviewed_by=auth.uid() then raise exception 'independent_legal_publish_required';end if;
   select coalesce(jsonb_agg(jsonb_build_object('rule_id',r.id,'rule_code',r.rule_code::text,'rule_hash',r.rule_hash,'source_reference',r.source_reference,'clause_reference',r.clause_reference,'effective_from',r.effective_from,'disposition',r.disposition,'requires_professional_interpretation',r.requires_professional_interpretation) order by r.rule_code),'[]'::jsonb) into rules_payload from regula.rules r where r.pack_id=p.id;
   final_hash:=encode(extensions.digest(jsonb_build_object('pack_hash',p.content_hash,'rules',rules_payload)::text,'sha256'),'hex');
   perform set_config('conceptspaces.regula_admin_phase','publish',true);update regula.packs set publication_status='published',content_hash=final_hash,published_by=auth.uid(),published_at=now(),updated_at=now() where id=p.id returning * into p;
   for proj in select pr.id,pr.organisation_id from project.projects pr where pr.lifecycle_state='active' and upper(pr.jurisdiction_country)=upper(p.jurisdiction_country) and (p.jurisdiction_state is null or lower(p.jurisdiction_state)=lower(coalesce(pr.jurisdiction_state,''))) and (p.jurisdiction_city is null or lower(p.jurisdiction_city)=lower(coalesce(pr.jurisdiction_city,''))) loop
     insert into regula.project_rule_impacts(project_id,pack_id,reason,evidence_hash) values(proj.id,p.id,'New published REGULA pack matches active project jurisdiction/effective scope',final_hash) on conflict(project_id,pack_id) do update set status='proposed',reason=excluded.reason,evidence_hash=excluded.evidence_hash,detected_at=now();
     perform project.invalidate_compiler_runs(proj.id,'REGULA pack published: '||p.code::text,final_hash);
     perform audit.append_event(proj.organisation_id,proj.id,'project.regulatory_impact_detected','regula_pack',p.id,null,jsonb_build_object('pack_id',p.id,'pack_code',p.code::text,'pack_version',p.version,'pack_hash',final_hash),final_hash,gen_random_uuid());
   end loop;
 elsif s='retired' then
   if p.publication_status<>'published' then raise exception 'published_pack_required_for_retirement';end if;
   perform set_config('conceptspaces.regula_admin_phase','retire',true);update regula.packs set publication_status='retired',effective_until=coalesce(effective_until,current_date),updated_at=now() where id=p.id returning * into p;
 else raise exception 'unsupported_regula_pack_transition';end if;
 perform audit.append_event((select organisation_id from core.memberships where user_id=auth.uid() and status='active' limit 1),null,'regula.pack.'||s,'regula_pack',p.id,before_state,to_jsonb(p),coalesce(final_hash,target_reason),gen_random_uuid());return p.publication_status;
end;$$;
revoke all on function public.transition_regula_pack(uuid,text,text) from public,anon;grant execute on function public.transition_regula_pack(uuid,text,text) to authenticated;

create or replace function public.list_regula_governance_workspace()
returns jsonb language plpgsql stable security invoker set search_path='regula','auth','pg_temp' as $$
begin
 if auth.uid() is null or not regula.can_govern_rules() then raise exception 'regula_governance_authority_required';end if;
 return jsonb_build_object('packs',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from regula.packs p),'[]'::jsonb),'rules',coalesce((select jsonb_agg(to_jsonb(r) order by r.pack_id,r.rule_code) from regula.rules r),'[]'::jsonb),'impacts',coalesce((select jsonb_agg(to_jsonb(i) order by i.detected_at desc) from regula.project_rule_impacts i),'[]'::jsonb));
end;$$;
revoke all on function public.list_regula_governance_workspace() from public,anon;grant execute on function public.list_regula_governance_workspace() to authenticated;

commit;
