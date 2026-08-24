import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import ApiIntegrationGovernanceClient,{type ApiIntegrationState} from "@/components/ApiIntegrationGovernanceClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};
const empty:ApiIntegrationState={credentials:[],instances:[],subscriptions:[],deliveries:[],webhooks:[],event_definitions:[],data_contracts:[]};
export default async function ApiAccess({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as Org[];const params=await searchParams;const org=orgs.find(o=>o.id===params.org)||orgs[0];let state=empty;
 if(org){const {data,error}=await supabase.rpc("list_api_integration_workspace",{target_organisation_id:org.id});if(error)throw new Error(error.message);state=data as ApiIntegrationState;}
 return <><div className="topbar"><div><div className="demo">Super Admin / API Access</div><h1>API Credentials & Scopes</h1><div className="subtle">One-time secrets, least-privilege scopes, project restrictions, expiry, rate limits, immediate revocation and service-only idempotency enforcement.</div></div></div><section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/admin/api-access?org=${o.id}`} className={org?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name} · {o.role_code}</Link>)}</div></section>{org?<div style={{marginTop:16}}><ApiIntegrationGovernanceClient organisationId={org.id} state={state} view="api"/></div>:<div className="note" style={{marginTop:18}}>No active organisation membership is available.</div>}</>;
}
