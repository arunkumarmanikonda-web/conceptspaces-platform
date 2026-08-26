import { revalidatePath } from "next/cache";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

type Lead={id:string;contact_id?:string|null;source:string;status:string;project_typology?:string|null;project_location?:string|null;estimated_project_value?:number|null;currency:string;next_action_at?:string|null;created_at:string;merged_into_lead_id?:string|null};
type Contact={id:string;full_name:string;company_name?:string|null;email?:string|null;phone?:string|null;consent_email?:boolean;consent_whatsapp?:boolean;consent_sms?:boolean};
type Opportunity={id:string;lead_id?:string|null;contact_id?:string|null;project_name:string;stage:string;probability:number;expected_fee?:number|null;currency:string;decision_due_at?:string|null;lost_reason_code?:string|null;remarketing_eligible?:boolean;remarketing_segment?:string|null};
type Activity={id:string;lead_id?:string|null;origin_lead_id?:string|null;opportunity_id?:string|null;activity_type:string;summary:string;occurred_at:string};
type Remarketing={id:string;opportunity_id:string;segment:string;reason_code:string;status:string;suppression_reason?:string|null;created_at:string};
type Workspace={leads:Lead[];contacts:Contact[];opportunities:Opportunity[];activities:Activity[];merges:any[];remarketing:Remarketing[]};

