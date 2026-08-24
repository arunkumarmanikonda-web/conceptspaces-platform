begin;

create table if not exists engineering.structural_invalidations(
 id uuid primary key default gen_random_uuid(),
 project_id uuid not null references project.projects(id) on delete cascade,
 structural_scheme_id uuid not null references engineering.structural_schemes(id) on delete cascade,
 prior_architecture_package_id uuid references engineering.architecture_packages(id) on delete set null,
 invalidating_architecture_package_id uuid not null references engineering.architecture_packages(id) on delete restrict,
 prior_architecture_hash text,
 invalidating_architecture_hash text not null,
 reason text not null,
 affected_calculation_run_ids jsonb not null default '[]'::jsonb,
 invalidation_hash text not null,
 detected_at timestamptz not null default now(),
 unique(structural_scheme_id,invalidating_architecture_package_id)
);
alter table engineering.structural_invalidations enable row level security;
grant select on engineering.structural_invalidations to authenticated;
create policy structural_invalidations_read on engineering.structural_invalidations for select to authenticated using(project.can_access_project(project_id));

create or replace function engineering.invalidate_structural_on_architecture_release()
returns trigger
language plpgsql
security definer
set search_path='engineering','project','audit','extensions','pg_temp'
as $$
declare s engineering.structural_schemes%rowtype;run_ids jsonb;inv_hash text;affected int:=0;
begin
 if new.status not in ('approved','issued') then return new; end if;
 if old.status is not distinct from new.status and old.package_hash is not distinct from new.package_hash then return new; end if;
 for s in select * from engineering.structural_schemes where project_id=new.project_id and source_architecture_package_id is distinct from new.id loop
   select coalesce(jsonb_agg(value order by value),'[]'::jsonb) into run_ids from jsonb_array_elements_text(coalesce(s.calculation_run_ids,'[]'::jsonb)) value;
   inv_hash:=encode(extensions.digest(jsonb_build_object('project_id',new.project_id,'structural_scheme_id',s.id,'prior_architecture_package_id',s.source_architecture_package_id,'prior_architecture_hash',s.source_architecture_hash,'invalidating_architecture_package_id',new.id,'invalidating_architecture_hash',new.package_hash,'affected_calculation_run_ids',run_ids)::text,'sha256'),'hex');
   insert into engineering.structural_invalidations(project_id,structural_scheme_id,prior_architecture_package_id,invalidating_architecture_package_id,prior_architecture_hash,invalidating_architecture_hash,reason,affected_calculation_run_ids,invalidation_hash)
   values(new.project_id,s.id,s.source_architecture_package_id,new.id,s.source_architecture_hash,new.package_hash,'New approved/issued Architecture package supersedes the structural analysis basis',run_ids,inv_hash)
   on conflict(structural_scheme_id,invalidating_architecture_package_id) do nothing;
   update engineering.calculation_runs r set status='superseded'
   where r.project_id=new.project_id and r.status='completed' and r.id in (select value::uuid from jsonb_array_elements_text(run_ids));
   affected:=affected+1;
 end loop;
 if affected>0 then
   perform audit.append_event((select organisation_id from project.projects where id=new.project_id),new.project_id,'structure.architecture_basis_invalidated','architecture_package',new.id,to_jsonb(old),jsonb_build_object('architecture_package_id',new.id,'architecture_hash',new.package_hash,'affected_structural_schemes',affected),'Approved Architecture revision invalidated dependent structural analysis',gen_random_uuid());
 end if;
 return new;
end;$$;
revoke all on function engineering.invalidate_structural_on_architecture_release() from public,anon,authenticated;
drop trigger if exists architecture_release_invalidates_structure on engineering.architecture_packages;
create trigger architecture_release_invalidates_structure after update of status,package_hash on engineering.architecture_packages for each row execute function engineering.invalidate_structural_on_architecture_release();

