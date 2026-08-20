import {requireWorkspaceUser} from "@/lib/auth";
import EngineeringRegistryClient from "@/components/EngineeringRegistryClient";
import {emptyEngineeringState,type EngineeringWorkspaceState} from "@/components/engineering-validation-types";

export const dynamic="force-dynamic";

export default async function EngineeringEnginesAdmin(){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.rpc("list_engineering_validation_workspace");
 if(error)throw new Error(error.message);
 const state=(data||emptyEngineeringState) as EngineeringWorkspaceState;
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / Verification & Validation</div><h1>Engineering Engine Registry</h1><div className="subtle">Versioned solver identity, benchmark evidence, certification state, supported standards and maximum permitted criticality. No engine is enabled by registration alone.</div></div></div>
  <EngineeringRegistryClient state={state}/>
 </>;
}
