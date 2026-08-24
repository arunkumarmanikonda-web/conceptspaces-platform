import {requireWorkspaceUser} from "@/lib/auth";
import TaxRuleGovernanceClient from "@/components/TaxRuleGovernanceClient";

export const dynamic="force-dynamic";

export default async function TaxRulesPage(){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.rpc("list_tax_rule_workspace");
 if(error)throw new Error(error.message);
 const workspace=(data||{rules:[],determinations:[]}) as {rules:any[];determinations:any[]};
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / Tax Governance</div><h1>Tax Rule Packs</h1><div className="subtle">Effective-dated statutory logic with source evidence, immutable published versions and maker-checker publication.</div></div></div>
  <TaxRuleGovernanceClient workspace={workspace}/>
 </>;
}
