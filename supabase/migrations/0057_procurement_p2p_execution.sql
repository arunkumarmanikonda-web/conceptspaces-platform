begin;

create or replace function public.register_procurement_vendor(target_organisation_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,core,audit,extensions,auth,pg_temp
as $$
declare v procurement.vendors%rowtype;
begin
  if auth.uid() is null or not core.is_internal_org_member(target_organisation_id) then raise exception 'organisation_member_required'; end if;
  if nullif(btrim(input_payload->>'legal_name'),'') is null then raise exception 'vendor_legal_name_required'; end if;
  perform set_config('conceptspaces.procurement_phase','vendor_register',true);
  insert into procurement.vendors(organisation_id,legal_name,display_name,gstin,pan,udyam_number,categories,kyc_status,status,metadata)
  values(target_organisation_id,btrim(input_payload->>'legal_name'),nullif(btrim(input_payload->>'display_name'),''),nullif(upper(btrim(input_payload->>'gstin')),''),nullif(upper(btrim(input_payload->>'pan')),''),nullif(upper(btrim(input_payload->>'udyam_number')),''),coalesce(input_payload->'categories','[]'::jsonb),'pending','active',coalesce(input_payload->'metadata','{}'::jsonb)) returning * into v;
  perform audit.append_event(target_organisation_id,null,'procurement.vendor.registered','vendor',v.id,null,to_jsonb(v),null,gen_random_uuid());
  return v.id;
end;$$;
revoke all on function public.register_procurement_vendor(uuid,jsonb) from public,anon;
grant execute on function public.register_procurement_vendor(uuid,jsonb) to authenticated;

create or replace function public.review_procurement_vendor(target_vendor_id uuid,target_kyc_status text,target_status text default 'active',target_reason text default null)
returns text
language plpgsql security invoker
set search_path=public,procurement,core,audit,auth,pg_temp
as $$
declare v procurement.vendors%rowtype; before_state jsonb; k text:=lower(btrim(target_kyc_status)); s text:=lower(btrim(target_status));
begin
  select * into v from procurement.vendors where id=target_vendor_id for update;
  if not found or auth.uid() is null or not core.is_internal_org_member(v.organisation_id) then raise exception 'vendor_review_authority_required'; end if;
  if k not in ('pending','verified','rejected','expired') or s not in ('active','suspended','blacklisted') then raise exception 'unsupported_vendor_state'; end if;
  before_state:=to_jsonb(v); perform set_config('conceptspaces.procurement_phase','vendor_review',true);
  update procurement.vendors set kyc_status=k,status=s,updated_at=now() where id=v.id returning * into v;
  perform audit.append_event(v.organisation_id,null,'procurement.vendor.reviewed','vendor',v.id,before_state,to_jsonb(v),target_reason,gen_random_uuid());
  return v.kyc_status;
end;$$;
revoke all on function public.review_procurement_vendor(uuid,text,text,text) from public,anon;
grant execute on function public.review_procurement_vendor(uuid,text,text,text) to authenticated;

create or replace function public.map_procurement_vendor_user(target_vendor_id uuid,target_user_id uuid,target_status text default 'active')
returns void
language plpgsql security invoker
set search_path=public,procurement,core,auth,pg_temp
as $$
declare v procurement.vendors%rowtype; s text:=lower(btrim(target_status));
begin
  select * into v from procurement.vendors where id=target_vendor_id;
  if not found or auth.uid() is null or not core.is_internal_org_member(v.organisation_id) then raise exception 'vendor_mapping_authority_required'; end if;
  if s not in ('active','revoked') then raise exception 'unsupported_vendor_user_state'; end if;
  perform set_config('conceptspaces.procurement_phase','vendor_map',true);
  insert into procurement.vendor_users(vendor_id,user_id,status) values(v.id,target_user_id,s)
  on conflict(vendor_id,user_id) do update set status=excluded.status;
end;$$;
revoke all on function public.map_procurement_vendor_user(uuid,uuid,text) from public,anon;
grant execute on function public.map_procurement_vendor_user(uuid,uuid,text) to authenticated;

create or replace function public.create_tender_package(target_project_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,cost,project,audit,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; plan cost.cost_plans%rowtype; boq_id uuid; boq_ids jsonb:=coalesce(input_payload->'boq_line_ids','[]'::jsonb); org_id uuid; due_at timestamptz:=nullif(input_payload->>'bid_due_at','')::timestamptz; opening_at_value timestamptz:=nullif(input_payload->>'opening_at','')::timestamptz;
begin
  if auth.uid() is null or not project.can_manage_project(target_project_id) then raise exception 'project_manage_authority_required'; end if;
  if jsonb_typeof(boq_ids)<>'array' or jsonb_array_length(boq_ids)=0 then raise exception 'tender_boq_required'; end if;
  if due_at is null or opening_at_value is null or opening_at_value<due_at then raise exception 'tender_opening_schedule_invalid'; end if;
  if due_at<=now() then raise exception 'tender_due_date_must_be_future'; end if;
  if nullif(btrim(input_payload->>'package_code'),'') is null or nullif(btrim(input_payload->>'title'),'') is null then raise exception 'tender_identity_required'; end if;
  select cp.* into plan from cost.cost_plans cp join cost.boq_lines b on b.cost_plan_id=cp.id where b.id=(boq_ids->>0)::uuid and cp.project_id=target_project_id and cp.status='approved';
  if not found then raise exception 'approved_boq_required'; end if;
  if exists(select 1 from jsonb_array_elements_text(boq_ids) x where not exists(select 1 from cost.boq_lines b where b.id=x::uuid and b.cost_plan_id=plan.id)) then raise exception 'tender_boq_must_share_approved_plan'; end if;
  perform set_config('conceptspaces.procurement_phase','package_create',true);
  insert into procurement.tender_packages(project_id,package_code,title,scope_refs,status,bid_due_at,created_by,opening_at,opening_authority_role)
  values(target_project_id,btrim(input_payload->>'package_code'),btrim(input_payload->>'title'),coalesce(input_payload->'scope_refs','[]'::jsonb),'draft',due_at,auth.uid(),opening_at_value,coalesce(nullif(btrim(input_payload->>'opening_authority_role'),''),'procurement_manager')) returning * into p;
  for boq_id in select value::uuid from jsonb_array_elements_text(boq_ids) loop
    insert into procurement.tender_boq_lines(tender_package_id,boq_line_id) values(p.id,boq_id);
  end loop;
  select organisation_id into org_id from project.projects where id=target_project_id;
  perform audit.append_event(org_id,target_project_id,'procurement.package.created','tender_package',p.id,null,to_jsonb(p),plan.approved_hash,gen_random_uuid());
  return p.id;
end;$$;
revoke all on function public.create_tender_package(uuid,jsonb) from public,anon;
grant execute on function public.create_tender_package(uuid,jsonb) to authenticated;

create or replace function public.issue_tender_rfq(target_package_id uuid,target_vendor_ids uuid[],target_reason text default null)
returns integer
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; vendor_id uuid; count_value int:=0; org_id uuid;
begin
  select * into p from procurement.tender_packages where id=target_package_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'tender_manage_authority_required'; end if;
  if p.status<>'draft' then raise exception 'tender_not_draft'; end if;
  if p.bid_due_at is null or p.opening_at is null or p.bid_due_at<=now() or p.opening_at<p.bid_due_at then raise exception 'tender_schedule_invalid'; end if;
  if target_vendor_ids is null or cardinality(target_vendor_ids)=0 then raise exception 'qualified_bidders_required'; end if;
  if not exists(select 1 from procurement.tender_boq_lines where tender_package_id=p.id) then raise exception 'tender_boq_required'; end if;
  perform set_config('conceptspaces.procurement_phase','rfq_issue',true);
  foreach vendor_id in array target_vendor_ids loop
    if not exists(select 1 from procurement.vendors v join project.projects pr on pr.organisation_id=v.organisation_id where v.id=vendor_id and pr.id=p.project_id and v.status='active' and v.kyc_status='verified') then raise exception 'vendor_not_qualified:%',vendor_id; end if;
    insert into procurement.tender_invites(tender_package_id,vendor_id) values(p.id,vendor_id) on conflict do nothing;
    count_value:=count_value+1;
  end loop;
  update procurement.tender_packages set status='rfq',updated_at=now() where id=p.id returning * into p;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.rfq.issued','tender_package',p.id,null,to_jsonb(p),target_reason,gen_random_uuid());
  return count_value;
end;$$;
revoke all on function public.issue_tender_rfq(uuid,uuid[],text) from public,anon;
grant execute on function public.issue_tender_rfq(uuid,uuid[],text) to authenticated;

create or replace function public.submit_sealed_bid(target_package_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,cost,audit,extensions,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; b procurement.bids%rowtype; vendor_id_value uuid:=nullif(input_payload->>'vendor_id','')::uuid; line jsonb; boq_line cost.boq_lines%rowtype; total_value numeric:=0; qty numeric; rate_value numeric; org_id uuid;
begin
  select * into p from procurement.tender_packages where id=target_package_id;
  if not found or auth.uid() is null then raise exception 'tender_not_found'; end if;
  if p.status<>'rfq' or now()>p.bid_due_at then raise exception 'BID_LATE'; end if;
  if vendor_id_value is null or not exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_id_value and vu.user_id=auth.uid() and vu.status='active') then raise exception 'BID_ACCESS_DENIED'; end if;
  if not exists(select 1 from procurement.tender_invites ti where ti.tender_package_id=p.id and ti.vendor_id=vendor_id_value and ti.declined_at is null) then raise exception 'BID_ACCESS_DENIED'; end if;
  if jsonb_typeof(input_payload->'lines')<>'array' or jsonb_array_length(input_payload->'lines')=0 then raise exception 'bid_lines_required'; end if;
  perform set_config('conceptspaces.procurement_phase','bid_submit',true);
  insert into procurement.bids(tender_package_id,vendor_id,currency,total,commercial_deviations,technical_deviations,status,submitted_at)
  values(p.id,vendor_id_value,upper(coalesce(nullif(btrim(input_payload->>'currency'),''),'INR')),0,coalesce(input_payload->'commercial_deviations','[]'::jsonb),coalesce(input_payload->'technical_deviations','[]'::jsonb),'submitted',now()) returning * into b;
  for line in select value from jsonb_array_elements(input_payload->'lines') loop
    select bl.* into boq_line from cost.boq_lines bl join procurement.tender_boq_lines tbl on tbl.boq_line_id=bl.id where tbl.tender_package_id=p.id and bl.id=(line->>'boq_line_id')::uuid;
    if not found then raise exception 'bid_line_not_in_tender'; end if;
    qty:=coalesce(nullif(line->>'quantity','')::numeric,boq_line.quantity); rate_value:=nullif(line->>'rate','')::numeric;
    if qty is null or qty<0 or rate_value is null or rate_value<0 then raise exception 'bid_line_value_invalid'; end if;
    insert into procurement.bid_lines(bid_id,boq_line_id,quantity,rate,total,exclusions) values(b.id,boq_line.id,qty,rate_value,round(qty*rate_value,2),coalesce(line->'exclusions','[]'::jsonb));
    total_value:=total_value+round(qty*rate_value,2);
  end loop;
  update procurement.bids set total=total_value where id=b.id returning * into b;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.bid.submitted','bid',b.id,null,jsonb_build_object('id',b.id,'tender_package_id',b.tender_package_id,'vendor_id',b.vendor_id,'submitted_at',b.submitted_at),encode(extensions.digest((b.id::text||'|'||total_value::text||'|'||b.submitted_at::text),'sha256'),'hex'),gen_random_uuid());
  return b.id;
end;$$;
revoke all on function public.submit_sealed_bid(uuid,jsonb) from public,anon;
grant execute on function public.submit_sealed_bid(uuid,jsonb) to authenticated;

create or replace function public.open_tender_bids(target_package_id uuid,target_reason text)
returns integer
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; org_id uuid; count_value int;
begin
  select * into p from procurement.tender_packages where id=target_package_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'tender_open_authority_required'; end if;
  if p.status<>'rfq' then raise exception 'tender_not_openable'; end if;
  if p.opening_at is null or now()<p.opening_at then raise exception 'BID_ACCESS_DENIED'; end if;
  if nullif(btrim(target_reason),'') is null then raise exception 'bid_open_reason_required'; end if;
  select count(*) into count_value from procurement.bids where tender_package_id=p.id and status='submitted';
  perform set_config('conceptspaces.procurement_phase','bid_open',true);
  update procurement.tender_packages set opened_at=now(),opened_by=auth.uid(),status=case when count_value>0 then 'evaluation' else 'bid_received' end,updated_at=now() where id=p.id returning * into p;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.bid.opened','tender_package',p.id,null,to_jsonb(p),target_reason,gen_random_uuid());
  return count_value;
end;$$;
revoke all on function public.open_tender_bids(uuid,text) from public,anon;
grant execute on function public.open_tender_bids(uuid,text) to authenticated;

create or replace function public.record_bid_evaluation(target_bid_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,extensions,auth,pg_temp
as $$
declare b procurement.bids%rowtype; p procurement.tender_packages%rowtype; e procurement.bid_evaluations%rowtype; org_id uuid; type_value text:=lower(btrim(input_payload->>'evaluation_type')); decision_value text:=lower(btrim(input_payload->>'decision')); hash_value text;
begin
  select * into b from procurement.bids where id=target_bid_id;
  if not found then raise exception 'bid_not_found'; end if;
  select * into p from procurement.tender_packages where id=b.tender_package_id;
  if p.opened_at is null or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'BID_ACCESS_DENIED'; end if;
  if type_value not in ('technical','commercial') or decision_value not in ('qualified','rejected','ranked','recommended','not_recommended') then raise exception 'unsupported_bid_evaluation'; end if;
  if type_value='technical' and decision_value not in ('qualified','rejected') then raise exception 'technical_evaluation_decision_invalid'; end if;
  if type_value='commercial' and decision_value not in ('ranked','recommended','not_recommended') then raise exception 'commercial_evaluation_decision_invalid'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('bid_id',b.id,'type',type_value,'decision',decision_value,'score',input_payload->>'score','normalised_total',input_payload->>'normalised_total','exclusions',coalesce(input_payload->'exclusions_summary','[]'::jsonb),'evidence',coalesce(input_payload->'evidence_refs','[]'::jsonb))::text,'sha256'),'hex');
  perform set_config('conceptspaces.procurement_phase','evaluate',true);
  insert into procurement.bid_evaluations(bid_id,evaluation_type,decision,score,normalised_total,exclusions_summary,evidence_refs,evaluation_hash,reviewed_by)
  values(b.id,type_value,decision_value,nullif(input_payload->>'score','')::numeric,nullif(input_payload->>'normalised_total','')::numeric,coalesce(input_payload->'exclusions_summary','[]'::jsonb),coalesce(input_payload->'evidence_refs','[]'::jsonb),hash_value,auth.uid()) returning * into e;
  update procurement.bids set status=case when decision_value='rejected' then 'rejected' else 'evaluated' end where id=b.id;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.bid.evaluated','bid_evaluation',e.id,null,to_jsonb(e),hash_value,gen_random_uuid());
  return e.id;
end;$$;
revoke all on function public.record_bid_evaluation(uuid,jsonb) from public,anon;
grant execute on function public.record_bid_evaluation(uuid,jsonb) to authenticated;

create or replace function public.award_tender_package(target_package_id uuid,target_bid_id uuid,input_payload jsonb)
returns text
language plpgsql security invoker
set search_path=public,procurement,project,audit,extensions,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; b procurement.bids%rowtype; org_id uuid; hash_value text;
begin
  select * into p from procurement.tender_packages where id=target_package_id for update;
  if not found or p.opened_at is null or auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'tender_award_authority_required'; end if;
  if p.status not in ('evaluation','bid_received') then raise exception 'tender_not_awardable'; end if;
  select * into b from procurement.bids where id=target_bid_id and tender_package_id=p.id;
  if not found then raise exception 'bid_not_in_tender'; end if;
  if not exists(select 1 from procurement.bid_evaluations where bid_id=b.id and evaluation_type='technical' and decision='qualified') then raise exception 'technical_qualification_required'; end if;
  if not exists(select 1 from procurement.bid_evaluations where bid_id=b.id and evaluation_type='commercial' and decision in ('recommended','ranked')) then raise exception 'commercial_evaluation_required'; end if;
  if nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'award_reason_required'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('package_id',p.id,'bid_id',b.id,'bid_total',b.total,'evaluations',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at),'[]'::jsonb) from procurement.bid_evaluations e where e.bid_id=b.id),'negotiation_summary',coalesce(input_payload->'negotiation_summary','{}'::jsonb),'reason',input_payload->>'reason')::text,'sha256'),'hex');
  perform set_config('conceptspaces.procurement_phase','award',true);
  update procurement.bids set status=case when id=b.id then 'selected' else case when status<>'withdrawn' then 'rejected' else status end end where tender_package_id=p.id;
  update procurement.tender_packages set status='awarded',selected_bid_id=b.id,award_decision_hash=hash_value,negotiation_summary=coalesce(input_payload->'negotiation_summary','{}'::jsonb),award_reason=btrim(input_payload->>'reason'),updated_at=now() where id=p.id returning * into p;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.vendor.selected','tender_package',p.id,null,to_jsonb(p),hash_value,gen_random_uuid());
  return hash_value;
