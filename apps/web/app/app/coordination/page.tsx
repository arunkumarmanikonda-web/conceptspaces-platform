import {requireWorkspaceUser} from "@/lib/auth";
import CoordinationMatrixClient from "@/components/CoordinationMatrixClient";
import {emptyCoordinationWorkspace,type CoordinationProject,type CoordinationWorkspaceState} from "@/components/coordination-runtime-types";

export const dynamic="force-dynamic";

export default async function CoordinationPage(){
  const {supabase}=await requireWorkspaceUser();
  const [{data:projectData,error:projectError},{data:coordinationData,error:coordinationError}]=await Promise.all([
    supabase.rpc("list_accessible_projects"),
    supabase.rpc("list_coordination_matrix_workspace")
  ]);
  if(projectError)throw new Error(projectError.message);
  if(coordinationError)throw new Error(coordinationError.message);
  const projects=(projectData||[]) as CoordinationProject[];
  const state=(coordinationData||emptyCoordinationWorkspace) as CoordinationWorkspaceState;

  return <>
    <div className="topbar"><div><div className="demo">Cross-Discipline / CDE / BCF / Release-Coupled</div><h1>Coordination Matrix</h1><div className="subtle">Hash-bound source and target resources, issue accountability, evidence-backed resolution and governed deviation acceptance.</div></div></div>
    <CoordinationMatrixClient projects={projects} state={state}/>
  </>;
}
