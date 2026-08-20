begin;

create table if not exists procurement.vendor_users(
  vendor_id uuid not null references procurement.vendors(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'active' check(status in ('active','revoked')),
  created_at timestamptz not null default now(),
  primary key(vendor_id,user_id)
);

alter table procurement.tender_packages add column if not exists opening_at timestamptz;
alter table procurement.tender_packages add column if not exists opened_at timestamptz;
alter table procurement.tender_packages add column if not exists opened_by uuid references auth.users(id);
alter table procurement.tender_packages add column if not exists opening_authority_role text;
alter table procurement.tender_packages add column if not exists selected_bid_id uuid;
alter table procurement.tender_packages add column if not exists award_decision_hash text;
alter table procurement.tender_packages add column if not exists negotiation_summary jsonb not null default '{}'::jsonb;
alter table procurement.tender_packages add column if not exists award_reason text;

create table if not exists procurement.clarifications(
  id uuid primary key default gen_random_uuid(),
  tender_package_id uuid not null references procurement.tender_packages(id) on delete cascade,
  vendor_id uuid references procurement.vendors(id) on delete set null,
  question text not null,
  response text,
  status text not null default 'open' check(status in ('open','answered','closed')),
  raised_by uuid references auth.users(id),
  responded_by uuid references auth.users(id),
  due_at timestamptz,
  created_at timestamptz not null default now(),
  answered_at timestamptz
);

create table if not exists procurement.bid_evaluations(
  id uuid primary key default gen_random_uuid(),
  bid_id uuid not null references procurement.bids(id) on delete cascade,
  evaluation_type text not null check(evaluation_type in ('technical','commercial')),
  decision text not null check(decision in ('qualified','rejected','ranked','recommended','not_recommended')),
  score numeric,
  normalised_total numeric,
  exclusions_summary jsonb not null default '[]'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  evaluation_hash text not null,
  reviewed_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(bid_id,evaluation_type,reviewed_by)
);

create table if not exists procurement.purchase_orders(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  tender_package_id uuid not null references procurement.tender_packages(id) on delete restrict,
  selected_bid_id uuid not null references procurement.bids(id) on delete restrict,
  vendor_id uuid not null references procurement.vendors(id) on delete restrict,
  po_number text not null,
  version integer not null default 1,
  parent_po_id uuid references procurement.purchase_orders(id) on delete set null,
  currency text not null default 'INR',
  total numeric not null default 0,
  approved_variation_total numeric not null default 0,
  scope_snapshot jsonb not null default '{}'::jsonb,
  terms jsonb not null default '{}'::jsonb,
  delivery_schedule jsonb not null default '[]'::jsonb,
  decision_hash text not null,
  status text not null default 'draft' check(status in ('draft','approved','issued','delivering','closed','superseded','cancelled')),
  created_by uuid references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  issued_by uuid references auth.users(id),
  issued_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(project_id,po_number,version)
);

create table if not exists procurement.material_submittals(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  purchase_order_id uuid references procurement.purchase_orders(id) on delete set null,
  submittal_code text not null,
  item_ref text not null,
  proposed_product_ref text not null,
  technical_evidence jsonb not null default '[]'::jsonb,
  model_object_refs jsonb not null default '[]'::jsonb,
  status text not null default 'draft' check(status in ('draft','submitted','approved','rejected','superseded')),
  submitted_by uuid references auth.users(id),
  reviewed_by uuid references auth.users(id),
  review_note text,
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  unique(project_id,submittal_code)
);

create table if not exists procurement.goods_receipts(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  purchase_order_id uuid not null references procurement.purchase_orders(id) on delete restrict,
  grn_number text not null,
  receipt_date date not null,
  lines jsonb not null default '[]'::jsonb,
  inspection_result text not null default 'pending' check(inspection_result in ('pending','accepted','conditional','rejected')),
  evidence_refs jsonb not null default '[]'::jsonb,
  posted_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  unique(project_id,grn_number)
);

create table if not exists procurement.vendor_invoices(
  id uuid primary key default gen_random_uuid(),
  project_id uuid not null references project.projects(id) on delete cascade,
  purchase_order_id uuid not null references procurement.purchase_orders(id) on delete restrict,
  vendor_id uuid not null references procurement.vendors(id) on delete restrict,
  invoice_number text not null,
  invoice_date date not null,
  currency text not null default 'INR',
  total numeric not null,
  matched_po_value numeric not null default 0,
  matched_receipt_value numeric not null default 0,
  variance numeric not null default 0,
  match_result jsonb not null default '{}'::jsonb,
  evidence_refs jsonb not null default '[]'::jsonb,
  status text not null default 'received' check(status in ('received','matching','exception','approved','posted','rejected')),
  created_by uuid references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(vendor_id,invoice_number)
);

alter table procurement.tender_packages drop constraint if exists tender_packages_selected_bid_id_fkey;
alter table procurement.tender_packages add constraint tender_packages_selected_bid_id_fkey foreign key(selected_bid_id) references procurement.bids(id) on delete set null;

create index if not exists vendor_users_user_idx on procurement.vendor_users(user_id,status);
create index if not exists tender_packages_opening_idx on procurement.tender_packages(project_id,opening_at,status);
create index if not exists bid_evaluations_bid_idx on procurement.bid_evaluations(bid_id,evaluation_type);
create index if not exists purchase_orders_project_idx on procurement.purchase_orders(project_id,status,created_at desc);
create index if not exists goods_receipts_po_idx on procurement.goods_receipts(purchase_order_id,receipt_date desc);
create index if not exists vendor_invoices_po_idx on procurement.vendor_invoices(purchase_order_id,status);

alter table procurement.vendor_users enable row level security;
alter table procurement.clarifications enable row level security;
alter table procurement.bid_evaluations enable row level security;
alter table procurement.purchase_orders enable row level security;
alter table procurement.material_submittals enable row level security;
alter table procurement.goods_receipts enable row level security;
alter table procurement.vendor_invoices enable row level security;

drop policy if exists cs_read on procurement.bids;
drop policy if exists cs_read on procurement.bid_lines;

drop policy if exists vendor_users_read on procurement.vendor_users;
create policy vendor_users_read on procurement.vendor_users for select to authenticated using(user_id=auth.uid() or exists(select 1 from procurement.vendors v where v.id=vendor_id and core.is_internal_org_member(v.organisation_id)));
drop policy if exists vendor_users_write on procurement.vendor_users;
create policy vendor_users_write on procurement.vendor_users for all to authenticated using(exists(select 1 from procurement.vendors v where v.id=vendor_id and core.is_internal_org_member(v.organisation_id)) and current_setting('conceptspaces.procurement_phase',true)='vendor_map') with check(exists(select 1 from procurement.vendors v where v.id=vendor_id and core.is_internal_org_member(v.organisation_id)) and current_setting('conceptspaces.procurement_phase',true)='vendor_map');

drop policy if exists vendor_self_read on procurement.vendors;
create policy vendor_self_read on procurement.vendors for select to authenticated using(exists(select 1 from procurement.vendor_users vu where vu.vendor_id=id and vu.user_id=auth.uid() and vu.status='active'));

drop policy if exists tender_vendor_read on procurement.tender_packages;
create policy tender_vendor_read on procurement.tender_packages for select to authenticated using(exists(select 1 from procurement.tender_invites ti join procurement.vendor_users vu on vu.vendor_id=ti.vendor_id where ti.tender_package_id=id and vu.user_id=auth.uid() and vu.status='active'));
drop policy if exists invite_vendor_read on procurement.tender_invites;
create policy invite_vendor_read on procurement.tender_invites for select to authenticated using(exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_id and vu.user_id=auth.uid() and vu.status='active'));

