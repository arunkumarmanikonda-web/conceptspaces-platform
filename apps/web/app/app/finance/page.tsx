import {requireWorkspaceUser} from "@/lib/auth";
import FinanceWorkspaceClient from "@/components/FinanceWorkspaceClient";
import {emptyFinanceWorkspace,type FinanceWorkspaceState} from "@/components/finance-runtime-types";

export const dynamic="force-dynamic";

export default async function FinancePage(){
 const {supabase,memberships}=await requireWorkspaceUser();
 const organisationId=memberships[0]?.organisation_id;
 if(!organisationId)throw new Error("Organisation membership required.");
 const {data,error}=await supabase.rpc("list_finance_workspace",{target_organisation_id:organisationId});
 if(error)throw new Error(error.message);
 const state=(data||emptyFinanceWorkspace) as FinanceWorkspaceState;
 return <>
  <div className="topbar"><div><div className="demo">Finance ERP / Governed Ledger</div><h1>Finance</h1><div className="subtle">Project-aware double-entry accounting, fiscal-period control, contract-to-cash invoicing, payments and effective-dated tax provenance.</div></div></div>
  <FinanceWorkspaceClient organisationId={organisationId} state={state}/>
  <div className="note" style={{marginTop:16}}><b>Accounting control.</b> Draft journals must balance, a different authorised user posts them, closed periods block posting, and corrections use linked reversals rather than rewriting posted history.</div>
 </>;
}
