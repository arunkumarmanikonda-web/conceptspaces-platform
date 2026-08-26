import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import ReliabilityWorkspaceClient,{type SreState} from "@/components/ReliabilityWorkspaceClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};type ProjectChoice={id:string;code:string;name:string};
export default async function ReliabilityPage({searchParams}:{searchParams:Promise<{org?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as Org[];const params=await searchParams;const org=orgs.find(o=>o.id===params.org)||orgs[0];let state:SreState={jobs:[],providers:[],slos:[],incidents:[],drills:[]};let projects:ProjectChoice[]=[];
 if(org){const [{data,error},{data:projectData,error:projectError}]=await Promise.all([supabase.rpc("list_sre_workspace",{target_organisation_id:org.id}),supabase.rpc("list_accessible_projects_for_org",{target_organisation_id:org.id})]);if(error)throw new Error(error.message);if(projectError)throw new Error(projectError.message);state=data as SreState;projects=(projectData||[]) as ProjectChoice[];}
 return <>
  <div className="topbar"><div><div className="demo">Platform Reliability / SRE</div><h1>Reliability, Jobs & Continuity</h1><div className="subtle">Measured SLOs, immutable compute jobs, trace-linked failures, provider circuit state, incident command and evidence-tested disaster recovery.</div></div></div>
  <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/reliability?org=${o.id}`} className={org?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name}</Link>)}</div></section>
  {org?<div style={{marginTop:16}}><ReliabilityWorkspaceClient organisationId={org.id} projects={projects} state={state}/></div>:<div className="note" style={{marginTop:18}}>No active organisation membership is available.</div>}
 </>;
}
