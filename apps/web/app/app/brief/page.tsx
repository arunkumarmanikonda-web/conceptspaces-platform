import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import BriefRequirementsClient,{type BriefRequirementWorkspace} from "@/components/BriefRequirementsClient";

export const dynamic="force-dynamic";
type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
const empty:BriefRequirementWorkspace={typology_packs:[],briefs:[],programme_briefs:[],requirements:[],revisions:[],trace_links:[]};
export default async function BriefPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as ProjectRow[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state=empty;if(project){const {data,error}=await supabase.rpc("list_brief_requirement_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||empty) as BriefRequirementWorkspace;}
 return <>
  <div className="topbar"><div><div className="demo">Brief / Requirements / Typology</div><h1>Brief Intelligence & Requirement Traceability</h1><div className="subtle">Draft interpretation remains unapproved until human confirmation. Approved requirement revisions preserve history and trigger governed downstream impact analysis.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/brief?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{!projects.length&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<div style={{marginTop:18}}><BriefRequirementsClient projectId={project.id} state={state}/></div>}
 </>;
}
