import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import DesignReviewRuntimeClient,{type DesignReviewWorkspace} from "@/components/DesignReviewRuntimeClient";

export const dynamic="force-dynamic";
type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
const empty:DesignReviewWorkspace={intents:[],branches:[],instructions:[],objects:[]};
export default async function DesignReviewPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as ProjectRow[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state=empty;if(project){const {data,error}=await supabase.rpc("list_design_review_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||empty) as DesignReviewWorkspace;}
 return <>
  <div className="topbar"><div><div className="demo">Architect Review / Voice-to-Design / Object Versioning</div><h1>Governed Design Review</h1><div className="subtle">Deterministic objectives, isolated scenario branches, structured instruction review and object-level revision comparison. Raw voice/text never changes the approved main branch directly.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/design-review?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{!projects.length&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<div style={{marginTop:18}}><DesignReviewRuntimeClient projectId={project.id} state={state}/></div>}
 </>;
}
