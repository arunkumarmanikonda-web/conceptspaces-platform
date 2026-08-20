# Vercel deployment runbook

## One-time project import
1. In the Vercel team `akm's projects`, import GitHub repository `arunkumarmanikonda-web/conceptspaces-platform`.
2. Set project name to `conceptspaces-platform`.
3. Set Root Directory to `apps/web`.
4. Framework preset: Next.js.
5. Keep production branch as `main`.

## Environment policy
- Public variables may use the `NEXT_PUBLIC_` prefix only when intentionally browser-visible.
- Provider secrets must be server-side only.
- Do not place service-role, payment, DNS, communication or AI secret keys in client bundles.
- Preview and Production environments must have independently configurable credentials.

## Foundation preview
The app can deploy without Supabase. `/api/readiness` will report `foundation-preview` and mark provider capabilities false until configured.

## Health validation after each production deployment
- GET `/api/health` must return `status: ok`.
- GET `/api/readiness` must return JSON and accurately reflect configured capabilities.
- Review Vercel build logs for warnings/errors.
- Review runtime errors before promotion of major changes.

## Domain
After the deployment is stable, attach `conceptspaces.live`. DNS changes should be performed only after Vercel provides the exact required records. Preserve rollback/previous records until the new domain verifies.
