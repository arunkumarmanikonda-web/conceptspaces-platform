"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";

export type LearningSignal={id:string;project_id:string;project_code:string;project_name:string;signal_type:string;source_ref:string;confidence:string;privacy_state:string;captured_at:string};
export type GenomeCandidate={id:string;pattern_code:string;source_signal_refs:string[];proposed_principle:string;stage:string;evidence_score:number;expert_reviewer_refs:string[];benchmark_refs:string[];rollback_ref?:string|null};
export type GenomeEvent={id:string;candidate_id:string;from_stage?:string|null;to_stage:string;reason:string;created_at:string};
export type LearningWorkspaceState={is_platform_admin:boolean;signals:LearningSignal[];candidates:GenomeCandidate[];events:GenomeEvent[]};
export type LearningProject={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};

const stages=["observation","evidence","privacy_review","expert_review","benchmark","shadow","controlled_production"];
const labels:Record<string,string>={observation:"Observation",evidence:"Evidence",privacy_review:"Privacy Review",expert_review:"Expert Review",benchmark:"Benchmark",shadow:"Shadow",controlled_production:"Controlled Production",retired:"Retired",client_approval:"Client approval",design_change:"Design change",coordination_issue:"Coordination issue",site_ncr:"Site NCR",cost_variance:"Cost variance",schedule_variance:"Schedule variance",energy_outcome:"Energy outcome",maintenance_outcome:"Maintenance outcome",post_occupancy:"Post occupancy"};
const human=(v:string)=>labels[v]||v.replaceAll("_"," ");
const next=(v:string)=>{const i=stages.indexOf(v);return i>=0&&i<stages.length-1?stages[i+1]:null;};
const list=(v:string)=>v.split(/[\n,]/).map(x=>x.trim()).filter(Boolean);

