"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";

export type ProfessionalOutcomeSource={id:string;signal_type:string;source_ref:string;value:Record<string,unknown>;confidence:string;captured_at:string;source_hash:string};
type Profile={id:string;display_name:string;discipline:string};
const short=(v:string)=>`${v.slice(0,12)}…`;
const pretty=(v:string)=>v.replaceAll("_"," ");

export default function ProfessionalOutcomePerformanceClient({projectId,profiles,sources}:{projectId:string;profiles:Profile[];sources:ProfessionalOutcomeSource[]}){
 const supabase=createClient();const router=useRouter();const [message,setMessage]=useState("");const [busy,startTransition]=useTransition();
 async function record(form:FormData){
  const source=sources.find(s=>s.id===String(form.get("source_id")||""));
  if(!source){setMessage("Select a governed project outcome source.");return;}
  const {error}=await supabase.rpc("record_professional_performance",{target_profile_id:String(form.get("profile_id")||""),target_project_id:projectId,input_payload:{metric_code:String(form.get("metric_code")||""),metric_value:String(form.get("metric_value")||""),unit:String(form.get("unit")||""),outcome_type:String(form.get("outcome_type")||"other"),source_ref:source.id,source_hash:source.source_hash,notes:String(form.get("notes")||"")}});
  if(error){setMessage(error.message);return;}setMessage("Performance metric recorded against the exact governed project outcome hash.");startTransition(()=>router.refresh());
 }
 return <section className="panel" style={{marginTop:16}}><h3>Governed Outcome Performance</h3><p className="subtle">Performance evidence must resolve to a real project outcome signal. The server recomputes the selected source hash before accepting the metric.</p>{message&&<div className="note" style={{marginBottom:10}}>{message}{busy?" Refreshing…":""}</div>}
  <form action={record}><div className="field"><label>Professional</label><select name="profile_id" required>{profiles.map(p=><option key={p.id} value={p.id}>{p.display_name} · {p.discipline}</option>)}</select></div><div className="field-grid"><div className="field"><label>Metric code</label><input name="metric_code" required/></div><div className="field"><label>Value</label><input name="metric_value" type="number" step="0.0001" required/></div><div className="field"><label>Unit</label><input name="unit" required/></div><div className="field"><label>Outcome type</label><select name="outcome_type"><option>first_pass_quality</option><option>correction</option><option>schedule</option><option>rfi</option><option>ncr</option><option>cost_impact</option><option>review</option><option>other</option></select></div></div><div className="field"><label>Governed project outcome</label><select name="source_id" required defaultValue=""><option value="" disabled>Select verified source evidence</option>{sources.map(s=><option key={s.id} value={s.id}>{pretty(s.signal_type)} · {s.source_ref} · {s.confidence} · {short(s.source_hash)}</option>)}</select></div><div className="field"><label>Notes</label><textarea name="notes" rows={2}/></div><button className="btn" disabled={!profiles.length||!sources.length}>Record Traceable Metric</button></form>
  <div style={{overflowX:"auto",marginTop:14}}><table className="table"><thead><tr><th>Outcome</th><th>Source</th><th>Confidence</th><th>Captured</th><th>Accepted hash</th></tr></thead><tbody>{sources.slice(0,20).map(s=><tr key={s.id}><td>{pretty(s.signal_type)}</td><td><b>{s.source_ref}</b><div className="subtle">{s.id}</div></td><td>{s.confidence}</td><td>{new Date(s.captured_at).toLocaleString("en-IN")}</td><td><code>{short(s.source_hash)}</code></td></tr>)}{sources.length===0&&<tr><td colSpan={5} className="subtle">No governed outcome signals are available for this project. Performance scoring remains blocked until real project outcomes exist.</td></tr>}</tbody></table></div>
 </section>;
}
