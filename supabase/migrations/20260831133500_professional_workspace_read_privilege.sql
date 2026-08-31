begin;

-- list_professional_workspace is SECURITY INVOKER. RLS already restricts rows,
-- but the authenticated role also requires the underlying SELECT privilege.
grant usage on schema engagement to authenticated;
grant select on engagement.project_professional_assignments to authenticated;

-- PostgREST only exposes the public schema in this deployment. Keep the
-- feasibility tables private and provide narrow, authority-checked RPCs for
-- the typology registry instead of addressing the schema from the browser.
create or replace function public.list_admin_typology_packs()
returns jsonb
language plpgsql
stable
security invoker
set search_path = 'feasibility','core','auth','pg_temp'
as $$
begin
  if auth.uid() is null or not core.is_platform_admin() then
    raise exception 'platform_admin_authority_required';
  end if;
  return coalesce((
    select jsonb_agg(to_jsonb(t) order by t.typology,t.version desc)
    from feasibility.typology_packs t
  ), '[]'::jsonb);
end;
$$;

create or replace function public.create_admin_typology_pack(input_payload jsonb)
returns uuid
language plpgsql
security invoker
set search_path = 'feasibility','core','auth','pg_temp'
as $$
declare
  created_id uuid;
begin
  if auth.uid() is null or not core.is_platform_admin() then
    raise exception 'platform_admin_authority_required';
  end if;
  if nullif(btrim(input_payload->>'code'),'') is null
     or nullif(btrim(input_payload->>'name'),'') is null
     or nullif(btrim(input_payload->>'typology'),'') is null then
    raise exception 'typology_pack_identity_required';
  end if;
  insert into feasibility.typology_packs(
    code,name,typology,version,programme_categories,planning_principles,
    operational_principles,engineering_considerations,
    sustainability_considerations,commercial_drivers,benchmark_sources,
    questionnaire,state,created_by
  ) values (
    upper(btrim(input_payload->>'code')),btrim(input_payload->>'name'),
    lower(btrim(input_payload->>'typology')),1,
    coalesce(input_payload->'programme_categories','[]'::jsonb),
    coalesce(input_payload->'planning_principles','[]'::jsonb),
    coalesce(input_payload->'operational_principles','[]'::jsonb),
    coalesce(input_payload->'engineering_considerations','[]'::jsonb),
    coalesce(input_payload->'sustainability_considerations','[]'::jsonb),
    coalesce(input_payload->'commercial_drivers','[]'::jsonb),
    coalesce(input_payload->'benchmark_sources','[]'::jsonb),
    coalesce(input_payload->'questionnaire','[]'::jsonb),'draft',auth.uid()
  ) returning id into created_id;
  return created_id;
end;
$$;

revoke all on function public.list_admin_typology_packs() from public,anon;
revoke all on function public.create_admin_typology_pack(jsonb) from public,anon;
grant execute on function public.list_admin_typology_packs() to authenticated;
grant execute on function public.create_admin_typology_pack(jsonb) to authenticated;

-- Workspace facade functions are security-invoker by design. Their callers
-- therefore need the underlying read privileges; RLS remains the tenant and
-- project boundary.
grant select on engagement.activations to authenticated;
grant select on cost.qto_runs, cost.quantity_items, cost.cost_plans, cost.boq_lines to authenticated;
grant usage on schema procurement to authenticated;
grant select on procurement.vendors, procurement.tender_packages,
  procurement.tender_invites, procurement.clarifications, procurement.bids,
  procurement.bid_evaluations, procurement.purchase_orders,
  procurement.goods_receipts, procurement.vendor_invoices to authenticated;
grant usage on schema analytics to authenticated;
grant select on analytics.kpi_definitions, analytics.kpi_observations to authenticated;
grant select on workflow.jobs to authenticated;
grant select on operations.service_slos, operations.service_telemetry to authenticated;

-- Superseded vendor policy from the foundation release was left active beside
-- the hardened security-definer helper and recursively re-entered package RLS.
drop policy if exists tender_vendor_read on procurement.tender_packages;

commit;