drop policy if exists bids_sealed_read on procurement.bids;
create policy bids_sealed_read on procurement.bids for select to authenticated using(
  exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_id and vu.user_id=auth.uid() and vu.status='active')
  or exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and p.opened_at is not null and project.can_access_project(p.project_id))
);
drop policy if exists bid_lines_sealed_read on procurement.bid_lines;
create policy bid_lines_sealed_read on procurement.bid_lines for select to authenticated using(exists(select 1 from procurement.bids b where b.id=bid_id and (exists(select 1 from procurement.vendor_users vu where vu.vendor_id=b.vendor_id and vu.user_id=auth.uid() and vu.status='active') or exists(select 1 from procurement.tender_packages p where p.id=b.tender_package_id and p.opened_at is not null and project.can_access_project(p.project_id)))));

drop policy if exists vendors_write_insert on procurement.vendors;
create policy vendors_write_insert on procurement.vendors for insert to authenticated with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.procurement_phase',true)='vendor_register');
drop policy if exists vendors_write_update on procurement.vendors;
create policy vendors_write_update on procurement.vendors for update to authenticated using(core.is_internal_org_member(organisation_id)) with check(core.is_internal_org_member(organisation_id) and current_setting('conceptspaces.procurement_phase',true)='vendor_review');