async function createLead(formData:FormData){
  "use server";
  const {supabase,memberships}=await requireWorkspaceUser();
  const org=memberships[0]?.organisation_id;
  if(!org) throw new Error("Organisation membership required.");
  const payload={organisation_id:org,source:String(formData.get("source")||"direct"),project_typology:String(formData.get("project_typology")||""),project_location:String(formData.get("project_location")||""),estimated_project_value:String(formData.get("estimated_project_value")||""),currency:"INR",next_action_at:String(formData.get("next_action_at")||""),contact:{full_name:String(formData.get("full_name")||""),company_name:String(formData.get("company_name")||""),email:String(formData.get("email")||""),phone:String(formData.get("phone")||""),consent_email:formData.get("consent_email")==="on",consent_whatsapp:formData.get("consent_whatsapp")==="on",consent_sms:formData.get("consent_sms")==="on"}};
  const {error}=await supabase.rpc("create_crm_lead",{input_payload:payload});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

async function advanceLead(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const {error}=await supabase.rpc("advance_lead_to_opportunity",{target_lead_id:String(formData.get("lead_id")||""),input_payload:{project_name:String(formData.get("project_name")||""),stage:"discovery",probability:String(formData.get("probability")||"25"),expected_fee:String(formData.get("expected_fee")||""),currency:"INR",decision_due_at:String(formData.get("decision_due_at")||"")}});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

async function mergeLead(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const survivor=String(formData.get("survivor_lead_id")||"");
  const duplicate=String(formData.get("duplicate_lead_id")||"");
  const reason=String(formData.get("reason")||"");
  if(!survivor||!duplicate||!reason.trim()) throw new Error("Survivor, duplicate and merge reason are required.");
  const {error}=await supabase.rpc("merge_crm_leads",{survivor_lead_id:survivor,duplicate_lead_id:duplicate,target_reason:reason});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

async function markLost(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const {error}=await supabase.rpc("mark_opportunity_lost",{target_opportunity_id:String(formData.get("opportunity_id")||""),target_reason_code:String(formData.get("reason_code")||""),target_reason_detail:String(formData.get("reason_detail")||""),target_remarketing_segment:String(formData.get("remarketing_segment")||"")||null});
  if(error) throw new Error(error.message);
  revalidatePath("/app/crm");
}

async function recordActivity(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const target=String(formData.get("target")||"");
  const [kind,id]=target.split(":");
  if(!id) throw new Error("A lead or opportunity is required.");
  const {error}=await supabase.rpc("record_crm_activity",{target_lead_id:kind==="lead"?id:null,target_opportunity_id:kind==="opportunity"?id:null,input_payload:{activity_type:String(formData.get("activity_type")||"note"),summary:String(formData.get("summary")||"")}});
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
  if(!org) throw new Error("Organisation membership required.");
  const {data,error}=await supabase.rpc("list_crm_workspace",{target_organisation_id:org});
  if(error) throw new Error(`Unable to load CRM: ${error.message}`);
  const state=(data||{}) as Workspace;
  const leads=state.leads||[],contacts=state.contacts||[],opportunities=state.opportunities||[],activities=state.activities||[],remarketing=state.remarketing||[];
  const contactMap=new Map(contacts.map(c=>[c.id,c]));
  const activeLeads=leads.filter(l=>l.status!=="merged");
  const openLeads=activeLeads.filter(l=>!["won","lost"].includes(l.status)).length;
  const qualified=activeLeads.filter(l=>l.status==="qualified").length;
  const proposalPipeline=opportunities.filter(o=>!["won","lost"].includes(o.stage)).reduce((s,o)=>s+Number(o.expected_fee||0),0);
  const weighted=opportunities.filter(o=>!["won","lost"].includes(o.stage)).reduce((s,o)=>s+Number(o.expected_fee||0)*Number(o.probability||0)/100,0);
  const eligibleRemarketing=remarketing.filter(r=>r.status==="eligible"||r.status==="active").length;

  return <>
    <div className="topbar"><div><div className="demo">Live CRM / Governed Data</div><h1>CRM & Growth</h1><div className="subtle">Contacts, leads, merge history, opportunities, consent-aware remarketing and auditable activity</div></div></div>
    <div className="kpis">{[["Open Leads",String(openLeads)],["Qualified",String(qualified)],["Proposal Pipeline",money(proposalPipeline)],["Weighted Pipeline",money(weighted)],["Remarketing Eligible",String(eligibleRemarketing)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>10?20:30}}>{v}</div><div className="subtle">Live workspace state</div></div>)}</div>

    <div className="panel-grid">
      <section className="panel"><h3>New Lead</h3><form action={createLead}><div className="field-grid">
        <div className="field"><label>Contact Name</label><input name="full_name" required/></div><div className="field"><label>Company</label><input name="company_name"/></div>
        <div className="field"><label>Email</label><input type="email" name="email"/></div><div className="field"><label>Phone</label><input name="phone"/></div>
        <div className="field"><label>Project Typology</label><input name="project_typology" placeholder="Hotel / Mixed Use / Residence"/></div><div className="field"><label>Project Location</label><input name="project_location"/></div>
        <div className="field"><label>Estimated Project Value</label><input type="number" min="0" step="0.01" name="estimated_project_value"/></div><div className="field"><label>Source</label><input name="source" defaultValue="direct"/></div>
        <div className="field"><label>Next Action</label><input type="datetime-local" name="next_action_at"/></div>
      </div><div style={{display:"flex",gap:16,marginTop:14,fontSize:12,flexWrap:"wrap"}}><label><input type="checkbox" name="consent_email"/> Email consent</label><label><input type="checkbox" name="consent_whatsapp"/> WhatsApp consent</label><label><input type="checkbox" name="consent_sms"/> SMS consent</label></div><button className="btn" style={{marginTop:16}}>Create Lead</button></form></section>
      <section className="panel"><h3>Duplicate Resolution</h3><p className="subtle">A duplicate is never deleted. Opportunities and current activity links move to the survivor while the duplicate record, original activity lead IDs and immutable merge snapshot remain retained.</p><form action={mergeLead}><div className="field"><label>Surviving Lead</label><select name="survivor_lead_id" required defaultValue=""><option value="" disabled>Select survivor</option>{activeLeads.map(l=>{const c=l.contact_id?contactMap.get(l.contact_id):undefined;return <option key={l.id} value={l.id}>{c?.full_name||l.project_typology||l.id.slice(0,8)} · {l.id.slice(0,8)}</option>})}</select></div><div className="field"><label>Duplicate Lead</label><select name="duplicate_lead_id" required defaultValue=""><option value="" disabled>Select duplicate</option>{activeLeads.map(l=>{const c=l.contact_id?contactMap.get(l.contact_id):undefined;return <option key={l.id} value={l.id}>{c?.full_name||l.project_typology||l.id.slice(0,8)} · {l.id.slice(0,8)}</option>})}</select></div><div className="field"><label>Merge Reason</label><textarea name="reason" rows={3} required/></div><button className="btn ghost" disabled={activeLeads.length<2}>Merge Without Deleting History</button></form></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Lead Queue</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Contact</th><th>Project</th><th>Status</th><th>Value</th><th>Next Action</th><th>Advance</th></tr></thead><tbody>{leads.map(l=>{const c=l.contact_id?contactMap.get(l.contact_id):undefined;return <tr key={l.id}><td><b>{c?.full_name||"Unnamed"}</b><div className="subtle">{c?.company_name||c?.email||l.source}</div></td><td>{l.project_typology||"—"}<div className="subtle">{l.project_location||""}</div></td><td><span className="badge">{l.status}</span>{l.merged_into_lead_id&&<div className="subtle">Merged into {l.merged_into_lead_id.slice(0,8)}</div>}</td><td>{money(l.estimated_project_value,l.currency)}</td><td>{l.next_action_at?new Date(l.next_action_at).toLocaleString("en-IN"):"—"}</td><td>{!["won","lost","merged"].includes(l.status)&&<form action={advanceLead} style={{display:"grid",gap:6,minWidth:180}}><input type="hidden" name="lead_id" value={l.id}/><input name="project_name" defaultValue={l.project_typology||"Project Opportunity"}/><input type="number" name="probability" min="0" max="100" defaultValue="25"/><input type="number" name="expected_fee" min="0" step="0.01" placeholder="Expected fee"/><button className="btn ghost" style={{padding:8}}>Create Opportunity</button></form>}</td></tr>})}{leads.length===0&&<tr><td colSpan={6} className="subtle">No leads yet. Create the first governed CRM record above.</td></tr>}</tbody></table></div></section>

    <section className="panel" style={{marginTop:16}}><h3>Opportunity Pipeline</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Opportunity</th><th>Stage</th><th>Probability</th><th>Expected Fee</th><th>Decision Due</th><th>Structured Loss</th></tr></thead><tbody>{opportunities.map(o=><tr key={o.id}><td>{o.project_name}{o.lost_reason_code&&<div className="subtle">Lost reason: {o.lost_reason_code}</div>}</td><td><span className="badge">{o.stage}</span></td><td>{o.probability}%</td><td>{money(o.expected_fee,o.currency)}</td><td>{o.decision_due_at?new Date(o.decision_due_at).toLocaleDateString("en-IN"):"—"}</td><td>{!["won","lost"].includes(o.stage)?<form action={markLost} style={{display:"grid",gap:6,minWidth:190}}><input type="hidden" name="opportunity_id" value={o.id}/><input name="reason_code" required placeholder="Structured reason code"/><input name="reason_detail" placeholder="Reason detail"/><input name="remarketing_segment" placeholder="Remarketing segment (optional)"/><button className="btn ghost" style={{padding:8}}>Mark Lost</button></form>:o.remarketing_segment?<span className="subtle">{o.remarketing_eligible?"Eligible":"Suppressed"} · {o.remarketing_segment}</span>:"—"}</td></tr>)}{opportunities.length===0&&<tr><td colSpan={6} className="subtle">No opportunities yet.</td></tr>}</tbody></table></div></section>

    <div className="panel-grid">
      <section className="panel"><h3>Record Activity</h3><form action={recordActivity}><div className="field"><label>Lead / Opportunity</label><select name="target" required defaultValue=""><option value="" disabled>Select record</option>{activeLeads.map(l=><option key={`l-${l.id}`} value={`lead:${l.id}`}>Lead · {(l.contact_id?contactMap.get(l.contact_id)?.full_name:null)||l.project_typology||l.id.slice(0,8)}</option>)}{opportunities.map(o=><option key={`o-${o.id}`} value={`opportunity:${o.id}`}>Opportunity · {o.project_name}</option>)}</select></div><div className="field"><label>Activity Type</label><input name="activity_type" defaultValue="note" required/></div><div className="field"><label>Summary</label><textarea name="summary" rows={3} required/></div><button className="btn">Record Activity</button></form><div className="note"><b>Consent boundary.</b> A CRM record does not imply marketing permission. Lost-opportunity remarketing is suppressed automatically when the linked contact has no recorded channel consent.</div></section>
      <section className="panel"><h3>Recent Activity</h3>{activities.slice(0,12).map(a=><div key={a.id} style={{padding:"10px 0",borderTop:"1px solid #edf0f2"}}><b>{a.activity_type.replaceAll("_"," ")}</b><div>{a.summary}</div><div className="subtle">{new Date(a.occurred_at).toLocaleString("en-IN")}{a.origin_lead_id&&a.origin_lead_id!==a.lead_id?` · origin ${a.origin_lead_id.slice(0,8)}`:""}</div></div>)}{activities.length===0&&<p className="subtle">No CRM activity has been recorded yet.</p>}</section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Remarketing Governance</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Opportunity</th><th>Segment</th><th>Reason</th><th>Status</th><th>Suppression</th></tr></thead><tbody>{remarketing.map(r=>{const o=opportunities.find(x=>x.id===r.opportunity_id);return <tr key={r.id}><td>{o?.project_name||r.opportunity_id.slice(0,8)}</td><td>{r.segment}</td><td>{r.reason_code}</td><td><span className="badge">{r.status}</span></td><td>{r.suppression_reason||"—"}</td></tr>})}{remarketing.length===0&&<tr><td colSpan={5} className="subtle">No remarketing entries exist. The system will create one only through a structured lost-opportunity decision.</td></tr>}</tbody></table></div></section>
  </>;
}
