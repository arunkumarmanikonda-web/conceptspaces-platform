begin;

create unique index if not exists bids_single_active_vendor_submission_uq
on procurement.bids(tender_package_id,vendor_id)
where status<>'withdrawn';

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
  if vendor_id_value is null or not procurement.current_user_owns_vendor(vendor_id_value) then raise exception 'BID_ACCESS_DENIED'; end if;
  if not procurement.current_user_invited_to_package(p.id,vendor_id_value) then raise exception 'BID_ACCESS_DENIED'; end if;
  if exists(select 1 from procurement.bids existing where existing.tender_package_id=p.id and existing.vendor_id=vendor_id_value and existing.status<>'withdrawn') then raise exception 'BID_ALREADY_SUBMITTED'; end if;
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
  select organisation_id into org_id from procurement.vendors where id=vendor_id_value;
  perform audit.append_event(org_id,p.project_id,'procurement.bid.submitted','bid',b.id,null,jsonb_build_object('id',b.id,'tender_package_id',b.tender_package_id,'vendor_id',b.vendor_id,'submitted_at',b.submitted_at),encode(extensions.digest((b.id::text||'|'||total_value::text||'|'||b.submitted_at::text),'sha256'),'hex'),gen_random_uuid());
  return b.id;
end;$$;
revoke all on function public.submit_sealed_bid(uuid,jsonb) from public,anon;
grant execute on function public.submit_sealed_bid(uuid,jsonb) to authenticated;

commit;
