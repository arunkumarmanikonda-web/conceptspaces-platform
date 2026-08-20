# Supabase activation runbook

Concept Spaces is intentionally deployable before a dedicated database exists. When a dedicated Supabase project is approved, activate it in this order.

1. Provision a new isolated project in the selected organisation/region.
2. Apply migrations sequentially from `supabase/migrations/0001_*` onward. Never skip or hand-edit production history.
3. Generate TypeScript database types after migrations.
4. Configure publishable browser credentials and server-only service credentials in Vercel.
5. Configure Auth providers and invitation flows.
6. Create private storage buckets for project CDE files and evidence. Public project buckets are prohibited by default.
7. Validate RLS policies for every exposed table/schema before enabling user traffic.
8. Run Supabase security and performance advisors after DDL changes.
9. Seed only reference/configuration data. Do not seed fake production clients, payments or approvals.
10. Verify `/api/readiness` changes from `foundation-preview` to connected state.

## Safety rules
- Never reuse Neejee or Oye Imagine production projects for Concept Spaces data.
- Never store provider secrets in database rows as plaintext.
- Never let service-role keys reach browser code.
- Critical approvals, audit events, payment events and release evidence must be immutable/history-preserving.
- Migrations must be tested in a branch/development database before production changes once branching is enabled.
