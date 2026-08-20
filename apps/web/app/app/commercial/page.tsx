import { revalidatePath } from "next/cache";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

type Opportunity={id:string;project_name:string;stage:string;currency:string;expected_fee?:number|null};
type Proposal={id:string;opportunity_id:string;version:number;status:string;currency:string;subtotal:number;tax:number;total:number;valid_until?:string|null;created_by?:string|null;approved_by?:string|null;approved_at?:string|null;client_counter_offer?:number|null};
type Contract={id:string;proposal_id?:string|null;project_id?:string|null;status:string;version:number;effective_at?:string|null;expires_at?:string|null};
type Invoice={id:string;contract_id?:string|null;project_id?:string|null;invoice_number:string;status:string;currency:string;issue_date:string;due_date:string;subtotal:number;tax:number;total:number;amount_paid:number;tds_receivable:number;created_by?:string|null};

function money(v?:number|null,c="INR"){
  if(v===null||v===undefined) return "—";
  return new Intl.NumberFormat("en-IN",{style:"currency",currency:c,maximumFractionDigits:0}).format(Number(v));
}

async function createProposal(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const opportunityId=String(formData.get("opportunity_id")||"");
  const payload={
    currency:"INR",valid_until:String(formData.get("valid_until")||""),tax:String(formData.get("tax")||"0"),
    commercial_notes:[],lines:[{title:String(formData.get("title")||"Professional Services"),scope_code:String(formData.get("scope_code")||"ARCH"),pricing_model:String(formData.get("pricing_model")||"fixed"),quantity:String(formData.get("quantity")||"1"),rate:String(formData.get("rate")||"0"),optional:false,sort_order:1}]
  };
  const {error}=await supabase.rpc("create_commercial_proposal",{target_opportunity_id:opportunityId,input_payload:payload});
  if(error) throw new Error(error.message);
  revalidatePath("/app/commercial");
}
async function submitProposal(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("submit_proposal_for_review",{target_proposal_id:String(formData.get("proposal_id")||"")});if(error) throw new Error(error.message);revalidatePath("/app/commercial");}
async function approveProposal(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("approve_and_send_proposal",{target_proposal_id:String(formData.get("proposal_id")||""),review_note:String(formData.get("review_note")||"")});if(error) throw new Error(error.message);revalidatePath("/app/commercial");}
async function clientDecision(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("record_proposal_client_decision",{target_proposal_id:String(formData.get("proposal_id")||""),decision:String(formData.get("decision")||""),evidence_reference:String(formData.get("evidence_reference")||""),client_counter_offer:Number(formData.get("client_counter_offer")||0)||null});if(error) throw new Error(error.message);revalidatePath("/app/commercial");}
async function createContract(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("create_contract_from_proposal",{target_proposal_id:String(formData.get("proposal_id")||""),target_project_id:null,contract_snapshot:{source:"accepted_proposal",note:String(formData.get("note")||"")}});if(error) throw new Error(error.message);revalidatePath("/app/commercial");}
async function createInvoice(formData:FormData){
  "use server"; const {supabase,memberships}=await requireWorkspaceUser(); const org=memberships[0]?.organisation_id;if(!org) throw new Error("Organisation required.");
  const payload={organisation_id:org,contract_id:String(formData.get("contract_id")||""),invoice_number:String(formData.get("invoice_number")||""),currency:"INR",issue_date:String(formData.get("issue_date")||""),due_date:String(formData.get("due_date")||""),metadata:{source:"commercial_os"},lines:[{description:String(formData.get("description")||"Professional services"),quantity:String(formData.get("quantity")||"1"),rate:String(formData.get("rate")||"0"),gst_rate:String(formData.get("gst_rate")||"18"),sort_order:1}]};
  const {error}=await supabase.rpc("create_invoice_draft",{input_payload:payload});if(error) throw new Error(error.message);revalidatePath("/app/commercial");
}
async function issueInvoice(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("issue_invoice",{target_invoice_id:String(formData.get("invoice_id")||"")});if(error) throw new Error(error.message);revalidatePath("/app/commercial");}

