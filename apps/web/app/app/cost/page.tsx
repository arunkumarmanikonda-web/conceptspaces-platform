import {requireWorkspaceUser} from "@/lib/auth";
import CostWorkspaceClient from "@/components/CostWorkspaceClient";
import {emptyCostWorkspace,type CostWorkspaceState,type ProjectRow} from "@/components/lifecycle-runtime-types";

export const dynamic="force-dynamic";

export default async function CostPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
 if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ProjectRow[];
 const params=await searchParams;
 const project=projects.find(p=>p.id===params.project)||projects[0];
 let state=emptyCostWorkspace;
 if(project){const {data,error}=await supabase.rpc("list_cost_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyCostWorkspace) as CostWorkspaceState;}
 return <>
  <div className="topbar"><div><div className="demo">QTO / BOQ / Cost Intelligence / VE</div><h1>Cost & Quantity</h1><div className="subtle">Exact-model QTO, object/formula provenance, controlled BOQ rates, configuration-bound cost approval and governed value engineering.</div></div></div>
  {project?<CostWorkspaceClient projects={projects} projectId={project.id} state={state}/>:<div className="note">No accessible project exists yet.</div>}
  <div className="note"><b>Quantity integrity.</b> Design revisions create new quantity revisions rather than overwriting source evidence. Manual BOQ items remain explicitly classified, while approved cost plans fail closed if their Project Configuration changed.</div>
 </>;
}
