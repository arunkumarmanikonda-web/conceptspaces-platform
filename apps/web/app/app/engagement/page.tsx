import {requireWorkspaceUser} from "@/lib/auth";
import ContractLegalClient from "@/components/ContractLegalClient";
import ActivationStageClient from "@/components/ActivationStageClient";
import {emptyActivationState,emptyContractLegalState,emptyProjectTeamState,emptyScopeCommercialState,type ActivationState,type ContractLegalState,type ProjectTeamState,type ScopeCommercialState} from "@/components/commercial-runtime-types";

export const dynamic="force-dynamic";

export default async function EngagementPage(){
 const {supabase,memberships}=await requireWorkspaceUser();
 const organisationId=memberships[0]?.organisation_id;
 if(!organisationId)throw new Error("Organisation membership required.");
 const [scopeResult,legalResult,activationResult,teamResult]=await Promise.all([
  supabase.rpc("list_scope_commercial_workspace",{target_organisation_id:organisationId}),
  supabase.rpc("list_contract_legal_workspace",{target_organisation_id:organisationId}),
  supabase.rpc("list_project_activation_workspace",{target_organisation_id:organisationId}),
  supabase.rpc("list_project_team_candidates",{target_organisation_id:organisationId})
 ]);
 const error=scopeResult.error||legalResult.error||activationResult.error||teamResult.error;
 if(error)throw new Error(error.message);
 const commercial=(scopeResult.data||emptyScopeCommercialState) as ScopeCommercialState;
 const legal=(legalResult.data||emptyContractLegalState) as ContractLegalState;
 const activation=(activationResult.data||emptyActivationState) as ActivationState;
 const team=(teamResult.data||emptyProjectTeamState) as ProjectTeamState;
 const negotiationEvents=commercial.negotiation_events||[];
 const activationRows=activation.activations||[];
 const accepted=commercial.proposals.filter(p=>p.status==="accepted"&&p.scope_hash&&p.accepted_scope_hash===p.scope_hash).length;
 const executed=legal.contracts.filter(c=>Boolean(c.executed_at)&&Boolean(c.execution_hash)).length;
 return <>
  <div className="topbar"><div><div className="demo">Commercial / Legal / Activation</div><h1>Engagement & Project Activation</h1><div className="subtle">One auditable thread from scope and proposal negotiation through clause-controlled contract execution, signature evidence, activation prerequisites and governed delivery-stage baselines.</div></div></div>
  <div className="kpis">{[["Negotiation Events",String(negotiationEvents.length).padStart(2,"0")],["Accepted Proposals",String(accepted).padStart(2,"0")],["Executed Contracts",String(executed).padStart(2,"0")],["Activation Records",String(activationRows.length).padStart(2,"0")],["Active Projects",String(activation.projects.filter(p=>p.lifecycle_state==="active").length).padStart(2,"0")]].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Live workspace state</div></div>)}</div>
  <section className="panel" style={{marginTop:16}}><h3>Negotiation Continuity</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Version</th><th>Party</th><th>Event</th><th>Amount</th><th>Proposal</th><th>Recorded</th></tr></thead><tbody>{negotiationEvents.map(e=><tr key={e.id}><td>v{e.version}</td><td>{e.party}</td><td><span className="badge">{e.event_type.replaceAll("_"," ")}</span></td><td>{e.amount===null||e.amount===undefined?"—":new Intl.NumberFormat("en-IN",{style:"currency",currency:e.currency||"INR",maximumFractionDigits:0}).format(Number(e.amount))}</td><td>{e.proposal_id.slice(0,8)}</td><td>{new Date(e.created_at).toLocaleString("en-IN")}</td></tr>)}{negotiationEvents.length===0&&<tr><td colSpan={6} className="subtle">No proposal negotiation history exists yet. Nothing is fabricated for display.</td></tr>}</tbody></table></div></section>
  <div className="note" style={{marginTop:16}}><b>Commercial integrity.</b> Accepted proposal scope is hash-bound into the contract. Executed contract content is immutable. Project activation then fails closed until the configured payment, KYC, team, client-user, site and classification prerequisites are evidenced.</div>
  <div style={{marginTop:20}}><ContractLegalClient organisationId={organisationId} state={legal} proposals={commercial.proposals} projects={commercial.projects}/></div>
  <div style={{marginTop:24}}><ActivationStageClient state={activation} team={team}/></div>
 </>;
}
