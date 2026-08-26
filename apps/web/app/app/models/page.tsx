import {requireWorkspaceUser} from "@/lib/auth";
import ModelWorkspaceClient from "@/components/ModelWorkspaceClient";
import {emptyModelWorkspace,type ModelWorkspaceState,type ProjectRow} from "@/components/lifecycle-runtime-types";

export const dynamic="force-dynamic";

export default async function ModelsPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
 if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ProjectRow[];
 const params=await searchParams;
 const project=projects.find(p=>p.id===params.project)||projects[0];
 let state=emptyModelWorkspace;
 if(project){const {data,error}=await supabase.rpc("list_model_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyModelWorkspace) as ModelWorkspaceState;}
 return <>
  <div className="topbar"><div><div className="demo">OpenBIM / IFC / IDS / BCF</div><h1>Models</h1><div className="subtle">Immutable model revisions, exact validation evidence, structured failure issues and governed approval/issue transitions.</div></div></div>
  {project?<ModelWorkspaceClient projects={projects} projectId={project.id} state={state}/>:<div className="note">No accessible project exists yet.</div>}
  <div className="note"><b>Open-data boundary.</b> Native authoring formats may enter through authorised adapters, but controlled model identity, validation, coordination evidence and issue authority remain vendor-neutral and hash-bound.</div>
 </>;
}
