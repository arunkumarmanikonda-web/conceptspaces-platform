import {requireWorkspaceUser} from "@/lib/auth";
import ScopeCommercialClient from "@/components/ScopeCommercialClient";
import {emptyScopeCommercialState,type ScopeCommercialState} from "@/components/commercial-runtime-types";

export const dynamic="force-dynamic";

export default async function ScopePage(){
 const {supabase,memberships}=await requireWorkspaceUser();
 const organisationId=memberships[0]?.organisation_id;
 if(!organisationId)throw new Error("Organisation membership required.");
 const {data,error}=await supabase.rpc("list_scope_commercial_workspace",{target_organisation_id:organisationId});
 if(error)throw new Error(error.message);
 const state=(data||emptyScopeCommercialState) as ScopeCommercialState;
 return <>
  <div className="topbar"><div><div className="demo">Scope Architecture / Proposal / Negotiation</div><h1>Commercial Scope</h1><div className="subtle">Dependency-aware service configuration, controlled fee recalculation, immutable proposal revisions and complete negotiation history.</div></div></div>
  <ScopeCommercialClient organisationId={organisationId} state={state}/>
  <div className="note"><b>Commercial truth boundary.</b> Accepted proposal scope is immutable. A commercial change creates a new scope/proposal revision; dependency exceptions require independent approval and evidence.</div>
 </>;
}