drop policy if exists tender_packages_write_insert on procurement.tender_packages;
create policy tender_packages_write_insert on procurement.tender_packages for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.procurement_phase',true)='package_create');
drop policy if exists tender_packages_write_update on procurement.tender_packages;
create policy tender_packages_write_update on procurement.tender_packages for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.procurement_phase',true) in ('rfq_issue','bid_open','award'));

drop policy if exists tender_boq_write on procurement.tender_boq_lines;
create policy tender_boq_write on procurement.tender_boq_lines for insert to authenticated with check(current_setting('conceptspaces.procurement_phase',true)='package_create' and exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and project.can_manage_project(p.project_id)));
drop policy if exists tender_invites_write on procurement.tender_invites;
create policy tender_invites_write on procurement.tender_invites for insert to authenticated with check(current_setting('conceptspaces.procurement_phase',true)='rfq_issue' and exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and project.can_manage_project(p.project_id)));

drop policy if exists bids_vendor_insert on procurement.bids;
create policy bids_vendor_insert on procurement.bids for insert to authenticated with check(current_setting('conceptspaces.procurement_phase',true)='bid_submit' and exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_id and vu.user_id=auth.uid() and vu.status='active'));
drop policy if exists bids_internal_update on procurement.bids;
create policy bids_internal_update on procurement.bids for update to authenticated using(exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and project.can_manage_project(p.project_id))) with check(current_setting('conceptspaces.procurement_phase',true) in ('evaluate','award') and exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and project.can_manage_project(p.project_id)));
drop policy if exists bid_lines_vendor_insert on procurement.bid_lines;
create policy bid_lines_vendor_insert on procurement.bid_lines for insert to authenticated with check(current_setting('conceptspaces.procurement_phase',true)='bid_submit' and exists(select 1 from procurement.bids b join procurement.vendor_users vu on vu.vendor_id=b.vendor_id where b.id=bid_id and vu.user_id=auth.uid() and vu.status='active'));

drop policy if exists clarifications_read on procurement.clarifications;
create policy clarifications_read on procurement.clarifications for select to authenticated using(exists(select 1 from procurement.tender_packages p where p.id=tender_package_id and project.can_access_project(p.project_id)) or (vendor_id is not null and exists(select 1 from procurement.vendor_users vu where vu.vendor_id=clarifications.vendor_id and vu.user_id=auth.uid() and vu.status='active')));
drop policy if exists clarifications_write on procurement.clarifications;
create policy clarifications_write on procurement.clarifications for all to authenticated using(current_setting('conceptspaces.procurement_phase',true)='clarification') with check(current_setting('conceptspaces.procurement_phase',true)='clarification');

