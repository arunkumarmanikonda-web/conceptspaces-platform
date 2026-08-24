import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import DesignSystemGovernanceClient from "@/components/DesignSystemGovernanceClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};

export default async function DesignSystemPage({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);
 const orgs=(orgData||[]) as Org[];const params=await searchParams;const organisation=orgs.find(o=>o.id===params.org)||orgs[0];
 let workspace:any={tokens:[],components:[],preferences:{},saved_views:[],audits:[],findings:[],localisation:[],glossary:[],help_guides:[]};
 if(organisation){const {data,error}=await supabase.rpc("list_design_system_workspace",{target_organisation_id:organisation.id});if(error)throw new Error(error.message);workspace=data||workspace;}
 return <>
  <div className="topbar"><div><div className="demo">F31 / Design System & Human Factors</div><h1>Design System & Accessibility</h1><div className="subtle">WCAG 2.2 AA target, keyboard-first core workflows, explicit localisation/units, recoverable errors and evidence-gated accessibility review.</div></div></div>
  <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/admin/design-system?org=${o.id}`} className={organisation?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name} · {o.role_code}</Link>)}</div>{!orgs.length&&<div className="note">No active organisation membership is available.</div>}</section>
  {organisation&&<div style={{marginTop:18}}><DesignSystemGovernanceClient organisationId={organisation.id} workspace={workspace}/></div>}
 </>;
}