export default async function CommercialPage(){
  const {supabase,memberships,user}=await requireWorkspaceUser(); const org=memberships[0]?.organisation_id;
  const [{data:opps,error:e1},{data:props,error:e2},{data:contracts,error:e3},{data:invoices,error:e4}]=await Promise.all([
    supabase.from("opportunities").select("id,project_name,stage,currency,expected_fee").eq("organisation_id",org).order("created_at",{ascending:false}),
    supabase.from("proposals").select("id,opportunity_id,version,status,currency,subtotal,tax,total,valid_until,created_by,approved_by,approved_at,client_counter_offer").eq("organisation_id",org).order("created_at",{ascending:false}),
    supabase.from("contracts").select("id,proposal_id,project_id,status,version,effective_at,expires_at").eq("organisation_id",org).order("created_at",{ascending:false}),
    supabase.from("invoices").select("id,contract_id,project_id,invoice_number,status,currency,issue_date,due_date,subtotal,tax,total,amount_paid,tds_receivable,created_by").eq("organisation_id",org).order("created_at",{ascending:false})
  ]);
  if(e1||e2||e3||e4) throw new Error(e1?.message||e2?.message||e3?.message||e4?.message||"Unable to load commercial data.");
  const opportunities=(opps||[]) as Opportunity[]; const proposals=(props||[]) as Proposal[]; const contractRows=(contracts||[]) as Contract[]; const invoiceRows=(invoices||[]) as Invoice[];
  const oppMap=new Map(opportunities.map(o=>[o.id,o]));
  const proposalValue=proposals.filter(p=>!["rejected","expired"].includes(p.status)).reduce((s,p)=>s+Number(p.total||0),0);
  const contracted=contractRows.filter(c=>["active","signature_pending","draft","negotiation"].includes(c.status)).map(c=>proposals.find(p=>p.id===c.proposal_id)).reduce((s,p)=>s+Number(p?.total||0),0);
  const receivables=invoiceRows.filter(i=>!["paid","void"].includes(i.status)).reduce((s,i)=>s+Math.max(0,Number(i.total||0)-Number(i.amount_paid||0)),0);
  const tds=invoiceRows.reduce((s,i)=>s+Number(i.tds_receivable||0),0);
  const overdue=invoiceRows.filter(i=>!["paid","void"].includes(i.status)&&new Date(i.due_date)<new Date()).reduce((s,i)=>s+Math.max(0,Number(i.total||0)-Number(i.amount_paid||0)),0);

  return <>
    <div className="topbar"><div><div className="demo">Live Commercial OS / Maker-Checker</div><h1>Commercial OS</h1><div className="subtle">Proposal → independent review → client evidence → contract → invoice → verified collection</div></div></div>
    <div className="kpis">{[["Proposal Value",money(proposalValue)],["Contracted Fees",money(contracted)],["Receivables",money(receivables)],["TDS Receivable",money(tds)],["Overdue",money(overdue)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>10?20:30}}>{v}</div><div className="subtle">Live workspace state</div></div>)}</div>

    <div className="panel-grid">
      <section className="panel"><h3>Create Proposal Draft</h3><form action={createProposal}><div className="field-grid"><div className="field"><label>Opportunity</label><select name="opportunity_id" required><option value="">Select</option>{opportunities.filter(o=>!["won","lost"].includes(o.stage)).map(o=><option key={o.id} value={o.id}>{o.project_name}</option>)}</select></div><div className="field"><label>Valid Until</label><input type="date" name="valid_until"/></div><div className="field"><label>Line Title</label><input name="title" defaultValue="Professional Services" required/></div><div className="field"><label>Scope Code</label><input name="scope_code" defaultValue="ARCH" required/></div><div className="field"><label>Pricing Model</label><select name="pricing_model" defaultValue="fixed"><option value="fixed">Fixed</option><option value="percent">Percent</option><option value="sqft">Per sq ft</option><option value="per_key">Per key</option><option value="retainer">Retainer</option><option value="milestone">Milestone</option><option value="subscription">Subscription</option></select></div><div className="field"><label>Quantity</label><input type="number" min="0" step="0.01" name="quantity" defaultValue="1"/></div><div className="field"><label>Rate</label><input type="number" min="0" step="0.01" name="rate" required/></div><div className="field"><label>Tax Amount</label><input type="number" min="0" step="0.01" name="tax" defaultValue="0"/></div></div><button className="btn" style={{marginTop:16}}>Create Draft</button></form></section>
      <section className="panel"><h3>Control Boundary</h3><p className="subtle">Proposal totals are calculated in PostgreSQL from line quantities and rates. A proposal maker cannot approve their own controlled proposal. Client acceptance requires an explicit evidence reference.</p><div className="note"><b>Payment integrity.</b> This screen does not contain any action that can manually mark an invoice paid. Provider-confirmed payment is handled separately.</div></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Proposals</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Opportunity</th><th>Version</th><th>Status</th><th>Fee</th><th>Validity</th><th>Controlled Actions</th></tr></thead><tbody>{proposals.map(p=><tr key={p.id}><td>{oppMap.get(p.opportunity_id)?.project_name||p.opportunity_id}</td><td>v{p.version}</td><td><span className="badge">{p.status}</span></td><td>{money(p.total,p.currency)}</td><td>{p.valid_until?new Date(p.valid_until).toLocaleDateString("en-IN"):"—"}</td><td><div style={{display:"grid",gap:6,minWidth:220}}>{p.status==="draft"&&<form action={submitProposal}><input type="hidden" name="proposal_id" value={p.id}/><button className="btn ghost" style={{padding:8}}>Submit for Review</button></form>}{p.status==="internal_review"&&<form action={approveProposal}><input type="hidden" name="proposal_id" value={p.id}/><input name="review_note" placeholder="Checker note"/><button className="btn ghost" style={{padding:8}}>Approve & Send</button>{p.created_by===user.id&&<div className="subtle">Independent checker required.</div>}</form>}{["sent","countered"].includes(p.status)&&<form action={clientDecision}><input type="hidden" name="proposal_id" value={p.id}/><select name="decision" defaultValue="accepted"><option value="accepted">Accepted</option><option value="countered">Countered</option><option value="rejected">Rejected</option></select><input name="evidence_reference" placeholder="Client email/eSign/evidence ref" required/><input type="number" min="0" step="0.01" name="client_counter_offer" placeholder="Counter offer if applicable"/><button className="btn ghost" style={{padding:8}}>Record Client Decision</button></form>}{p.status==="accepted"&&!contractRows.some(c=>c.proposal_id===p.id)&&<form action={createContract}><input type="hidden" name="proposal_id" value={p.id}/><input name="note" placeholder="Contract preparation note"/><button className="btn" style={{padding:8}}>Create Contract Draft</button></form>}</div></td></tr>)}{proposals.length===0&&<tr><td colSpan={6} className="subtle">No proposals yet.</td></tr>}</tbody></table></div></section>

    <div className="panel-grid">
      <section className="panel"><h3>Contracts</h3><table className="table"><thead><tr><th>Contract</th><th>Status</th><th>Proposal</th></tr></thead><tbody>{contractRows.map(c=><tr key={c.id}><td>{c.id.slice(0,8).toUpperCase()}</td><td><span className="badge">{c.status}</span></td><td>{c.proposal_id?`Proposal ${c.proposal_id.slice(0,8)}`:"—"}</td></tr>)}{contractRows.length===0&&<tr><td colSpan={3} className="subtle">No contracts yet.</td></tr>}</tbody></table></section>
      <section className="panel"><h3>Create Invoice Draft</h3><form action={createInvoice}><div className="field"><label>Contract</label><select name="contract_id"><option value="">Unlinked</option>{contractRows.map(c=><option key={c.id} value={c.id}>{c.id.slice(0,8)} · {c.status}</option>)}</select></div><div className="field"><label>Invoice Number</label><input name="invoice_number" required placeholder="CS/26-27/001"/></div><div className="field-grid"><div className="field"><label>Issue Date</label><input type="date" name="issue_date"/></div><div className="field"><label>Due Date</label><input type="date" name="due_date"/></div><div className="field"><label>Description</label><input name="description" defaultValue="Professional services"/></div><div className="field"><label>Quantity</label><input type="number" min="0" step="0.01" name="quantity" defaultValue="1"/></div><div className="field"><label>Rate</label><input type="number" min="0" step="0.01" name="rate" required/></div><div className="field"><label>GST %</label><input type="number" min="0" step="0.01" name="gst_rate" defaultValue="18"/></div></div><button className="btn" style={{marginTop:16}}>Create Invoice Draft</button></form></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Invoices & Collections</h3><table className="table"><thead><tr><th>Invoice</th><th>Amount</th><th>Paid</th><th>Status</th><th>Due</th><th>Action</th></tr></thead><tbody>{invoiceRows.map(i=><tr key={i.id}><td>{i.invoice_number}</td><td>{money(i.total,i.currency)}</td><td>{money(i.amount_paid,i.currency)}</td><td><span className="badge">{i.status}</span></td><td>{new Date(i.due_date).toLocaleDateString("en-IN")}</td><td>{i.status==="draft"&&<form action={issueInvoice}><input type="hidden" name="invoice_id" value={i.id}/><button className="btn ghost" style={{padding:8}}>Issue</button></form>}</td></tr>)}{invoiceRows.length===0&&<tr><td colSpan={6} className="subtle">No invoices yet.</td></tr>}</tbody></table></section>
  </>;
}