drop policy if exists bid_evaluations_read on procurement.bid_evaluations;
create policy bid_evaluations_read on procurement.bid_evaluations for select to authenticated using(exists(select 1 from procurement.bids b join procurement.tender_packages p on p.id=b.tender_package_id where b.id=bid_id and p.opened_at is not null and project.can_access_project(p.project_id)));
drop policy if exists bid_evaluations_write on procurement.bid_evaluations;
create policy bid_evaluations_write on procurement.bid_evaluations for insert to authenticated with check(reviewed_by=auth.uid() and current_setting('conceptspaces.procurement_phase',true)='evaluate' and exists(select 1 from procurement.bids b join procurement.tender_packages p on p.id=b.tender_package_id where b.id=bid_id and p.opened_at is not null and project.can_manage_project(p.project_id)));

drop policy if exists purchase_orders_read on procurement.purchase_orders;
create policy purchase_orders_read on procurement.purchase_orders for select to authenticated using(project.can_access_project(project_id) or exists(select 1 from procurement.vendor_users vu where vu.vendor_id=purchase_orders.vendor_id and vu.user_id=auth.uid() and vu.status='active'));
drop policy if exists purchase_orders_insert on procurement.purchase_orders;
create policy purchase_orders_insert on procurement.purchase_orders for insert to authenticated with check(project.can_manage_project(project_id) and created_by=auth.uid() and current_setting('conceptspaces.procurement_phase',true) in ('po_create','po_amend'));
drop policy if exists purchase_orders_update on procurement.purchase_orders;
create policy purchase_orders_update on procurement.purchase_orders for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.procurement_phase',true)='po_transition');

drop policy if exists material_submittals_read on procurement.material_submittals;
create policy material_submittals_read on procurement.material_submittals for select to authenticated using(project.can_access_project(project_id));
drop policy if exists material_submittals_write on procurement.material_submittals;
create policy material_submittals_write on procurement.material_submittals for all to authenticated using(project.can_manage_project(project_id) and current_setting('conceptspaces.procurement_phase',true)='submittal') with check(project.can_manage_project(project_id) and current_setting('conceptspaces.procurement_phase',true)='submittal');

drop policy if exists goods_receipts_read on procurement.goods_receipts;
create policy goods_receipts_read on procurement.goods_receipts for select to authenticated using(project.can_access_project(project_id));
drop policy if exists goods_receipts_insert on procurement.goods_receipts;
create policy goods_receipts_insert on procurement.goods_receipts for insert to authenticated with check(project.can_manage_project(project_id) and posted_by=auth.uid() and current_setting('conceptspaces.procurement_phase',true)='grn');

drop policy if exists vendor_invoices_read on procurement.vendor_invoices;
create policy vendor_invoices_read on procurement.vendor_invoices for select to authenticated using(project.can_access_project(project_id) or exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_invoices.vendor_id and vu.user_id=auth.uid() and vu.status='active'));
drop policy if exists vendor_invoices_insert on procurement.vendor_invoices;
create policy vendor_invoices_insert on procurement.vendor_invoices for insert to authenticated with check(current_setting('conceptspaces.procurement_phase',true)='vendor_invoice' and (project.can_manage_project(project_id) or exists(select 1 from procurement.vendor_users vu where vu.vendor_id=vendor_invoices.vendor_id and vu.user_id=auth.uid() and vu.status='active')));
drop policy if exists vendor_invoices_update on procurement.vendor_invoices;
create policy vendor_invoices_update on procurement.vendor_invoices for update to authenticated using(project.can_manage_project(project_id)) with check(project.can_manage_project(project_id) and current_setting('conceptspaces.procurement_phase',true)='invoice_review');

grant select,insert,update on procurement.vendor_users to authenticated;
grant insert,update on procurement.vendors to authenticated;
grant insert,update on procurement.tender_packages to authenticated;
grant insert on procurement.tender_boq_lines,procurement.tender_invites,procurement.bid_lines,procurement.bid_evaluations,procurement.goods_receipts to authenticated;
grant insert,update on procurement.bids,procurement.clarifications,procurement.purchase_orders,procurement.material_submittals,procurement.vendor_invoices to authenticated;
grant select on procurement.clarifications,procurement.bid_evaluations,procurement.purchase_orders,procurement.material_submittals,procurement.goods_receipts,procurement.vendor_invoices,procurement.vendor_users to authenticated;

commit;