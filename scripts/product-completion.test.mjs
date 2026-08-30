import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";

const read=(path)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");

test("the public journey exposes real sign-in and access routes",async()=>{
  const home=await read("apps/web/app/page.tsx");
  assert.match(home,/href="\/login"[^>]*>Sign in/);
  assert.match(home,/href="\/request-access"/);
  assert.match(home,/id="about"/);
  assert.doesNotMatch(home,/being built/i);
});

test("passwordless sign-in cannot create an unauthorised first account",async()=>{
  const actions=await read("apps/web/app/login/actions.ts");
  assert.match(actions,/shouldCreateUser:false/);
  assert.match(actions,/flowType:"implicit"/);
  assert.match(actions,/persistSession:false/);
  assert.match(actions,/createDeviceIndependentMagicLinkClient/);
  assert.match(actions,/over_email_send_rate_limit/);
  assert.match(actions,/cooldown=1/);
  const login=await read("apps/web/app/login/page.tsx");
  assert.match(login,/open the newest link in any browser/);
  assert.match(login,/MagicLinkSubmitButton/);
  const submitButton=await read("apps/web/app/login/MagicLinkSubmitButton.tsx");
  assert.match(submitButton,/useFormStatus/);
  assert.match(submitButton,/disabled=\{pending\}/);
  const migration=await read("supabase/migrations/0124_secure_invite_auth_bootstrap.sql");
  assert.doesNotMatch(migration,/not exists\s*\(select 1 from core\.memberships\)/i);
  assert.match(migration,/first-user bootstrap is forbidden/i);
});

test("only an authenticated administrator can create an invited identity",async()=>{
  const access=await read("apps/web/app/app/admin/access/page.tsx");
  const migration=await read("supabase/migrations/0125_governed_identity_invitations.sql");
  const isolation=await read("supabase/migrations/0126_service_isolated_identity_invitations.sql");
  const edgeFunction=await read("supabase/functions/invite-workspace-identity/index.ts");
  assert.match(access,/requireWorkspaceUser\(\)/);
  assert.match(access,/\["super_admin","org_admin"\]\.includes/);
  assert.match(access,/invite-workspace-identity/);
  assert.match(access,/Initial role/);
  assert.match(access,/role!=="super_admin"/);
  assert.match(migration,/new\.email_confirmed_at is not null/);
  assert.match(migration,/identity\.invitation_accepted/);
  assert.match(edgeFunction,/auth\.admin\.inviteUserByEmail/);
  assert.match(edgeFunction,/SUPABASE_SERVICE_ROLE_KEY/);
  assert.match(isolation,/service_invite_workspace_identity/);
  assert.match(isolation,/to service_role/);
  assert.match(isolation,/drop function if exists public\.invite_workspace_identity/);
});

test("governed audit events use the valid actor value",async()=>{
  const migration=await read("supabase/migrations/0126_service_isolated_identity_invitations.sql");
  assert.match(migration,/then 'system' else 'user' end/);
  assert.match(migration,/conceptspaces\.audit_actor/);
  assert.doesNotMatch(migration,/else 'human' end/);
});

test("server auth refresh, account recovery and sign-out are release-gated",async()=>{
  const proxy=await read("apps/web/lib/supabase-proxy.ts");
  const callback=await read("apps/web/app/auth/callback/route.ts");
  const inviteCompletion=await read("apps/web/app/auth/complete/page.tsx");
  const sidebar=await read("apps/web/components/AppSidebar.tsx");
  assert.match(proxy,/supabase\.auth\.getUser\(\)/);
  assert.match(callback,/exchangeCodeForSession/);
  assert.match(callback,/verifyOtp/);
  assert.match(callback,/\/auth\/complete/);
  assert.match(inviteCompletion,/auth\.setSession/);
  assert.match(inviteCompletion,/history\.replaceState/);
  assert.match(inviteCompletion,/window\.location\.replace\(next\)/);
  assert.match(sidebar,/action=\{signOut\}/);
});

test("authenticated command-centre reads have least-privilege table access",async()=>{
  const migration=await read("supabase/migrations/0127_authenticated_dashboard_read_privileges.sql");
  assert.match(migration,/grant select on core\.organisations to authenticated/);
  assert.match(migration,/grant select on operations\.risks to authenticated/);
  assert.match(migration,/create policy risks_governed_read on operations\.risks/);
  assert.match(migration,/project\.can_access_project\(project_id\)/);
  assert.match(migration,/core\.is_internal_org_member\(organisation_id\)/);
  assert.doesNotMatch(migration,/\bgrant all\b/i);
  assert.doesNotMatch(migration,/\bto anon\b/i);
});

