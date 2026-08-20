"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";
import type {EngineeringProject,EngineeringWorkspaceState,CalculationRun} from "@/components/engineering-validation-types";

const list=(v:string)=>v.split(/[\n,]/).map(x=>x.trim()).filter(Boolean);
const human=(v:string)=>v.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const statusClass=(v:string)=>v==="ELIGIBLE_FOR_RELEASE_GATE"||v==="PROFESSIONALLY_REVIEWED"?"badge":"badge";

export default function EngineeringValidationClient({projects,state}:{projects:EngineeringProject[];state:EngineeringWorkspaceState}){
 const router=useRouter(),supabase=createClient();
 const [message,setMessage]=useState(""),[busy,startTransition]=useTransition();
 const refresh=(m:string)=>{setMessage(m);startTransition(()=>router.refresh());};
 const eligibleEngines=state.engines.filter(e=>e.enabled&&["approved","conditionally_approved"].includes(e.certification_status));
 const verifiedCredentials=state.credentials.filter(c=>c.verification_status==="verified");

 async function addSystem(form:FormData){
  const criteria=String(form.get("criteria")||"").trim();
  const {data,error}=await supabase.rpc("register_mep_system",{target_project_id:String(form.get("project_id")||""),target_discipline:String(form.get("discipline")||"mechanical"),target_system_code:String(form.get("system_code")||""),target_name:String(form.get("name")||""),target_design_criteria:{basis:criteria},target_reason:"Human-defined project engineering system criteria"});
  if(error){setMessage(error.message);return;}refresh(`System ${String(data).slice(0,8)} registered at Criteria state.`);
 }

 async function recordCalculation(form:FormData){
  const engine=state.engines.find(e=>e.id===String(form.get("engine_id")||""));
  if(!engine){setMessage("Select a certified engine version.");return;}
  const standards=list(String(form.get("standards")||""));
  const assumptions=list(String(form.get("assumptions")||""));
  const evidence=list(String(form.get("evidence_refs")||""));
  const {data,error}=await supabase.rpc("record_engineering_calculation",{
   target_project_id:String(form.get("project_id")||""),target_discipline:String(form.get("discipline")||""),target_calculation_type:String(form.get("calculation_type")||""),target_engine_id:engine.id,
   target_input_snapshot_ref:String(form.get("input_ref")||""),target_input_hash:String(form.get("input_hash")||""),target_assumptions:assumptions,target_standard_references:standards,
   target_unit_system:String(form.get("unit_system")||""),target_output_ref:String(form.get("output_ref")||""),target_output_hash:String(form.get("output_hash")||""),target_result_summary:{summary:String(form.get("result_summary")||"")},
   target_evidence_refs:evidence,target_reason:"Recorded reproducible engineering calculation provenance for governed validation"
  });
  if(error){setMessage(error.message);return;}refresh(`Calculation ${String(data).slice(0,8)} recorded. It is not release-eligible until professional review is valid for the exact output hash.`);
 }

 async function review(run:CalculationRun,form:FormData){
  const {data,error}=await supabase.rpc("review_engineering_calculation",{target_calculation_run_id:run.id,target_credential_id:String(form.get("credential_id")||""),target_decision:String(form.get("decision")||"accepted"),target_comments:String(form.get("comments")||"")});
  if(error){setMessage(error.message);return;}refresh(`Professional review ${String(data).slice(0,8)} bound to output hash ${run.output_hash?.slice(0,12)||""}.`);
 }

 return <>
  {message&&<div className="note" style={{marginBottom:18}}><b>Engineering V&V:</b> {message}{busy?" Refreshing…":""}</div>}
  <div className="kpis">{[["Systems",state.systems.length],["Certified Engines",eligibleEngines.length],["Calculation Records",state.calculation_runs.length],["Professionally Reviewed",state.calculation_runs.filter(r=>r.verification_state==="PROFESSIONALLY_REVIEWED").length],["Release Eligible",state.calculation_runs.filter(r=>r.release_state==="ELIGIBLE_FOR_RELEASE_GATE").length]].map(([l,v])=><div className="kpi" key={String(l)}><div className="label">{l}</div><div className="value">{String(v).padStart(2,"0")}</div><div className="subtle">Live evidence</div></div>)}</div>

  <div className="panel-grid"><section className="panel"><h3>Register Engineering System</h3><form action={addSystem}>
   <div className="field"><label>Project</label><select name="project_id" required>{projects.map(p=><option key={p.id} value={p.id}>{p.code} · {p.name} · {p.criticality}</option>)}</select></div>
   <div className="field"><label>Discipline</label><select name="discipline"><option value="mechanical">Mechanical</option><option value="electrical">Electrical</option><option value="plumbing">Plumbing</option><option value="fire">Fire / Life Safety</option><option value="elv">ELV</option><option value="bms">BMS</option><option value="vertical_transport">Vertical Transport</option></select></div>
   <div className="field"><label>System code</label><input name="system_code" required placeholder="MECH-HVAC-01"/></div><div className="field"><label>System name</label><input name="name" required placeholder="HVAC design criteria"/></div>
   <div className="field"><label>Design criteria / basis</label><textarea name="criteria" rows={4} placeholder="Human-defined load basis, occupancy, temperatures, diversity, redundancy, code basis…"/></div><button className="btn" disabled={!projects.length}>Register Criteria</button>
  </form></section>
  <section className="panel"><h3>Verification Boundary</h3><p className="subtle">This workspace does not invent or simulate engineering results. It records the immutable provenance of an externally executed deterministic or physics-based calculation from a certified engine version, then binds qualified human review to that exact output hash.</p><div className="note"><b>NOT VERIFIED is the default.</b> An output remains blocked when engine certification, version identity, project criticality coverage, calculation evidence, credential validity or exact-hash professional review is insufficient.</div></section></div>

  <section className="panel" style={{marginTop:18}}><h3>System Register</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Project</th><th>Code</th><th>Discipline</th><th>System</th><th>State</th></tr></thead><tbody>{state.systems.map(s=><tr key={s.id}><td>{s.project_code}<div className="subtle">{s.project_name}</div></td><td>{s.system_code}</td><td>{human(s.discipline)}</td><td>{s.name}</td><td><span className="badge">{human(s.status)}</span></td></tr>)}{!state.systems.length&&<tr><td colSpan={5} className="subtle">No live engineering systems registered yet.</td></tr>}</tbody></table></div></section>

  <section className="panel" style={{marginTop:18}}><h3>Record Calculation Provenance</h3><div className="note" style={{marginBottom:14}}><b>Evidence registration only.</b> Enter references and hashes produced by a real solver/execution workflow. The platform will reject uncertified engines, unsupported standards/units and engines below the project criticality.</div><form action={recordCalculation}>
   <div className="panel-grid"><div><div className="field"><label>Project</label><select name="project_id" required>{projects.map(p=><option key={p.id} value={p.id}>{p.code} · {p.criticality} · {p.name}</option>)}</select></div><div className="field"><label>Discipline</label><input name="discipline" required placeholder="mechanical"/></div><div className="field"><label>Calculation type</label><input name="calculation_type" required placeholder="cooling_load / demand_load / water_demand"/></div><div className="field"><label>Certified engine version</label><select name="engine_id" required>{eligibleEngines.map(e=><option key={e.id} value={e.id}>{e.code} · {e.version} · max {e.maximum_criticality}</option>)}</select></div><div className="field"><label>Unit system</label><input name="unit_system" required placeholder="SI"/></div><div className="field"><label>Standards used</label><textarea name="standards" rows={2} required placeholder="Must match standards declared by selected engine"/></div></div>
   <div><div className="field"><label>Input snapshot reference</label><input name="input_ref" required placeholder="immutable://inputs/..."/></div><div className="field"><label>Input hash</label><input name="input_hash" required placeholder="sha256…"/></div><div className="field"><label>Output reference</label><input name="output_ref" required placeholder="immutable://outputs/..."/></div><div className="field"><label>Output hash</label><input name="output_hash" required placeholder="sha256…"/></div><div className="field"><label>Assumptions</label><textarea name="assumptions" rows={2} placeholder="one assumption per line"/></div><div className="field"><label>Execution evidence references</label><textarea name="evidence_refs" rows={2} required placeholder="logs, reports, solver artifacts, reproducibility evidence"/></div><div className="field"><label>Result summary</label><textarea name="result_summary" rows={2}/></div></div></div>
   <button className="btn" disabled={!projects.length||!eligibleEngines.length}>Record Immutable Calculation Evidence</button>{!eligibleEngines.length&&<span className="subtle" style={{marginLeft:10}}>No certified enabled engine is available.</span>}
  </form></section>

  <section style={{marginTop:18}}><div className="topbar"><div><div className="demo">Exact Hash / Professional Authority</div><h2>Calculation Validation Ledger</h2></div></div><div className="grid-3">{state.calculation_runs.map(run=><div className="card" key={run.id}><div className="eyebrow">{run.project_code} · {human(run.discipline)}</div><h3>{run.calculation_type}</h3><p><b>{run.engine_code}</b> v{run.engine_version} · engine {human(run.engine_certification)} · max {run.engine_maximum_criticality}</p><div className="subtle">Input {run.input_hash?.slice(0,14)}…<br/>Output {run.output_hash?.slice(0,14)}…<br/>Verification <span className={statusClass(run.verification_state)}>{human(run.verification_state)}</span><br/>Release <span className={statusClass(run.release_state)}>{human(run.release_state)}</span></div>
   {run.release_state!=="ELIGIBLE_FOR_RELEASE_GATE"&&verifiedCredentials.length>0&&<form action={f=>review(run,f)} style={{marginTop:12}}><div className="field"><label>Verified credential</label><select name="credential_id">{verifiedCredentials.map(c=><option key={c.id} value={c.id}>{c.credential_type} · {c.registration_number} · {c.discipline||"multi"}</option>)}</select></div><div className="field"><label>Decision</label><select name="decision"><option value="accepted">Accept</option><option value="accepted_with_comments">Accept with comments</option><option value="rejected">Reject</option></select></div><div className="field"><label>Review comments</label><textarea name="comments" rows={2}/></div><button className="btn">Bind Professional Review</button></form>}
   {run.release_state!=="ELIGIBLE_FOR_RELEASE_GATE"&&!verifiedCredentials.length&&<div className="note" style={{marginTop:12}}>No verified professional credential is available for your user. This output remains blocked.</div>}
  </div>)}{!state.calculation_runs.length&&<div className="note">No calculation provenance has been recorded. No engineering output is represented as verified.</div>}</div></section>
 </>;
}
