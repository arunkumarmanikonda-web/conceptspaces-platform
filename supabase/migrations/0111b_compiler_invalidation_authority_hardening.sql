begin;

create or replace function project.invalidate_compiler_runs(target_project_id uuid,target_reason text,target_evidence_hash text)
returns integer
language plpgsql
security definer
set search_path='project','public','regula','core','audit','extensions','auth','pg_temp'
as $$
declare affected int:=0;org_id uuid;allowed boolean:=false;
begin
 if auth.uid() is null then raise exception 'authentication_required';end if;
 if nullif(btrim(target_reason),'') is null then raise exception 'invalidation_reason_required';end if;
 if target_evidence_hash !~ '^[0-9a-f]{64}$' then raise exception 'invalidation_evidence_hash_required';end if;
 select organisation_id into org_id from project.projects where id=target_project_id;if org_id is null then raise exception 'project_not_found';end if;
 allowed:=project.can_manage_project(target_project_id);
 if not allowed then
   allowed:=exists(
     select 1 from regula.project_rule_impacts i join regula.packs p on p.id=i.pack_id
     where i.project_id=target_project_id and i.evidence_hash=target_evidence_hash and i.status='proposed' and p.publication_status='published'
   ) and regula.can_govern_rules();
 end if;
 if not allowed then raise exception 'compiler_invalidation_authority_required';end if;
 update public.compilation_runs r set status='superseded',blocked_reasons=coalesce(r.blocked_reasons,'[]'::jsonb)||jsonb_build_array(jsonb_build_object('code','INPUT_VERSION_STALE','reason',target_reason,'evidence_hash',target_evidence_hash,'invalidated_at',now())) where r.project_id=target_project_id and r.status in ('queued','running','blocked','awaiting_review','completed');
 get diagnostics affected=row_count;
 if affected>0 then perform audit.append_event(org_id,target_project_id,'compiler.input_invalidated','project',target_project_id,null,jsonb_build_object('affected_runs',affected,'reason',target_reason,'evidence_hash',target_evidence_hash),target_evidence_hash,gen_random_uuid());end if;
 return affected;
end;$$;
revoke all on function project.invalidate_compiler_runs(uuid,text,text) from public,anon;
grant execute on function project.invalidate_compiler_runs(uuid,text,text) to authenticated;

commit;