end;$$;
revoke all on function public.award_tender_package(uuid,uuid,jsonb) from public,anon;
grant execute on function public.award_tender_package(uuid,uuid,jsonb) to authenticated;

create or replace function public.create_purchase_order_from_award(target_package_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,extensions,auth,pg_temp
as $$
declare p procurement.tender_packages%rowtype; b procurement.bids%rowtype; po procurement.purchase_orders%rowtype; org_id uuid; total_value numeric; decision_hash_value text;
begin
  select * into p from procurement.tender_packages where id=target_package_id for update;
  if not found or p.status<>'awarded' or p.selected_bid_id is null or p.award_decision_hash is null then raise exception 'awarded_tender_required'; end if;
  if auth.uid() is null or not project.can_manage_project(p.project_id) then raise exception 'po_create_authority_required'; end if;
  select * into b from procurement.bids where id=p.selected_bid_id;
  total_value:=coalesce(nullif(input_payload->>'total','')::numeric,b.total);
  if total_value<0 or total_value>b.total then raise exception 'PO_LIMIT_EXCEEDED'; end if;
  if nullif(btrim(input_payload->>'po_number'),'') is null then raise exception 'po_number_required'; end if;
  decision_hash_value:=encode(extensions.digest(jsonb_build_object('award_decision_hash',p.award_decision_hash,'selected_bid_id',b.id,'po_number',input_payload->>'po_number','total',total_value,'scope_snapshot',coalesce(input_payload->'scope_snapshot','{}'::jsonb),'terms',coalesce(input_payload->'terms','{}'::jsonb),'delivery_schedule',coalesce(input_payload->'delivery_schedule','[]'::jsonb))::text,'sha256'),'hex');
  perform set_config('conceptspaces.procurement_phase','po_create',true);
  insert into procurement.purchase_orders(project_id,tender_package_id,selected_bid_id,vendor_id,po_number,version,currency,total,scope_snapshot,terms,delivery_schedule,decision_hash,status,created_by)
  values(p.project_id,p.id,b.id,b.vendor_id,btrim(input_payload->>'po_number'),1,b.currency,total_value,coalesce(input_payload->'scope_snapshot','{}'::jsonb),coalesce(input_payload->'terms','{}'::jsonb),coalesce(input_payload->'delivery_schedule','[]'::jsonb),decision_hash_value,'draft',auth.uid()) returning * into po;
  select organisation_id into org_id from project.projects where id=p.project_id;
  perform audit.append_event(org_id,p.project_id,'procurement.po.created','purchase_order',po.id,null,to_jsonb(po),decision_hash_value,gen_random_uuid());
  return po.id;
end;$$;
revoke all on function public.create_purchase_order_from_award(uuid,jsonb) from public,anon;
grant execute on function public.create_purchase_order_from_award(uuid,jsonb) to authenticated;

create or replace function public.transition_purchase_order(target_po_id uuid,target_status text,target_reason text)
returns text
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare po procurement.purchase_orders%rowtype; before_state jsonb; s text:=lower(btrim(target_status)); org_id uuid;
begin
  select * into po from procurement.purchase_orders where id=target_po_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(po.project_id) then raise exception 'po_manage_authority_required'; end if;
  if s not in ('approved','issued','delivering','closed','cancelled') then raise exception 'unsupported_po_status'; end if;
  if po.status in ('closed','superseded','cancelled') then raise exception 'terminal_po'; end if;
  if s='approved' and po.status<>'draft' then raise exception 'invalid_po_transition'; end if;
  if s='issued' and po.status<>'approved' then raise exception 'invalid_po_transition'; end if;
  if s='delivering' and po.status<>'issued' then raise exception 'invalid_po_transition'; end if;
  if s='closed' and po.status not in ('issued','delivering') then raise exception 'invalid_po_transition'; end if;
  if s='cancelled' and nullif(btrim(target_reason),'') is null then raise exception 'po_cancel_reason_required'; end if;
  before_state:=to_jsonb(po); perform set_config('conceptspaces.procurement_phase','po_transition',true);
  update procurement.purchase_orders set status=s,approved_by=case when s='approved' then auth.uid() else approved_by end,approved_at=case when s='approved' then now() else approved_at end,issued_by=case when s='issued' then auth.uid() else issued_by end,issued_at=case when s='issued' then now() else issued_at end,updated_at=now() where id=po.id returning * into po;
  if s='issued' and po.parent_po_id is not null then update procurement.purchase_orders set status='superseded',updated_at=now() where id=po.parent_po_id and status not in ('closed','cancelled'); end if;
  select organisation_id into org_id from project.projects where id=po.project_id;
  perform audit.append_event(org_id,po.project_id,'procurement.po.'||s,'purchase_order',po.id,before_state,to_jsonb(po),target_reason,gen_random_uuid());
  return po.status;
end;$$;
revoke all on function public.transition_purchase_order(uuid,text,text) from public,anon;
grant execute on function public.transition_purchase_order(uuid,text,text) to authenticated;

create or replace function public.amend_purchase_order(target_po_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,extensions,auth,pg_temp
as $$
declare source_po procurement.purchase_orders%rowtype; po procurement.purchase_orders%rowtype; org_id uuid; total_value numeric; variation_value numeric; hash_value text;
begin
  select * into source_po from procurement.purchase_orders where id=target_po_id for update;
  if not found or auth.uid() is null or not project.can_manage_project(source_po.project_id) then raise exception 'po_manage_authority_required'; end if;
  if source_po.status not in ('approved','issued','delivering') then raise exception 'po_not_amendable'; end if;
  if nullif(btrim(input_payload->>'reason'),'') is null then raise exception 'po_amendment_reason_required'; end if;
  total_value:=coalesce(nullif(input_payload->>'total','')::numeric,source_po.total); variation_value:=coalesce(nullif(input_payload->>'approved_variation_total','')::numeric,source_po.approved_variation_total);
  if total_value<0 or variation_value<0 then raise exception 'po_amendment_value_invalid'; end if;
  hash_value:=encode(extensions.digest(jsonb_build_object('parent_decision_hash',source_po.decision_hash,'version',source_po.version+1,'total',total_value,'approved_variation_total',variation_value,'reason',input_payload->>'reason','terms',coalesce(input_payload->'terms',source_po.terms),'delivery_schedule',coalesce(input_payload->'delivery_schedule',source_po.delivery_schedule))::text,'sha256'),'hex');
  perform set_config('conceptspaces.procurement_phase','po_amend',true);
  insert into procurement.purchase_orders(project_id,tender_package_id,selected_bid_id,vendor_id,po_number,version,parent_po_id,currency,total,approved_variation_total,scope_snapshot,terms,delivery_schedule,decision_hash,status,created_by)
  values(source_po.project_id,source_po.tender_package_id,source_po.selected_bid_id,source_po.vendor_id,source_po.po_number,source_po.version+1,source_po.id,source_po.currency,total_value,variation_value,coalesce(input_payload->'scope_snapshot',source_po.scope_snapshot),coalesce(input_payload->'terms',source_po.terms),coalesce(input_payload->'delivery_schedule',source_po.delivery_schedule),hash_value,'draft',auth.uid()) returning * into po;
  select organisation_id into org_id from project.projects where id=po.project_id;
  perform audit.append_event(org_id,po.project_id,'procurement.po.amendment_created','purchase_order',po.id,to_jsonb(source_po),to_jsonb(po),input_payload->>'reason',gen_random_uuid());
  return po.id;
end;$$;
revoke all on function public.amend_purchase_order(uuid,jsonb) from public,anon;
grant execute on function public.amend_purchase_order(uuid,jsonb) to authenticated;

create or replace function public.record_goods_receipt(target_po_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare po procurement.purchase_orders%rowtype; g procurement.goods_receipts%rowtype; org_id uuid;
begin
  select * into po from procurement.purchase_orders where id=target_po_id;
  if not found or po.status not in ('issued','delivering','closed') then raise exception 'issued_po_required'; end if;
  if auth.uid() is null or not project.can_manage_project(po.project_id) then raise exception 'grn_authority_required'; end if;
  if jsonb_typeof(input_payload->'lines')<>'array' or jsonb_array_length(input_payload->'lines')=0 then raise exception 'grn_lines_required'; end if;
  if nullif(btrim(input_payload->>'grn_number'),'') is null then raise exception 'grn_number_required'; end if;
  perform set_config('conceptspaces.procurement_phase','grn',true);
  insert into procurement.goods_receipts(project_id,purchase_order_id,grn_number,receipt_date,lines,inspection_result,evidence_refs,posted_by)
  values(po.project_id,po.id,btrim(input_payload->>'grn_number'),coalesce(nullif(input_payload->>'receipt_date','')::date,current_date),input_payload->'lines',coalesce(nullif(lower(btrim(input_payload->>'inspection_result')),''),'pending'),coalesce(input_payload->'evidence_refs','[]'::jsonb),auth.uid()) returning * into g;
  select organisation_id into org_id from project.projects where id=po.project_id;
  perform audit.append_event(org_id,po.project_id,'procurement.grn.posted','goods_receipt',g.id,null,to_jsonb(g),null,gen_random_uuid());
  return g.id;
end;$$;
revoke all on function public.record_goods_receipt(uuid,jsonb) from public,anon;
grant execute on function public.record_goods_receipt(uuid,jsonb) to authenticated;

create or replace function public.record_vendor_invoice_match(target_po_id uuid,input_payload jsonb)
returns uuid
language plpgsql security invoker
set search_path=public,procurement,project,audit,auth,pg_temp
as $$
declare po procurement.purchase_orders%rowtype; vi procurement.vendor_invoices%rowtype; org_id uuid; invoice_total numeric:=nullif(input_payload->>'total','')::numeric; tolerance_value numeric:=coalesce(nullif(input_payload->>'tolerance','')::numeric,0); receipt_value numeric; po_limit numeric; variance_value numeric; status_value text; match_json jsonb;
begin
  select * into po from procurement.purchase_orders where id=target_po_id;
  if not found or po.status not in ('issued','delivering','closed') then raise exception 'issued_po_required'; end if;
  if auth.uid() is null then raise exception 'authentication_required'; end if;
  if not (project.can_manage_project(po.project_id) or exists(select 1 from procurement.vendor_users vu where vu.vendor_id=po.vendor_id and vu.user_id=auth.uid() and vu.status='active')) then raise exception 'vendor_invoice_access_denied'; end if;
  if invoice_total is null or invoice_total<=0 or nullif(btrim(input_payload->>'invoice_number'),'') is null then raise exception 'vendor_invoice_identity_required'; end if;
  po_limit:=po.total+po.approved_variation_total;
  select coalesce(sum(coalesce(nullif(x.value->>'value','')::numeric,coalesce(nullif(x.value->>'quantity','')::numeric,0)*coalesce(nullif(x.value->>'rate','')::numeric,0))),0) into receipt_value
  from procurement.goods_receipts g cross join lateral jsonb_array_elements(g.lines) x(value)
  where g.purchase_order_id=po.id and g.inspection_result in ('accepted','conditional');
  variance_value:=greatest(invoice_total-po_limit,invoice_total-receipt_value,0);
  status_value:=case when variance_value>tolerance_value then 'exception' else 'approved' end;
  match_json:=jsonb_build_object('po_limit',po_limit,'accepted_receipt_value',receipt_value,'invoice_total',invoice_total,'tolerance',tolerance_value,'po_discrepancy',greatest(invoice_total-po_limit,0),'receipt_discrepancy',greatest(invoice_total-receipt_value,0),'matched',variance_value<=tolerance_value);
  perform set_config('conceptspaces.procurement_phase','vendor_invoice',true);
  insert into procurement.vendor_invoices(project_id,purchase_order_id,vendor_id,invoice_number,invoice_date,currency,total,matched_po_value,matched_receipt_value,variance,match_result,evidence_refs,status,created_by)
  values(po.project_id,po.id,po.vendor_id,btrim(input_payload->>'invoice_number'),coalesce(nullif(input_payload->>'invoice_date','')::date,current_date),upper(coalesce(nullif(btrim(input_payload->>'currency'),''),po.currency)),invoice_total,po_limit,receipt_value,variance_value,match_json,coalesce(input_payload->'evidence_refs','[]'::jsonb),status_value,auth.uid()) returning * into vi;
  select organisation_id into org_id from project.projects where id=po.project_id;
  perform audit.append_event(org_id,po.project_id,'procurement.vendor_invoice.matched','vendor_invoice',vi.id,null,to_jsonb(vi),status_value,gen_random_uuid());
  return vi.id;
end;$$;
revoke all on function public.record_vendor_invoice_match(uuid,jsonb) from public,anon;
grant execute on function public.record_vendor_invoice_match(uuid,jsonb) to authenticated;

create or replace function public.list_procurement_workspace(target_project_id uuid)
returns jsonb
language plpgsql stable security invoker
set search_path=public,procurement,cost,project,pg_temp
as $$
begin
  if auth.uid() is null or not project.can_access_project(target_project_id) then raise exception 'project_access_required'; end if;
  return jsonb_build_object(
    'vendors',coalesce((select jsonb_agg(to_jsonb(v) order by v.legal_name) from procurement.vendors v join project.projects p on p.organisation_id=v.organisation_id where p.id=target_project_id),'[]'::jsonb),
    'packages',coalesce((select jsonb_agg(to_jsonb(p) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'bid_counts',coalesce((select jsonb_agg(jsonb_build_object('tender_package_id',p.id,'submitted_count',(select count(*) from procurement.bids b where b.tender_package_id=p.id)) order by p.created_at desc) from procurement.tender_packages p where p.project_id=target_project_id),'[]'::jsonb),
    'bids',coalesce((select jsonb_agg(to_jsonb(b) order by b.submitted_at desc) from procurement.bids b join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'evaluations',coalesce((select jsonb_agg(to_jsonb(e) order by e.created_at desc) from procurement.bid_evaluations e join procurement.bids b on b.id=e.bid_id join procurement.tender_packages p on p.id=b.tender_package_id where p.project_id=target_project_id),'[]'::jsonb),
    'purchase_orders',coalesce((select jsonb_agg(to_jsonb(po) order by po.created_at desc) from procurement.purchase_orders po where po.project_id=target_project_id),'[]'::jsonb),
    'goods_receipts',coalesce((select jsonb_agg(to_jsonb(g) order by g.created_at desc) from procurement.goods_receipts g where g.project_id=target_project_id),'[]'::jsonb),
    'vendor_invoices',coalesce((select jsonb_agg(to_jsonb(i) order by i.created_at desc) from procurement.vendor_invoices i where i.project_id=target_project_id),'[]'::jsonb),
    'approved_boq_lines',coalesce((select jsonb_agg(to_jsonb(b) order by b.code) from cost.boq_lines b join cost.cost_plans cp on cp.id=b.cost_plan_id where cp.project_id=target_project_id and cp.status='approved'),'[]'::jsonb)
  );
end;$$;
revoke all on function public.list_procurement_workspace(uuid) from public,anon;
grant execute on function public.list_procurement_workspace(uuid) to authenticated;

commit;