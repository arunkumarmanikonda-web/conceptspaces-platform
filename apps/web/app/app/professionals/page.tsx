import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import ProfessionalNetworkClient,{type ProfessionalWorkspaceState} from "@/components/ProfessionalNetworkClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};type Project={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
const empty:ProfessionalWorkspaceState={profiles:[],assignments:[],conflicts:[],performance:[],assignment_events:[]};

export default async function ProfessionalsPage({searchParams}:{searchParams:Promise<{org?:string;project?:string}>}){
 const {supabase,user}=await requireWorkspaceUser();const params=await searchParams;
 const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as Org[];const org=orgs.find(o=>o.id===params.org)||orgs[0];let projects:Project[]=[];let project:Project|undefined;let state=empty;
 if(org){const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects_for_org",{target_organisation_id:org.id});if(projectError)throw new Error(projectError.message);projects=(projectData||[]) as Project[];project=projects.find(p=>p.id===params.project)||projects[0];const {data,error}=await supabase.rpc("list_professional_workspace",{target_organisation_id:org.id,target_project_id:project?.id||null});if(error)throw new Error(error.message);state=(data||empty) as ProfessionalWorkspaceState;}
 return <>
  <div className="topbar"><div><div className="demo">F26 / Professional Network & Authority</div><h1>Professional Network</h1><div className="subtle">Credential-aware profiles, deterministic eligibility filtering, workload and conflict controls, history-preserving assignment/replacement, and source-traceable performance.</div></div></div>
  <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/professionals?org=${o.id}`} className={org?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name}</Link>)}</div></section>
  {org&&<><section className="panel"><h3>Project Context</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/professionals?org=${org.id}&project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="subtle">No accessible project. Organisation-level professional profiles and credentials remain available.</div>}</section><ProfessionalNetworkClient organisationId={org.id} projectId={project?.id} currentUserId={user.id} state={state}/></>}
  {!org&&<div className="note">No active organisation membership is available.</div>}
 </>;
}
