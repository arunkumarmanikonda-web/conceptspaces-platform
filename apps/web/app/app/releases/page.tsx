import {requireWorkspaceUser} from "@/lib/auth";
import ReleaseAssuranceClient from "@/components/ReleaseAssuranceClient";
import ReleaseQAAssuranceClient from "@/components/ReleaseQAAssuranceClient";
import {emptyReleaseWorkspace,type ReleaseProject,type ReleaseWorkspaceState} from "@/components/release-assurance-types";

export const dynamic="force-dynamic";
type ExtendedCase={id:string;package_reference?:string|null;package_type:string;content_hash?:string|null;state:string;unresolved_critical_defects:number;evidence_bundle_hash?:string|null;evidence_manifest?:unknown[];last_evaluated_at?:string|null};
export default async function ReleasesPage(){
 const {supabase}=await requireWorkspaceUser();const [{data:projectData,error:projectError},{data:releaseData,error:releaseError}]=await Promise.all([supabase.rpc("list_accessible_projects"),supabase.rpc("list_release_assurance_workspace")]);if(projectError)throw new Error(projectError.message);if(releaseError)throw new Error(releaseError.message);const projects=(projectData||[]) as ReleaseProject[];const state=(releaseData||emptyReleaseWorkspace) as ReleaseWorkspaceState&{safety_cases:ExtendedCase[]};
 return <><div className="topbar"><div><div className="demo">Proof Before Publish / Release Assurance Runtime</div><h1>Release Assurance</h1><div className="subtle">Exact package identity, current evidence, mandatory QA/waiver snapshot, professional authority, zero critical escape and a fresh final evaluation before issue.</div></div></div><ReleaseQAAssuranceClient cases={state.safety_cases}/><ReleaseAssuranceClient projects={projects} state={state}/></>;
}