create or replace function public.capture_release_engineering_check(target_safety_case_id uuid,target_calculation_run_id uuid,target_reason text)
returns uuid language plpgsql security invoker set search_path='public','governance','project','engineering','auth','pg_temp' as $$
declare s governance.release_safety_cases%rowtype;r engineering.calculation_runs%rowtype;en engineering.engines%rowtype;pr engineering.professional_reviews%rowtype;project_criticality text;new_id uuid;
begin
 select * into s from governance.release_safety_cases where id=target_safety_case_id;if not found then raise exception 'release_safety_case_not_found';end if;
 if auth.uid() is null or not project.can_manage_project(s.project_id) then raise exception 'project_manage_authority_required';end if;
 select * into r from engineering.calculation_runs where id=target_calculation_run_id and project_id=s.project_id;if not found then raise exception 'engineering_calculation_not_found_for_project';end if;
 select * into en from engineering.engines where id=r.engine_id;select criticality into project_criticality from project.projects where id=s.project_id;
 if r.status<>'completed' or r.output_hash is null or r.input_hash is null or en.id is null or not en.enabled or en.certification_status not in ('conditionally_approved','approved') or r.engine_version<>en.version or engineering.criticality_rank(project_criticality)>engineering.criticality_rank(en.maximum_criticality) then raise exception 'engineering_calculation_not_release_eligible';end if;
 select * into pr from engineering.professional_reviews x where x.resource_type='calculation' and x.resource_id=r.id and x.resource_hash=r.output_hash and x.decision in ('accepted','accepted_with_comments') and governance.credential_is_current_for_release(x.credential_id,x.reviewer_user_id,r.discipline) order by coalesce(x.reviewed_at,x.created_at) desc,x.id desc limit 1;
 if not found then raise exception 'current_exact_hash_engineering_review_required';end if;
 perform set_config('conceptspaces.release_capture','engineering_check',true);
 new_id:=public.add_release_evidence(s.id,'engineering_check',r.id::text,r.output_hash,true,jsonb_build_object('discipline',r.discipline,'calculation_type',r.calculation_type,'engine_id',r.engine_id,'engine_version',r.engine_version,'unit_system',r.unit_system,'input_hash',r.input_hash,'result_hash',r.output_hash,'output_ref',r.output_ref,'checker_user_id',pr.reviewer_user_id,'checker_credential_id',pr.credential_id,'checker_decision',pr.decision,'checked_at',coalesce(pr.reviewed_at,pr.created_at),'calculation_evidence_refs',r.evidence_refs),coalesce(nullif(btrim(target_reason),''),'Captured professionally reviewed engineering calculation with solver/checker provenance'));
 return new_id;
end;$$;
revoke all on function public.capture_release_engineering_check(uuid,uuid,text) from public,anon;grant execute on function public.capture_release_engineering_check(uuid,uuid,text) to authenticated;

create or replace function public.list_structure_workspace(target_project_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='engineering','project','auth','pg_temp' as $$
begin
 if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required';end if;
 return jsonb_build_object(
  'schemes',coalesce((select jsonb_agg(to_jsonb(s) order by s.version desc) from engineering.structural_schemes s where s.project_id=target_project_id),'[]'::jsonb),
  'architecture_packages',coalesce((select jsonb_agg(to_jsonb(a) order by a.version desc) from engineering.architecture_packages a where a.project_id=target_project_id and a.status in ('approved','issued')),'[]'::jsonb),
  'calculation_runs',coalesce((select jsonb_agg(to_jsonb(c) order by c.created_at desc) from engineering.calculation_runs c where c.project_id=target_project_id and lower(c.discipline) in ('structure','structural')),'[]'::jsonb),
  'engines',coalesce((select jsonb_agg(to_jsonb(e) order by e.code,e.version) from engineering.engines e where lower(e.discipline) in ('structure','structural')),'[]'::jsonb),
  'reviews',coalesce((select jsonb_agg(to_jsonb(r) order by coalesce(r.reviewed_at,r.created_at) desc) from engineering.professional_reviews r where r.project_id=target_project_id and r.discipline in ('structure','structural')),'[]'::jsonb),
  'invalidations',coalesce((select jsonb_agg(to_jsonb(i) order by i.detected_at desc) from engineering.structural_invalidations i where i.project_id=target_project_id),'[]'::jsonb));
end;$$;
revoke all on function public.list_structure_workspace(uuid) from public,anon;grant execute on function public.list_structure_workspace(uuid) to authenticated;

commit;