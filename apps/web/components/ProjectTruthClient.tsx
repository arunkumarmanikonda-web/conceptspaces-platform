"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";

export type TruthRow={id:string;kind:string;record_key:string;value:unknown;unit?:string|null;source_type?:string|null;source_reference?:string|null;confidence:string;status:string;criticality:string;verified_by?:string|null;verified_at?:string|null;created_at:string};

export default function ProjectTruthClient({projectId,rows}:{projectId:string;rows:TruthRow[]}){
 const supabase=createClient();const router=useRouter();const [message,setMessage]=useState("");const [busy,startTransition]=useTransition();
 const refresh=(m:string)=>{setMessage(m);startTransition(()=>router.refresh());};
 async function createTruth(form:FormData){let value:unknown;try{value=JSON.parse(String(form.get("value")||"null"));}catch{setMessage("Value must be valid JSON. Use a quoted string for text values.");return;}const payload={kind:String(form.get("kind")||"fact"),record_key:String(form.get("record_key")||""),value,unit:String(form.get("unit")||""),source_type:String(form.get("source_type")||""),source_reference:String(form.get("source_reference")||""),confidence:String(form.get("confidence")||"D"),criticality:String(form.get("criticality")||"C1")};const {error}=await supabase.rpc("create_project_truth_record",{target_project_id:projectId,input_payload:payload});if(error){setMessage(error.message);return;}refresh("Project Truth draft recorded with provenance.");}
 async function verify(row:TruthRow){const reason=window.prompt(`Reason for verifying ${row.record_key}?`);if(!reason)return;const {error}=await supabase.rpc("verify_project_truth_record",{target_truth_id:row.id,target_reason:reason});if(error){setMessage(error.message);return;}refresh("Truth record verified. Downstream compiler outputs were invalidated where required.");}
 async function supersede(row:TruthRow){const raw=window.prompt(`Replacement JSON value for ${row.record_key}`,JSON.stringify(row.value));if(raw===null)return;let value:unknown;try{value=JSON.parse(raw);}catch{setMessage("Replacement value must be valid JSON.");return;}const reason=window.prompt("Reason for superseding this Project Truth record?");if(!reason)return;const {error}=await supabase.rpc("supersede_project_truth_record",{target_truth_id:row.id,input_payload:{value},target_reason:reason});if(error){setMessage(error.message);return;}refresh("Prior truth preserved as superseded; replacement created as a new draft.");}
 return <>
  {message&&<div className="note" role="status" aria-live="polite" style={{marginBottom:16}}><b>Project Truth:</b> {message}{busy?" Refreshing…":""}</div>}
  <div className="panel-grid">
   <section className="panel"><h3>Capture Project Truth</h3><form action={createTruth}><div className="field-grid">
    <div className="field"><label>Kind</label><select name="kind" defaultValue="fact"><option value="fact">Fact</option><option value="assumption">Assumption</option><option value="decision">Decision</option><option value="requirement">Requirement</option><option value="constraint">Constraint</option><option value="evidence">Evidence</option></select></div>
    <div className="field"><label>Record Key</label><input name="record_key" placeholder="site.plot_area" required/></div>
    <div className="field" style={{gridColumn:"1/-1"}}><label>Value (JSON)</label><textarea name="value" rows={4} defaultValue={'{"value":0}'}/></div>
    <div className="field"><label>Unit</label><input name="unit" placeholder="m² / mm / kW / text"/></div>
    <div className="field"><label>Source Type</label><input name="source_type" placeholder="survey / client / authority / CDE"/></div>
    <div className="field" style={{gridColumn:"1/-1"}}><label>Source Reference</label><input name="source_reference" placeholder="Exact survey, document, clause or evidence reference"/></div>
    <div className="field"><label>Confidence</label><select name="confidence" defaultValue="D"><option>A</option><option>B</option><option>C</option><option>D</option></select></div>
    <div className="field"><label>Criticality</label><select name="criticality" defaultValue="C1"><option>C0</option><option>C1</option><option>C2</option><option>C3</option><option>C4</option></select></div>
   </div><button className="btn" style={{marginTop:14}}>Record Draft</button></form></section>
   <section className="panel"><h3>Verification Rule</h3><p className="subtle">Drafts may express incomplete knowledge. Verification requires an explicit source type and source reference, records the verifier and timestamp, and invalidates dependent compiler runs when authoritative inputs change.</p><div className="note"><b>No overwrite.</b> Changing a verified fact uses supersession: the prior version remains retrievable and the replacement returns to draft until independently verified.</div></section>
  </div>
  <section className="panel" style={{marginTop:18}}><h3>Governed Truth Records</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Record</th><th>Source</th><th>Confidence</th><th>Status</th><th>Verifier</th><th>Actions</th></tr></thead><tbody>{rows.map(r=><tr key={r.id}><td><b>{r.record_key}</b><div className="subtle">{r.kind} · {JSON.stringify(r.value)}</div></td><td>{r.source_type||"Unstated"}<div className="subtle">{r.source_reference||"No reference"}</div></td><td>{r.confidence} · {r.criticality}</td><td><span className="badge">{r.status}</span></td><td>{r.verified_by?<><code>{r.verified_by.slice(0,8)}…</code><div className="subtle">{r.verified_at?new Date(r.verified_at).toLocaleString("en-IN"):""}</div></>:"—"}</td><td><div style={{display:"flex",gap:6,flexWrap:"wrap"}}>{r.status==="draft"&&<button type="button" className="btn ghost" onClick={()=>verify(r)}>Verify</button>}{["draft","verified"].includes(r.status)&&<button type="button" className="btn ghost" onClick={()=>supersede(r)}>Supersede</button>}</div></td></tr>)}{rows.length===0&&<tr><td colSpan={6} className="subtle">No Project Truth records exist yet.</td></tr>}</tbody></table></div></section>
 </>;
}
