"use client";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";
import type {EngineeringWorkspaceState,EngineeringEngine,BenchmarkCase} from "@/components/engineering-validation-types";

const csv=(v:string)=>v.split(/[\n,]/).map(x=>x.trim()).filter(Boolean);
const human=(v:string)=>v.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());

export default function EngineeringRegistryClient({state}:{state:EngineeringWorkspaceState}){
 const router=useRouter(),supabase=createClient();
 const [message,setMessage]=useState(""),[busy,startTransition]=useTransition();
 const refresh=(m:string)=>{setMessage(m);startTransition(()=>router.refresh());};
 if(!state.is_platform_admin)return <div className="note"><b>Platform administration required.</b> Engineering engine certification is restricted to the governed registry authority.</div>;

 async function register(form:FormData){
  const {data,error}=await supabase.rpc("register_engine_version",{
   target_code:String(form.get("code")||""),target_name:String(form.get("name")||""),target_discipline:String(form.get("discipline")||""),target_engine_type:String(form.get("engine_type")||"deterministic"),
   target_vendor:String(form.get("vendor")||""),target_version:String(form.get("version")||""),target_executable_ref:String(form.get("executable_ref")||""),
   target_supported_standards:csv(String(form.get("standards")||"")),target_supported_units:csv(String(form.get("units")||"")),target_maximum_criticality:String(form.get("max_criticality")||"C1"),
   target_checksum:String(form.get("checksum")||""),target_reason:"Registered as an uncertified version pending benchmark evidence"
  });
  if(error){setMessage(error.message);return;}refresh(`Engine ${String(data).slice(0,8)} registered disabled and uncertified.`);
 }
 async function addBenchmark(form:FormData){
  const toleranceText=String(form.get("tolerance")||"").trim();
  let tolerance:Record<string,unknown>={};
  if(toleranceText){try{tolerance=JSON.parse(toleranceText);}catch{setMessage("Benchmark tolerance must be valid JSON.");return;}}
  const {data,error}=await supabase.rpc("add_engine_benchmark_case",{
   target_engine_id:String(form.get("engine_id")||""),target_suite_code:String(form.get("suite_code")||""),target_name:String(form.get("name")||""),target_standard_reference:String(form.get("standard_ref")||""),
   target_input_ref:String(form.get("input_ref")||""),target_expected_result_ref:String(form.get("expected_ref")||""),target_tolerance:tolerance,target_criticality:String(form.get("criticality")||"C1"),target_reason:"Benchmark case added for controlled certification"
  });
  if(error){setMessage(error.message);return;}refresh(`Benchmark case ${String(data).slice(0,8)} added.`);
 }
 async function recordResult(form:FormData){
  const {data,error}=await supabase.rpc("record_engine_benchmark_result",{
   target_benchmark_case_id:String(form.get("case_id")||""),target_passed:String(form.get("passed")||"true")==="true",target_deviation:{notes:String(form.get("deviation")||"")},
   target_evidence_refs:csv(String(form.get("evidence_refs")||"")),target_reason:"Recorded reproducible benchmark execution evidence"
  });
  if(error){setMessage(error.message);return;}refresh(`Benchmark result ${String(data).slice(0,8)} recorded.`);
 }
 async function certify(engine:EngineeringEngine,form:FormData){
  const {error}=await supabase.rpc("set_engine_certification",{target_engine_id:engine.id,target_certification_status:String(form.get("status")||"benchmarking"),target_maximum_criticality:String(form.get("max_criticality")||engine.maximum_criticality),target_reason:String(form.get("reason")||"Human certification review")});
  if(error){setMessage(error.message);return;}refresh(`${engine.code} certification updated.`);
 }
 const latest=(c:BenchmarkCase)=>state.benchmark_results.filter(r=>r.benchmark_case_id===c.id).sort((a,b)=>b.executed_at.localeCompare(a.executed_at))[0];

 return <>
  {message&&<div className="note" style={{marginBottom:18}}><b>Registry:</b> {message}{busy?" Refreshing…":""}</div>}
  <div className="kpis">{[["Registered",state.engines.length],["Approved",state.engines.filter(e=>e.certification_status==="approved").length],["Benchmarking",state.engines.filter(e=>e.certification_status==="benchmarking").length],["Enabled",state.engines.filter(e=>e.enabled).length],["Benchmark Cases",state.benchmark_cases.length]].map(([l,v])=><div className="kpi" key={String(l)}><div className="label">{l}</div><div className="value">{String(v).padStart(2,"0")}</div><div className="subtle">Live registry</div></div>)}</div>

  <div className="panel-grid"><section className="panel"><h3>Register Engine Version</h3><form action={register}>
   <div className="field"><label>Engine code</label><input name="code" required placeholder="ENG-HVAC-LOAD"/></div><div className="field"><label>Name</label><input name="name" required/></div>
   <div className="field"><label>Discipline</label><input name="discipline" required placeholder="mechanical"/></div><div className="field"><label>Engine type</label><select name="engine_type"><option>deterministic</option><option>physics_simulation</option><option>rules</option><option>parametric</option><option>optimisation</option><option>adapter</option></select></div>
   <div className="field"><label>Vendor</label><input name="vendor"/></div><div className="field"><label>Version</label><input name="version" required placeholder="1.0.0"/></div>
   <div className="field"><label>Executable reference</label><input name="executable_ref" placeholder="container/build/API identity"/></div><div className="field"><label>Checksum / build identity</label><input name="checksum" required/></div>
   <div className="field"><label>Supported standards</label><textarea name="standards" rows={2} required placeholder="NBC-2016, ASHRAE-90.1"/></div><div className="field"><label>Supported unit systems</label><input name="units" required placeholder="SI"/></div>
   <div className="field"><label>Maximum proposed criticality</label><select name="max_criticality" defaultValue="C1">{["C0","C1","C2","C3","C4"].map(x=><option key={x}>{x}</option>)}</select></div><button className="btn">Register Uncertified Version</button>
  </form></section>
  <section className="panel"><h3>Certification Rule</h3><p className="subtle">Registration never enables an engine. Conditional or full approval requires checksum identity, declared standards and units, an active benchmark suite, and a latest passing result for every active benchmark at the exact engine version.</p><div className="note"><b>Fail closed.</b> Conditional approval cannot exceed C2. Suspended, retired, uncertified and benchmarking engines are disabled for project calculation evidence.</div></section></div>

  <section className="panel" style={{marginTop:18}}><h3>Versioned Engine Registry</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Engine</th><th>Discipline</th><th>Version</th><th>Certification</th><th>Max</th><th>Benchmarks</th><th>Control</th></tr></thead><tbody>
   {state.engines.map(e=>{const cases=state.benchmark_cases.filter(c=>c.engine_id===e.id);return <tr key={e.id}><td><b>{e.code}</b><div className="subtle">{e.name}</div></td><td>{human(e.discipline)}</td><td>{e.version}</td><td><span className="badge">{human(e.certification_status)}</span>{e.enabled?" · enabled":" · disabled"}</td><td>{e.maximum_criticality}</td><td>{cases.length} case(s)<div className="subtle">{cases.filter(c=>latest(c)?.passed).length} latest-pass</div></td><td><form action={f=>certify(e,f)}><select name="status" defaultValue={e.certification_status}><option value="uncertified">Uncertified</option><option value="benchmarking">Benchmarking</option><option value="conditionally_approved">Conditionally Approved</option><option value="approved">Approved</option><option value="suspended">Suspended</option><option value="retired">Retired</option></select><select name="max_criticality" defaultValue={e.maximum_criticality}>{["C0","C1","C2","C3","C4"].map(x=><option key={x}>{x}</option>)}</select><input name="reason" required placeholder="Human certification rationale"/><button className="btn ghost">Apply</button></form></td></tr>})}
   {!state.engines.length&&<tr><td colSpan={7} className="subtle">No registered engine versions. The platform will not accept engineering calculation evidence until a version is registered, benchmarked and certified.</td></tr>}
  </tbody></table></div></section>

  <div className="panel-grid" style={{marginTop:18}}><section className="panel"><h3>Add Benchmark Case</h3><form action={addBenchmark}><div className="field"><label>Engine</label><select name="engine_id" required>{state.engines.map(e=><option key={e.id} value={e.id}>{e.code} · {e.version}</option>)}</select></div><div className="field"><label>Suite code</label><input name="suite_code" required/></div><div className="field"><label>Case name</label><input name="name" required/></div><div className="field"><label>Standard reference</label><input name="standard_ref"/></div><div className="field"><label>Immutable input reference</label><input name="input_ref" required/></div><div className="field"><label>Expected result reference</label><input name="expected_ref" required/></div><div className="field"><label>Tolerance JSON</label><textarea name="tolerance" rows={2} defaultValue={'{"relative_percent":1}'}/></div><div className="field"><label>Benchmark criticality</label><select name="criticality" defaultValue="C1">{["C0","C1","C2","C3","C4"].map(x=><option key={x}>{x}</option>)}</select></div><button className="btn" disabled={!state.engines.length}>Add Benchmark</button></form></section>
  <section className="panel"><h3>Record Benchmark Execution</h3><form action={recordResult}><div className="field"><label>Benchmark case</label><select name="case_id" required>{state.benchmark_cases.map(c=><option key={c.id} value={c.id}>{c.suite_code} · {c.name}</option>)}</select></div><div className="field"><label>Result</label><select name="passed"><option value="true">Pass</option><option value="false">Fail</option></select></div><div className="field"><label>Deviation notes</label><textarea name="deviation" rows={2}/></div><div className="field"><label>Execution evidence references</label><textarea name="evidence_refs" rows={3} required placeholder="logs/build artifacts/reproducible result refs"/></div><button className="btn" disabled={!state.benchmark_cases.length}>Record Result</button></form></section></div>
 </>;
}
