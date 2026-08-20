import {requireWorkspaceUser} from "@/lib/auth";
import EngineeringValidationClient from "@/components/EngineeringValidationClient";
import {emptyEngineeringState,type EngineeringProject,type EngineeringWorkspaceState} from "@/components/engineering-validation-types";

export const dynamic="force-dynamic";

export default async function MepPage(){
 const {supabase}=await requireWorkspaceUser();
 const [{data:projectData,error:projectError},{data:validationData,error:validationError}]=await Promise.all([
  supabase.rpc("list_accessible_projects"),
  supabase.rpc("list_engineering_validation_workspace")
 ]);
 if(projectError)throw new Error(projectError.message);
 if(validationError)throw new Error(validationError.message);
 const projects=(projectData||[]) as EngineeringProject[];
 const state=(validationData||emptyEngineeringState) as EngineeringWorkspaceState;
 return <>
  <div className="topbar"><div><div className="demo">MEPF + ELV + VT / Engineering Verification Runtime</div><h1>Building Systems Engineering</h1><div className="subtle">Project criteria, certified engine provenance, immutable calculation evidence and exact-hash professional review. Unsupported or insufficient evidence fails closed.</div></div></div>
  <EngineeringValidationClient projects={projects} state={state}/>
 </>;
}
