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
