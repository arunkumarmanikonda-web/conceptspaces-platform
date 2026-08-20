import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import CompilerRuntimeClient,{type CompilerState} from "@/components/CompilerRuntimeClient";

export const dynamic="force-dynamic";
type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
const emptyState:CompilerState={run:null,stages:[],candidates:[],branches:[]};
export default async function CompilerPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as ProjectRow[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state=emptyState;if(project){const {data,error}=await supabase.rpc("list_project_compiler_state",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyState) as CompilerState;}
 return <>
  <div className="topbar"><div><div className="demo">Building Compiler™ / Command</div><h1>Compile the Project</h1><div className="subtle">Immutable input snapshots, deterministic feasibility, governed stage execution and Proof Before Publish boundaries.</div></div><Link className="btn" href="/app/projects/new">New Input Session</Link></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/compiler?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<div style={{marginTop:18}}><CompilerRuntimeClient projectId={project.id} state={state}/></div>}
 </>;
}
