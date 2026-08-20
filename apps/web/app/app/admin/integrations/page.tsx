import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import ProviderRegistryClient,{type OrgRow,type ProviderRow} from "@/components/ProviderRegistryClient";

export const dynamic="force-dynamic";

export default async function IntegrationsPage({searchParams}:{searchParams:Promise<{org?:string}>}){
  const {supabase}=await requireWorkspaceUser();const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as OrgRow[];const params=await searchParams;const organisation=orgs.find(o=>o.id===params.org)||orgs[0];let rows:ProviderRow[]=[];
  if(organisation){const {data,error}=await supabase.rpc("list_provider_instances",{target_organisation_id:organisation.id});if(error)throw new Error(error.message);rows=(data||[]) as ProviderRow[];}
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Integrations</div><h1>Provider Registry</h1><div className="subtle">Vault-backed provider credentials, signed webhooks, idempotent dispatch and observable health.</div></div></div>
    <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/admin/integrations?org=${o.id}`} className={organisation?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name} · {o.role_code}</Link>)}</div>{orgs.length===0&&<div className="note">No active organisation membership is available.</div>}</section>
    {organisation&&<div style={{marginTop:18}}><ProviderRegistryClient organisation={organisation} rows={rows}/></div>}
    <div className="grid-3" style={{marginTop:18}}><div className="card"><div className="eyebrow">Vault</div><h3>Secrets never round-trip</h3><p>Credential values are encrypted in Supabase Vault and cannot be read back by the Admin UI.</p></div><div className="card"><div className="eyebrow">Delivery</div><h3>Provider workers</h3><p>Resend, AiSensy and Fast2SMS dispatch through governed Edge Functions with retry and health state.</p></div><div className="card"><div className="eyebrow">Payments</div><h3>Razorpay capture authority</h3><p>Only a signature-verified captured webhook can advance an invoice into part-paid or paid state.</p></div></div>
  </>;
}
