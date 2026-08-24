import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import PrivacySecurityClient,{type PrivacySecurityState,type SecurityFinding} from "@/components/PrivacySecurityClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};
export default async function SecurityAdmin({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as Org[];const params=await searchParams;const org=orgs.find(o=>o.id===params.org)||orgs[0];let state:PrivacySecurityState={processing:[],consents:[],retention:[],requests:[],exports:[],projects:[]};let findings:SecurityFinding[]=[];
 if(org){const [{data,error},{data:findingData,error:findingError}]=await Promise.all([supabase.rpc("list_privacy_security_workspace",{target_organisation_id:org.id}),supabase.from("security_findings").select("id,source,title,severity,affected_component,status,detected_at,due_at").order("detected_at",{ascending:false}).limit(100)]);if(error)throw new Error(error.message);if(findingError)throw new Error(findingError.message);state=data as PrivacySecurityState;findings=(findingData||[]) as SecurityFinding[];}
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / Security, Privacy & Audit</div><h1>Security Assurance</h1><div className="subtle">Live project classification, privacy governance, retention, restricted exports, security findings and tamper-evident audit verification.</div></div></div>
  <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/admin/security?org=${o.id}`} className={org?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name}</Link>)}</div></section>
  {org?<div style={{marginTop:16}}><PrivacySecurityClient organisationId={org.id} state={state} findings={findings}/></div>:<div className="note" style={{marginTop:18}}>No active organisation membership is available.</div>}
 </>;
}