export default function DesignGenomeClient({projects,state}:{projects:LearningProject[];state:LearningWorkspaceState}){
 const router=useRouter(),supabase=createClient();
 const [message,setMessage]=useState(""),[selected,setSelected]=useState<string[]>([]),[busy,startTransition]=useTransition();
 const refresh=(m:string)=>{setMessage(m);startTransition(()=>router.refresh());};
 const toggle=(id:string)=>setSelected(v=>v.includes(id)?v.filter(x=>x!==id):[...v,id]);

 async function record(form:FormData){
  const {data,error}=await supabase.rpc("record_outcome_signal",{target_project_id:String(form.get("project_id")||""),target_signal_type:String(form.get("signal_type")||"client_approval"),target_source_ref:String(form.get("source_ref")||""),target_value:{notes:String(form.get("notes")||"")},target_confidence:String(form.get("confidence")||"C"),target_captured_at:new Date().toISOString(),target_reason:"Human-recorded project outcome evidence"});
  if(error){setMessage(error.message);return;}refresh(`Outcome ${String(data).slice(0,8)} recorded as privacy-pending.`);
 }
 async function privacy(id:string,status:string){
  const {error}=await supabase.rpc("set_outcome_signal_privacy",{target_signal_id:id,target_privacy_state:status,target_reason:`Human privacy review: ${status} for reusable learning evidence`});
  if(error){setMessage(error.message);return;}refresh(`Evidence ${status} after privacy review.`);
 }
 async function propose(form:FormData){
  if(!selected.length){setMessage("Select at least one outcome signal.");return;}
  const {data,error}=await supabase.rpc("propose_design_genome_candidate",{target_pattern_code:String(form.get("pattern_code")||""),target_source_signal_refs:selected,target_proposed_principle:String(form.get("principle")||""),target_applicable_typologies:list(String(form.get("typologies")||"")),target_applicable_climates:list(String(form.get("climates")||"")),target_reason:"Human-created learning observation; not production-approved"});
  if(error){setMessage(error.message);return;}setSelected([]);refresh(`Candidate ${String(data).slice(0,8)} created at Observation.`);
 }
 async function advance(c:GenomeCandidate,form:FormData){
  const target=next(c.stage);if(!target)return;
  const score=String(form.get("score")||"").trim(),experts=list(String(form.get("experts")||"")),benchmarks=list(String(form.get("benchmarks")||""));
  const {error}=await supabase.rpc("advance_design_genome_candidate",{target_candidate_id:c.id,target_stage:target,target_reason:String(form.get("reason")||"Human governed review"),target_evidence_score:score?Number(score):null,target_expert_reviewer_refs:experts.length?experts:null,target_benchmark_refs:benchmarks.length?benchmarks:null,target_rollback_ref:String(form.get("rollback")||"").trim()||null});
  if(error){setMessage(error.message);return;}refresh(`${c.pattern_code} advanced to ${human(target)}.`);
 }
 async function retire(c:GenomeCandidate){const {error}=await supabase.rpc("advance_design_genome_candidate",{target_candidate_id:c.id,target_stage:"retired",target_reason:"Human retirement from reusable learning",target_evidence_score:null,target_expert_reviewer_refs:null,target_benchmark_refs:null,target_rollback_ref:null});if(error){setMessage(error.message);return;}refresh(`${c.pattern_code} retired.`);}

 return <>
  {message&&<div className="note" style={{marginBottom:18}}><b>Design Genome:</b> {message}{busy?" Refreshing…":""}</div>}
  <section className="panel"><h3>Governed Promotion Pipeline</h3><div className="grid-3">{stages.map((s,i)=><div className="card" key={s}><div className="eyebrow">0{i+1}</div><h3>{human(s)}</h3><p>{state.candidates.filter(c=>c.stage===s).length} active candidate(s)</p></div>)}</div><div className="note" style={{marginTop:14}}><b>No direct self-training.</b> Promotion is sequential, evidence must span projects, privacy approval precedes expert review, and controlled production requires benchmark evidence plus rollback.</div></section>

  <div className="panel-grid" style={{marginTop:18}}><section className="panel"><h3>Record Project Outcome</h3><form action={record}><div className="field"><label>Project</label><select name="project_id" required>{projects.map(p=><option key={p.id} value={p.id}>{p.code} · {p.name}</option>)}</select></div><div className="field"><label>Signal type</label><select name="signal_type">{["client_approval","design_change","coordination_issue","site_ncr","cost_variance","schedule_variance","energy_outcome","maintenance_outcome","post_occupancy"].map(v=><option key={v} value={v}>{human(v)}</option>)}</select></div><div className="field"><label>Source reference</label><input name="source_ref" required placeholder="Document, issue, NCR or verified report"/></div><div className="field"><label>Confidence</label><select name="confidence" defaultValue="C"><option>A</option><option>B</option><option>C</option><option>D</option></select></div><div className="field"><label>Evidence notes</label><textarea name="notes" rows={3}/></div><button className="btn" disabled={!projects.length}>Record Evidence</button></form></section><section className="panel"><h3>Learning Controls</h3><div className="metric-grid"><div><b>{state.signals.length}</b><span>Signals</span></div><div><b>{state.signals.filter(s=>s.privacy_state==="approved").length}</b><span>Privacy approved</span></div><div><b>{state.candidates.filter(c=>c.stage==="controlled_production").length}</b><span>Controlled production</span></div></div><p className="subtle" style={{marginTop:14}}>Project teams may record outcomes where they have management authority. Only platform administration can classify reusable evidence and promote Design Genome candidates.</p></section></div>

  <section className="panel" style={{marginTop:18}}><h3>Outcome Evidence Ledger</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Project</th><th>Outcome</th><th>Source</th><th>Confidence</th><th>Privacy</th><th>Review</th></tr></thead><tbody>{state.signals.map(s=><tr key={s.id}><td><b>{s.project_code}</b><div className="subtle">{s.project_name}</div></td><td>{human(s.signal_type)}</td><td><code>{s.source_ref}</code></td><td>{s.confidence}</td><td><span className="badge">{s.privacy_state}</span></td><td>{state.is_platform_admin?<div style={{display:"flex",gap:6}}><button type="button" className="btn ghost" onClick={()=>privacy(s.id,"approved")}>Approve</button><button type="button" className="btn ghost" onClick={()=>privacy(s.id,"excluded")}>Exclude</button></div>:"—"}</td></tr>)}{!state.signals.length&&<tr><td colSpan={6} className="subtle">No outcome evidence recorded yet.</td></tr>}</tbody></table></div></section>

  {state.is_platform_admin&&<section className="panel" style={{marginTop:18}}><h3>Create Learning Observation</h3><form action={propose}><div className="panel-grid"><div><div className="field"><label>Pattern code</label><input name="pattern_code" required placeholder="hotel_core_efficiency_01"/></div><div className="field"><label>Proposed reusable principle</label><textarea name="principle" rows={4} required/></div><div className="field"><label>Applicable typologies</label><input name="typologies" placeholder="hotel, residential"/></div><div className="field"><label>Applicable climates</label><input name="climates" placeholder="composite, warm_humid"/></div></div><div><div className="eyebrow">Source evidence</div><div style={{display:"grid",gap:8,maxHeight:250,overflowY:"auto"}}>{state.signals.map(s=><label className="card" key={s.id} style={{padding:10}}><input type="checkbox" checked={selected.includes(s.id)} onChange={()=>toggle(s.id)} style={{marginRight:8}}/><b>{s.project_code}</b> · {human(s.signal_type)} <span className="badge">{s.privacy_state}</span><div className="subtle">{s.source_ref}</div></label>)}</div></div></div><button className="btn" style={{marginTop:14}}>Create Observation</button></form></section>}

  {state.is_platform_admin&&<section style={{marginTop:18}}><h2>Human-Governed Learning Queue</h2><div className="grid-3">{state.candidates.map(c=>{const target=next(c.stage);return <div className="card" key={c.id}><div className="eyebrow">{c.pattern_code}</div><h3>{human(c.stage)}</h3><p>{c.proposed_principle}</p><div className="subtle">Sources {c.source_signal_refs.length} · Evidence score {c.evidence_score}{c.rollback_ref?<><br/>Rollback {c.rollback_ref}</>:null}</div>{target&&<form action={f=>advance(c,f)} style={{marginTop:12}}><div className="field"><label>Human rationale</label><textarea name="reason" rows={2} required defaultValue={`Reviewed for ${human(target)}.`}/></div>{target==="benchmark"&&<div className="field"><label>Expert reviewer references</label><textarea name="experts" rows={2}/></div>}{target==="shadow"&&<><div className="field"><label>Evidence score</label><input name="score" type="number" min="0" step="0.01" defaultValue={c.evidence_score||""}/></div><div className="field"><label>Benchmark references</label><textarea name="benchmarks" rows={2}/></div></>}{target==="controlled_production"&&<div className="field"><label>Rollback reference</label><input name="rollback" required defaultValue={c.rollback_ref||""}/></div>}<button className="btn">Advance to {human(target)}</button></form>}{c.stage!=="retired"&&<button type="button" className="btn ghost" style={{marginTop:8}} onClick={()=>retire(c)}>Retire</button>}</div>})}{!state.candidates.length&&<div className="note">No learning candidates yet.</div>}</div></section>}
 </>;
}
