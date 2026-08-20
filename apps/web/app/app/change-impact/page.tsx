import ConfigurationControlClient from "@/components/ConfigurationControlClient";
import {emptyConfigurationWorkspace,type ConfigurationProject,type ConfigurationWorkspace} from "@/components/configuration-runtime-types";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function ChangeImpactPage(){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ConfigurationProject[];
 const batches=await Promise.all(projects.map(async p=>{const {data,error}=await supabase.rpc("list_project_configuration_workspace",{target_project_id:p.id});if(error)throw new Error(error.message);return (data||emptyConfigurationWorkspace) as ConfigurationWorkspace;}));
 const state:ConfigurationWorkspace={branches:batches.flatMap(x=>x.branches||[]),commits:batches.flatMap(x=>x.commits||[]),changes:batches.flatMap(x=>x.changes||[]),impacts:batches.flatMap(x=>x.impacts||[]),approvals:batches.flatMap(x=>x.approvals||[])};
 return <><div className="topbar"><div><div className="demo">Change Impact Engine™ / Governed Configuration</div><h1>Blast Radius & Reversal Cost</h1><div className="subtle">Register a proposed project change, freeze its exact configuration baseline, trace downstream regulatory/design/engineering/commercial/programme impact, obtain exact-hash maker-checker approval and commit only while that analysis remains current.</div></div></div><ConfigurationControlClient projects={projects} state={state} section="changes"/></>;
}
