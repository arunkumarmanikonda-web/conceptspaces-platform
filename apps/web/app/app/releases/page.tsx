import {requireWorkspaceUser} from "@/lib/auth";
import ReleaseAssuranceClient from "@/components/ReleaseAssuranceClient";
import {emptyReleaseWorkspace,type ReleaseProject,type ReleaseWorkspaceState} from "@/components/release-assurance-types";

export const dynamic="force-dynamic";

export default async function ReleasesPage(){
  const {supabase}=await requireWorkspaceUser();
  const [{data:projectData,error:projectError},{data:releaseData,error:releaseError}]=await Promise.all([
    supabase.rpc("list_accessible_projects"),
    supabase.rpc("list_release_assurance_workspace")
  ]);
  if(projectError)throw new Error(projectError.message);
  if(releaseError)throw new Error(releaseError.message);
  const projects=(projectData||[]) as ReleaseProject[];
  const state=(releaseData||emptyReleaseWorkspace) as ReleaseWorkspaceState;

  return <>
    <div className="topbar"><div><div className="demo">Proof Before Publish / Release Assurance Runtime</div><h1>Release Assurance</h1><div className="subtle">Exact package identity, current evidence, professional authority, zero critical escape and a fresh final evaluation before issue.</div></div></div>
    <ReleaseAssuranceClient projects={projects} state={state}/>
  </>;
}