test("authorised project intake supports insert returning without bypassing RLS",async()=>{
  const migration=await read("supabase/migrations/0128_project_creation_returning_rls.sql");
  const scopeGrant=await read("supabase/migrations/0129_engagement_scope_selection_read_privilege.sql");
  const dependencyGrant=await read("supabase/migrations/0130_project_intake_scope_dependency_privileges.sql");
  const route=await read("apps/web/app/api/projects/intake/route.ts");
  assert.match(migration,/create policy projects_read on project\.projects/);
  assert.match(migration,/project\.can_access_project\(id\)/);
  assert.match(migration,/created_by = \(select auth\.uid\(\)\)/);
  assert.match(migration,/core\.has_org_role/);
  assert.match(migration,/project_manager/);
  assert.match(migration,/create policy projects_insert on project\.projects/);
  assert.doesNotMatch(migration,/security definer/i);
  assert.doesNotMatch(migration,/\bgrant all\b/i);
  assert.doesNotMatch(migration,/\bto anon\b/i);
  assert.match(scopeGrant,/grant select on engagement\.scope_selections to authenticated/);
  assert.match(dependencyGrant,/grant select on engagement\.scope_catalogue/);
  assert.match(dependencyGrant,/engagement\.scope_dependency_overrides/);
  assert.doesNotMatch(dependencyGrant,/\bgrant all\b/i);
  assert.doesNotMatch(dependencyGrant,/\bto anon\b/i);
  assert.doesNotMatch(scopeGrant,/\bgrant all\b/i);
  assert.doesNotMatch(scopeGrant,/\bto anon\b/i);
  assert.match(route,/\[projects\.intake\] persistence failed/);
  assert.doesNotMatch(route,/detail:error\.message/);
  assert.match(route,/status:500/);
});

test("project intake records legal parcels, assembled geometry and an explicit brief",async()=>{
  const wizard=await read("apps/web/components/ProjectIntakeWizardLive.tsx");
  const route=await read("apps/web/app/api/projects/intake/route.ts");
  const model=await read("apps/web/lib/project-intake.ts");
  const migration=await read("supabase/migrations/0131_multi_parcel_project_intake.sql");
  assert.match(wizard,/Adjacent plots used as one site/);
  assert.match(wizard,/Add plot/);
  assert.match(wizard,/Combined assembled-site boundary/);
  assert.match(wizard,/Project brief — what do you want designed or built/);
  assert.match(wizard,/localStorage\.setItem/);
  assert.match(model,/sqyd:0\.83612736/);
  assert.match(route,/normaliseParcels/);
  assert.match(route,/project_brief_required/);
  assert.match(route,/parcelGeometry/);
  assert.match(migration,/'site\.parcels'/);
  assert.match(migration,/'plot\.parcel_geometry'/);
  assert.match(migration,/'plot\.assembled_geometry'/);
  assert.match(migration,/'programme\.client_brief'/);
  assert.match(migration,/security invoker/i);
  assert.doesNotMatch(migration,/\bgrant all\b/i);
});

test("project intake captures a governed client billing identity",async()=>{
  const wizard=await read("apps/web/components/ProjectIntakeWizardLive.tsx");
  const route=await read("apps/web/app/api/projects/intake/route.ts");
  const model=await read("apps/web/lib/project-intake.ts");
  const migration=await read("supabase/migrations/0132_client_billing_identity.sql");
  const indexes=await read("supabase/migrations/0133_client_billing_identity_indexes.sql");
  assert.match(wizard,/GST registered\?/);
  assert.match(wizard,/Legal billing name/);
  assert.match(wizard,/Billing state \/ UT/);
  assert.match(wizard,/Registry verification is still required/);
  assert.match(model,/gstinPattern/);
  assert.match(route,/gst_registration_status_required/);
  assert.match(route,/registered_client_billing_identity_required/);
  assert.match(route,/valid_gstin_required/);
  assert.match(migration,/create table public\.client_accounts/);
  assert.match(migration,/client_account_id/);
  assert.match(migration,/gst_registered/);
  assert.match(migration,/gst_verification_status/);
  assert.match(indexes,/client_accounts_created_by_idx/);
  assert.match(indexes,/projects_org_client_account_idx/);
  assert.match(migration,/security invoker/i);
  assert.doesNotMatch(migration,/security definer/i);
  assert.doesNotMatch(migration,/\bgrant all\b/i);
  assert.doesNotMatch(migration,/\bto anon\b/i);
});

test("connected engagement readiness no longer advertises a preview-only platform",async()=>{
  const readiness=await read("apps/web/app/api/engagement/readiness/route.ts");
  assert.doesNotMatch(readiness,/preview-no-persistence/);
  assert.match(readiness,/authenticationConfigured:env\.supabaseConfigured/);
  assert.match(readiness,/persistenceConfigured:env\.supabaseConfigured/);
});

test("automatic Vercel deployments are limited to main",async()=>{
  const config=JSON.parse(await read("vercel.json"));
  assert.equal(config.installCommand,"npm ci");
  assert.equal(config.git.deploymentEnabled.main,true);
  assert.equal(config.git.deploymentEnabled["*"],false);
});
