begin;

-- Narrow read facades for live lifecycle workspaces. These expose only resources already readable to the authenticated project participant.
create or replace function public.list_procurement_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,procurement,cost,project,pg_temp
as $$
declare org_id uuid;
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  select organisation_id into org_id from project.projects where id=target_project_id;
  return jsonb_build_object(
    'organisation_id',org_id,
    'vendors',coalesce((select jsonb_agg(to_jsonb(v) order by v.legal_name) from procurement.vendors v where v.organisation_id=org_id),'[]'::jsonb),
    'packages',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'invites',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from procurement.tender_invites i join procurement.tender_packages p on p.id=i.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'bid_counts',coalesce((select jsonb_agg(jsonb_build_object('tender_package_id',p.id,'submitted_count',(select count(*) from procurement.bids b where b.tender_package_id=p.id)) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'bids',coalesce((select jsonb_agg(to_jsonb(b) order by b.submitted_at desc nulls last,b.created_at desc) from procurement.bids b join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'evaluations',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from procurement.bid_evaluations e join procurement.bids b on b.id=e.bid_id join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'purchase_orders',coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at desc) from procurement.purchase_orders po where po.project_id=target_project_id),'[]'::jsonb),
    'goods_receipts',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from procurement.goods_receipts g where g.project_id=target_project_id),'[]'::jsonb),
    'vendor_invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from procurement.vendor_invoices i where i.project_id=target_project_id),'[]'::jsonb),
    'approved_boq_lines',coalesce((select jsonb_agg(to_jsonb(b) order by b.code) from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id where cp.project_id=target_project_id and cp.status='approved'),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_procurement_workspace(uuid) from public,anon;
grant execute on function public.list_procurement_workspace(uuid) to authenticated;

create or replace function public.list_site_delivery_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,site,coordination,project,cost,procurement,cde,pg_temp
as $$;