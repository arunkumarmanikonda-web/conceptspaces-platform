import { revalidatePath } from "next/cache";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

type Lead={id:string;contact_id?:string|null;source:string;status:string;project_typology?:string|null;project_location?:string|null;estimated_project_value?:number|null;currency:string;next_action_at?:string|null;created_at:string};
type Contact={id:string;full_name:string;company_name?:string|null;email?:string|null;phone?:string|null};
type Opportunity={id:string;lead_id?:string|null;project_name:string;stage:string;probability:number;expected_fee?:number|null;currency:string;decision_due_at?:string|null};

async function createLead(formData:FormData){
  "use server";
  const {supabase,memberships}=await requireWorkspaceUser();
  const org=memberships[0]?.organisation_id;
  if(!org) throw new Error("Organisation membership required.");
  const payload={
    organisation_id:org,
    source:String(formData.get("source")||"direct"),
    project_typology:String(formData.get("project_typology")||""),
    project_location:String(formData.get("project_location")||""),
    estimated_project_value:String(formData.get("estimated_project_value")||""),
    currency:"INR",
    next_action_at:String(formData.get("next_action_at")||""),
    contact:{
      full_name:String(formData.get("full_name")||""),company_name:String(formData.get("company_name")||""),
      email:String(formData.get("email")||""),phone:String(formData.get("phone")||""),
      consent_email:formData.get("consent_email")==="on",consent_whatsapp:formData.get("consent_whatsapp")==="on",consent_sms:formData.get("consent_sms")==="on"
    }
  };
  const {error}=await supabase.rpc("create_crm_lead",{input_payload:payload});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

async function advanceLead(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const leadId=String(formData.get("lead_id")||"");
  const payload={
    project_name:String(formData.get("project_name")||""),stage:"discovery",probability:String(formData.get("probability")||"25"),
    expected_fee:String(formData.get("expected_fee")||""),currency:"INR",decision_due_at:String(formData.get("decision_due_at")||"")
  };
  const {error}=await supabase.rpc("advance_lead_to_opportunity",{target_lead_id:leadId,input_payload:payload});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

function money(v?:number|null,c="INR"){
  if(v===null||v===undefined) return "—";
  return new Intl.NumberFormat("en-IN",{style:"currency",currency:c,maximumFractionDigits:0}).format(Number(v));
}

export default async function CRMPage(){
  const {supabase,memberships}=await requireWorkspaceUser();
  const org=memberships[0]?.organisation_id;
  const [{data:leadData,error:leadError},{data:contactData,error:contactError},{data:opportunityData,error:oppError}]=await Promise.all([
    supabase.from("leads").select("id,contact_id,source,status,project_typology,project_location,estimated_project_value,currency,next_action_at,created_at").eq("organisation_id",org).order("created_at",{ascending:false}),
    supabase.from("contacts").select("id,full_name,company_name,email,phone").eq("organisation_id",org),
    supabase.from("opportunities").select("id,lead_id,project_name,stage,probability,expected_fee,currency,decision_due_at").eq("organisation_id",org).order("created_at",{ascending:false})
  ]);
  if(leadError||contactError||oppError) throw new Error(leadError?.message||contactError?.message||oppError?.message||"Unable to load CRM.");
  const leads=(leadData||[]) as Lead[]; const contacts=(contactData||[]) as Contact[]; const opportunities=(opportunityData||[]) as Opportunity[];
  const contactMap=new Map(contacts.map(c=>[c.id,c]));
  const openLeads=leads.filter(l=>!["won","lost"].includes(l.status)).length;
  const qualified=leads.filter(l=>l.status==="qualified").length;
  const proposalPipeline=opportunities.filter(o=>!["won","lost"].includes(o.stage)).reduce((s,o)=>s+Number(o.expected_fee||0),0);
  const weighted=opportunities.filter(o=>!["won","lost"].includes(o.stage)).reduce((s,o)=>s+Number(o.expected_fee||0)*Number(o.probability||0)/100,0);
  const nextActions=leads.filter(l=>Boolean(l.next_action_at)&&!["won","lost"].includes(l.status)).length;

  return <>
    <div className="topbar"><div><div className="demo">Live CRM / Governed Data</div><h1>CRM & Growth</h1><div className="subtle">Contacts, leads, opportunities, next actions and conversion intelligence</div></div></div>
    <div className="kpis">{[["Open Leads",String(openLeads)],["Qualified",String(qualified)],["Proposal Pipeline",money(proposalPipeline)],["Weighted Pipeline",money(weighted)],["Next Actions",String(nextActions)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>10?20:30}}>{v}</div><div className="subtle">Live workspace state</div></div>)}</div>

    <div className="panel-grid">
      <section className="panel"><h3>New Lead</h3><form action={createLead}><div className="field-grid">
        <div className="field"><label>Contact Name</label><input name="full_name" required/></div><div className="field"><label>Company</label><input name="company_name"/></div>
        <div className="field"><label>Email</label><input type="email" name="email"/></div><div className="field"><label>Phone</label><input name="phone"/></div>
        <div className="field"><label>Project Typology</label><input name="project_typology" placeholder="Hotel / Mixed Use / Residence"/></div><div className="field"><label>Project Location</label><input name="project_location"/></div>
        <div className="field"><label>Estimated Project Value</label><input type="number" min="0" step="0.01" name="estimated_project_value"/></div><div className="field"><label>Source</label><input name="source" defaultValue="direct"/></div>
        <div className="field"><label>Next Action</label><input type="datetime-local" name="next_action_at"/></div>
      </div><div style={{display:"flex",gap:16,marginTop:14,fontSize:12}}><label><input type="checkbox" name="consent_email"/> Email consent</label><label><input type="checkbox" name="consent_whatsapp"/> WhatsApp consent</label><label><input type="checkbox" name="consent_sms"/> SMS consent</label></div><button className="btn" style={{marginTop:16}}>Create Lead</button></form></section>
      <section className="panel"><h3>Consent Boundary</h3><p className="subtle">Communication consent is explicit per channel and defaults to false. A CRM record does not imply marketing permission.</p><div className="note"><b>Audit bound.</b> Lead and opportunity creation is written to the hash-linked audit ledger.</div></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Lead Queue</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Contact</th><th>Project</th><th>Status</th><th>Value</th><th>Next Action</th><th>Advance</th></tr></thead><tbody>{leads.map(l=>{const c=l.contact_id?contactMap.get(l.contact_id):undefined;return <tr key={l.id}><td><b>{c?.full_name||"Unnamed"}</b><div className="subtle">{c?.company_name||c?.email||l.source}</div></td><td>{l.project_typology||"—"}<div className="subtle">{l.project_location||""}</div></td><td><span className="badge">{l.status}</span></td><td>{money(l.estimated_project_value,l.currency)}</td><td>{l.next_action_at?new Date(l.next_action_at).toLocaleString("en-IN"):"—"}</td><td>{!["won","lost"].includes(l.status)&&<form action={advanceLead} style={{display:"grid",gap:6,minWidth:180}}><input type="hidden" name="lead_id" value={l.id}/><input name="project_name" defaultValue={l.project_typology||"Project Opportunity"}/><input type="number" name="probability" min="0" max="100" defaultValue="25"/><input type="number" name="expected_fee" min="0" step="0.01" placeholder="Expected fee"/><button className="btn ghost" style={{padding:8}}>Create Opportunity</button></form>}</td></tr>})}{leads.length===0&&<tr><td colSpan={6} className="subtle">No leads yet. Create the first governed CRM record above.</td></tr>}</tbody></table></div></section>

    <section className="panel" style={{marginTop:16}}><h3>Opportunity Pipeline</h3><table className="table"><thead><tr><th>Opportunity</th><th>Stage</th><th>Probability</th><th>Expected Fee</th><th>Decision Due</th></tr></thead><tbody>{opportunities.map(o=><tr key={o.id}><td>{o.project_name}</td><td><span className="badge">{o.stage}</span></td><td>{o.probability}%</td><td>{money(o.expected_fee,o.currency)}</td><td>{o.decision_due_at?new Date(o.decision_due_at).toLocaleDateString("en-IN"):"—"}</td></tr>)}{opportunities.length===0&&<tr><td colSpan={5} className="subtle">No opportunities yet.</td></tr>}</tbody></table></section>
  </>;
}
