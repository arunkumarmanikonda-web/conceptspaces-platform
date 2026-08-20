import ConfigurationControlClient from "@/components/ConfigurationControlClient";
import {emptyConfigurationWorkspace,type ConfigurationProject,type ConfigurationWorkspace} from "@/components/configuration-runtime-types";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function BranchesPage(){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ConfigurationProject[];
 const batches=await Promise.all(projects.map(async p=>{const {data,error}=await supabase.rpc("list_project_configuration_workspace",{target_project_id:p.id});if(error)throw new Error(error.message);return (data||emptyConfigurationWorkspace) as ConfigurationWorkspace;}));
 const state:ConfigurationWorkspace={branches:batches.flatMap(x=>x.branches||[]),commits:batches.flatMap(x=>x.commits||[]),changes:batches.flatMap(x=>x.changes||[]),impacts:batches.flatMap(x=>x.impacts||[]),approvals:batches.flatMap(x=>x.approvals||[])};
 return <><div className="topbar"><div><div className="demo">Building Git / Governed Configuration</div><h1>Project Branches</h1><div className="subtle">Explore alternatives without corrupting approved project state. Every branch head, project change, commit and merge carries exact lineage and content-hash evidence.</div></div></div><ConfigurationControlClient projects={projects} state={state} section="branches"/></>;
}
