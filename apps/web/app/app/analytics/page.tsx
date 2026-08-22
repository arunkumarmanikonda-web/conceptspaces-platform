import {requireWorkspaceUser} from "@/lib/auth";
import AnalyticsWorkspaceClient from "@/components/AnalyticsWorkspaceClient";
import {emptyAnalyticsWorkspace,type AnalyticsWorkspaceState} from "@/components/analytics-runtime-types";

export const dynamic="force-dynamic";

export default async function AnalyticsPage(){
 const {supabase,memberships}=await requireWorkspaceUser();
 const organisationId=memberships[0]?.organisation_id;
 if(!organisationId)throw new Error("Organisation membership required.");
 const {data,error}=await supabase.rpc("list_analytics_workspace",{target_organisation_id:organisationId});
 if(error)throw new Error(error.message);
 const state=(data||emptyAnalyticsWorkspace) as AnalyticsWorkspaceState;
 return <>
  <div className="topbar"><div><div className="demo">BI / Evidence-Governed Intelligence</div><h1>Analytics & Early Warning</h1><div className="subtle">Decision metrics retain exact definition version, calculation reference, source, confidence, observation time and immutable evidence hash.</div></div></div>
  <AnalyticsWorkspaceClient organisationId={organisationId} state={state}/>
  <div className="note" style={{marginTop:16}}><b>No vanity metrics.</b> A KPI does not appear because it looks useful; it appears only after a governed definition exists and an evidence-bearing observation has been recorded.</div>
 </>;
}
