"use client";

import {useMemo,useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";
import type {ReleaseProject,ReleaseWorkspaceState,ReleaseSafetyCase,ReleaseGate} from "@/components/release-assurance-types";

const evidenceTypes=["truth_snapshot","regulatory_check","engineering_check","coordination_check","professional_approval","client_approval","document_hash"];
const human=(value:string)=>value.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());
const when=(value?:string|null)=>value?new Intl.DateTimeFormat("en-IN",{dateStyle:"medium",timeStyle:"short"}).format(new Date(value)):"—";

export default function ReleaseAssuranceClient({projects,state}:{projects:ReleaseProject[];state:ReleaseWorkspaceState}){
  const router=useRouter();
  const supabase=createClient();
  const [message,setMessage]=useState("");
  const [busy,startTransition]=useTransition();
  const [selectedEvidence,setSelectedEvidence]=useState<string[]>(["document_hash"]);
  const verifiedCredentials=state.credentials.filter(c=>c.verification_status==="verified");
  const activeCases=state.safety_cases.filter(c=>c.state!=="issued");
  const currentEvidence=state.evidence.filter(e=>e.current&&e.passed);
  const refresh=(text:string)=>{setMessage(text);startTransition(()=>router.refresh());};
  const toggleEvidence=(value:string)=>setSelectedEvidence(v=>v.includes(value)?v.filter(x=>x!==value):[...v,value]);
  const gateFor=(c:ReleaseSafetyCase)=>state.gates.find(g=>g.id===c.gate_id);

  async function createGate(form:FormData){
    const criticality=String(form.get("criticality")||"C1");
    const required=[...new Set([...selectedEvidence,"document_hash",...(criticality==="C3"||criticality==="C4"?["professional_approval"]:[])])];
    const {data,error}=await supabase.rpc("create_release_gate",{target_project_id:String(form.get("project_id")||""),target_gate_code:String(form.get("gate_code")||""),target_name:String(form.get("name")||""),target_discipline:String(form.get("discipline")||""),target_criticality:criticality,target_required_evidence_types:required,target_reason:"Human-defined package release gate and evidence policy"});
    if(error){setMessage(error.message);return;}refresh(`Release gate ${String(data).slice(0,8)} created in Not Ready state.`);
  }

  async function createCase(form:FormData){
    const {data,error}=await supabase.rpc("create_release_safety_case",{target_gate_id:String(form.get("gate_id")||""),target_package_type:String(form.get("package_type")||""),target_package_reference:String(form.get("package_reference")||""),target_content_hash:String(form.get("content_hash")||""),target_client_approval_ref:String(form.get("client_approval_ref")||""),target_reason:"Assembled exact-hash release safety case"});
    if(error){setMessage(error.message);return;}refresh(`Safety case ${String(data).slice(0,8)} created. Document-hash evidence was bound automatically.`);
  }

  async function capture(caseId:string,type:string,sourceId?:string,reference?:string){
    let result;
    if(type==="truth_snapshot")result=await supabase.rpc("capture_release_truth_snapshot",{target_safety_case_id:caseId,target_reason:"Captured current Project Truth for release"});
    else if(type==="coordination_check")result=await supabase.rpc("capture_release_coordination_check",{target_safety_case_id:caseId,target_reason:"Captured current coordination state for release"});
    else if(type==="regulatory_check")result=await supabase.rpc("capture_release_regulatory_check",{target_safety_case_id:caseId,target_evaluation_run_id:sourceId,target_reason:"Captured latest clean REGULA run for release"});
    else if(type==="engineering_check")result=await supabase.rpc("capture_release_engineering_check",{target_safety_case_id:caseId,target_calculation_run_id:sourceId,target_reason:"Captured reviewed engineering calculation for release"});
    else result=await supabase.rpc("capture_release_client_approval",{target_safety_case_id:caseId,target_approval_reference:reference,target_reason:"Captured client approval for exact package hash"});
    if(result.error){setMessage(result.error.message);return;}refresh(`${human(type)} evidence captured and hash-bound.`);
  }

  async function reviewPackage(c:ReleaseSafetyCase,form:FormData){
    const {data,error}=await supabase.rpc("review_release_package",{target_safety_case_id:c.id,target_credential_id:String(form.get("credential_id")||""),target_decision:String(form.get("decision")||"accepted"),target_comments:String(form.get("comments")||"")});
    if(error){setMessage(error.message);return;}refresh(`Professional review ${String(data).slice(0,8)} bound to package hash ${c.content_hash?.slice(0,12)}…`);
  }

  async function evaluate(c:ReleaseSafetyCase){const {data,error}=await supabase.rpc("evaluate_release_safety_case",{target_safety_case_id:c.id});if(error){setMessage(error.message);return;}refresh(`Fresh evaluation: ${String((data as Record<string,unknown>)?.state||"complete")}.`);}
  async function approve(c:ReleaseSafetyCase){const {error}=await supabase.rpc("approve_release_safety_case",{target_safety_case_id:c.id,target_reason:"Human approval after fresh package-level safety evaluation"});if(error){setMessage(error.message);return;}refresh(`${c.package_reference} approved for final issue gate.`);}
  async function issue(c:ReleaseSafetyCase){const {error}=await supabase.rpc("issue_release_safety_case",{target_safety_case_id:c.id,target_reason:"Issued after fresh re-evaluation and zero-critical-escape confirmation"});if(error){setMessage(error.message);return;}refresh(`${c.package_reference} issued. Gate is now Released.`);}

  async function raiseException(form:FormData){
    const caseId=String(form.get("safety_case_id")||""); const c=state.safety_cases.find(x=>x.id===caseId); const gate=c?gateFor(c):undefined;
    if(!c||!gate){setMessage("Select a valid safety case.");return;}
    const {data,error}=await supabase.rpc("raise_release_exception",{target_project_id:c.project_id,target_gate_id:gate.id,target_safety_case_id:c.id,target_exception_type:String(form.get("exception_type")||"release_defect"),target_description:String(form.get("description")||""),target_criticality:String(form.get("criticality")||"C2"),target_reason:String(form.get("reason")||"Release exception recorded")});
    if(error){setMessage(error.message);return;}refresh(`Exception ${String(data).slice(0,8)} raised. C3/C4 open or accepted exceptions block issue.`);
  }
  async function resolveException(id:string,status:string){const {error}=await supabase.rpc("resolve_release_exception",{target_exception_id:id,target_status:status,target_rationale:`Human release governance decision: ${status}`});if(error){setMessage(error.message);return;}refresh(`Exception marked ${status}.`);}

  const releasedCount=state.safety_cases.filter(c=>c.state==="issued").length;
  const blockedCount=state.safety_cases.filter(c=>c.state==="blocked").length;
  const criticalOpen=state.exceptions.filter(e=>["C3","C4"].includes(e.criticality)&&["open","accepted"].includes(e.status)).length;

  return <>
    {message&&<div className="note" style={{marginBottom:18}}><b>Release Assurance:</b> {message}{busy?" Refreshing…":""}</div>}
    <div className="kpis">{[["Release Gates",state.gates.length],["Safety Cases",state.safety_cases.length],["Current Evidence",currentEvidence.length],["Critical Blocks",criticalOpen],["Issued",releasedCount]].map(([l,v])=><div className="kpi" key={String(l)}><div className="label">{l}</div><div className="value">{String(v).padStart(2,"0")}</div><div className="subtle">Live governance state</div></div>)}</div>

    <div className="panel-grid">
      <section className="panel"><h3>Create Release Gate</h3><form action={createGate}>
        <div className="field"><label>Project</label><select name="project_id" required>{projects.map(p=><option key={p.id} value={p.id}>{p.code} · {p.name} · {p.criticality}</option>)}</select></div>
        <div className="field"><label>Gate code</label><input name="gate_code" required placeholder="GATE-DD-ARCH"/></div><div className="field"><label>Gate name</label><input name="name" required placeholder="Detailed Design Architecture"/></div>
        <div className="field"><label>Discipline</label><input name="discipline" required placeholder="architecture / mechanical / structural"/></div><div className="field"><label>Criticality</label><select name="criticality" defaultValue="C3">{["C0","C1","C2","C3","C4"].map(v=><option key={v}>{v}</option>)}</select></div>
        <div className="field"><label>Required evidence</label><div style={{display:"grid",gap:7}}>{evidenceTypes.map(t=><label key={t}><input type="checkbox" disabled={t==="document_hash"} checked={t==="document_hash"||selectedEvidence.includes(t)} onChange={()=>toggleEvidence(t)} style={{marginRight:8}}/>{human(t)}</label>)}</div></div>
        <button className="btn" disabled={!projects.length}>Create Governed Gate</button>
      </form></section>
      <section className="panel"><h3>Assemble Safety Case</h3><form action={createCase}>
        <div className="field"><label>Release gate</label><select name="gate_id" required>{state.gates.map(g=><option key={g.id} value={g.id}>{g.project_code} · {g.gate_code} · {g.criticality}</option>)}</select></div>
        <div className="field"><label>Package type</label><input name="package_type" required placeholder="drawing_set / IFC / tender / authority_submission"/></div><div className="field"><label>Package reference</label><input name="package_reference" required placeholder="DD-ARCH-01-R3"/></div>
        <div className="field"><label>Exact package content hash</label><input name="content_hash" required placeholder="sha256…"/></div><div className="field"><label>Client approval reference, if already available</label><input name="client_approval_ref"/></div>
        <button className="btn" disabled={!state.gates.length}>Assemble Exact-Hash Case</button>
      </form><div className="note" style={{marginTop:12}}><b>Immutable release identity.</b> A new package hash requires a new safety case. Existing approvals do not transfer to changed content.</div></section>
    </div>

    <section style={{marginTop:18}}><div className="topbar"><div><div className="demo">Proof Before Publish</div><h2>Package Safety Cases</h2></div></div><div className="grid-3">{state.safety_cases.map(c=>{const g=gateFor(c);const ev=state.evidence.filter(e=>e.safety_case_id===c.id);const required=g?.required_evidence_types||[];const latestReg=state.regulatory_runs.find(r=>r.project_id===c.project_id&&r.is_latest_completed);const eng=state.engineering_runs.filter(r=>r.project_id===c.project_id&&r.release_eligible);const check=(c.checks?.[0]||{}) as Record<string,unknown>;
      return <div className="card" key={c.id}><div className="eyebrow">{g?.gate_code||"Gate"} · {g?.criticality||""}</div><h3>{c.package_reference||c.package_type}</h3><p><span className="badge">{human(c.state)}</span> · {human(c.package_type)}</p><div className="subtle">Hash {c.content_hash?.slice(0,16)}…<br/>Required {required.length} · Captured {new Set(ev.filter(x=>x.current&&x.passed).map(x=>x.evidence_type)).size}<br/>Critical defects {c.unresolved_critical_defects}<br/>Last evaluated {when(c.last_evaluated_at)}</div>
        {c.state!=="issued"&&<><div style={{display:"flex",gap:6,flexWrap:"wrap",marginTop:12}}>
          {required.includes("truth_snapshot")&&<button className="btn ghost" type="button" onClick={()=>capture(c.id,"truth_snapshot")}>Capture Truth</button>}
          {required.includes("coordination_check")&&<button className="btn ghost" type="button" onClick={()=>capture(c.id,"coordination_check")}>Capture Coordination</button>}
          {required.includes("regulatory_check")&&<button className="btn ghost" type="button" disabled={!latestReg} onClick={()=>capture(c.id,"regulatory_check",latestReg?.id)}>Capture REGULA</button>}
          {required.includes("engineering_check")&&eng.map(r=><button className="btn ghost" type="button" key={r.id} onClick={()=>capture(c.id,"engineering_check",r.id)}>Add {human(r.discipline)} Calc</button>)}
        </div>
        {required.includes("client_approval")&&<form action={f=>capture(c.id,"client_approval",undefined,String(f.get("client_ref")||""))} style={{marginTop:10}}><div className="field"><label>Client approval reference</label><input name="client_ref" required placeholder="Signed approval / portal decision reference"/></div><button className="btn ghost">Bind Client Approval</button></form>}
        {required.includes("professional_approval")&&verifiedCredentials.length>0&&<form action={f=>reviewPackage(c,f)} style={{marginTop:10}}><div className="field"><label>Professional credential</label><select name="credential_id">{verifiedCredentials.map(cr=><option value={cr.id} key={cr.id}>{cr.credential_type} · {cr.registration_number} · {cr.discipline||"multi"}</option>)}</select></div><div className="field"><label>Decision</label><select name="decision"><option value="accepted">Accept</option><option value="accepted_with_comments">Accept with comments</option><option value="rejected">Reject</option></select></div><div className="field"><label>Comments</label><textarea name="comments" rows={2}/></div><button className="btn ghost">Bind Professional Review</button></form>}
        <div style={{display:"flex",gap:7,flexWrap:"wrap",marginTop:12}}><button className="btn ghost" type="button" onClick={()=>evaluate(c)}>Fresh Evaluate</button>{c.state==="ready_for_review"&&<button className="btn" type="button" onClick={()=>approve(c)}>Approve</button>}{c.state==="approved"&&<button className="btn" type="button" onClick={()=>issue(c)}>Issue Package</button>}</div></>}
        {c.state==="blocked"&&<div className="note" style={{marginTop:12}}><b>Blocked.</b> Missing {String(check.missing_required_evidence??"?")}, stale/failed {String(check.stale_or_failed_required_evidence??"?")}, C3/C4 exceptions {String(check.unresolved_C3_C4_exceptions??c.unresolved_critical_defects)}.</div>}
        {c.state==="issued"&&<div className="note" style={{marginTop:12}}><b>Issued.</b> Final release completed {when(c.issued_at)} for this exact hash.</div>}
      </div>;})}{!state.safety_cases.length&&<div className="note">No safety cases yet. Create a release gate, then assemble a package against an exact content hash.</div>}</div></section>

    <section className="panel" style={{marginTop:18}}><h3>Evidence Ledger</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Package</th><th>Evidence</th><th>Reference</th><th>Pass</th><th>Current</th><th>Captured</th></tr></thead><tbody>{state.evidence.map(e=>{const c=state.safety_cases.find(x=>x.id===e.safety_case_id);return <tr key={e.id}><td>{c?.package_reference||"—"}</td><td>{human(e.evidence_type)}</td><td><code>{e.reference}</code></td><td>{e.passed?"Yes":"No"}</td><td><span className="badge">{e.current?"Current":"Stale / Invalid"}</span></td><td>{when(e.produced_at)}</td></tr>})}{!state.evidence.length&&<tr><td colSpan={6} className="subtle">No release evidence captured yet.</td></tr>}</tbody></table></div></section>

    <div className="panel-grid" style={{marginTop:18}}><section className="panel"><h3>Raise Release Exception</h3><form action={raiseException}><div className="field"><label>Safety case</label><select name="safety_case_id" required>{activeCases.map(c=><option key={c.id} value={c.id}>{c.package_reference} · {gateFor(c)?.gate_code}</option>)}</select></div><div className="field"><label>Exception type</label><input name="exception_type" required placeholder="coordination_defect / incomplete_authority_evidence"/></div><div className="field"><label>Description</label><textarea name="description" required rows={3}/></div><div className="field"><label>Criticality</label><select name="criticality" defaultValue="C3">{["C0","C1","C2","C3","C4"].map(v=><option key={v}>{v}</option>)}</select></div><div className="field"><label>Rationale / source</label><textarea name="reason" required rows={2}/></div><button className="btn" disabled={!activeCases.length}>Raise Exception</button></form></section>
    <section className="panel"><h3>Zero Critical Escape</h3><p className="subtle">An open or accepted C3/C4 exception remains blocking. “Accepted” records governance acknowledgement; it does not waive the zero-critical-escape rule. Only resolution or rejection removes the release block.</p><div className="note"><b>No administrative bypass.</b> Issue performs a fresh evidence evaluation again after approval. If Project Truth, REGULA, engineering authority, coordination state, credential validity or any required evidence has changed, the package returns to Blocked instead of issuing.</div></section></div>

    <section className="panel" style={{marginTop:18}}><h3>Exceptions</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Criticality</th><th>Type</th><th>Description</th><th>Status</th><th>Decision</th></tr></thead><tbody>{state.exceptions.map(ex=><tr key={ex.id}><td>{ex.criticality}</td><td>{human(ex.exception_type)}</td><td>{ex.description}</td><td><span className="badge">{human(ex.status)}</span></td><td>{ex.status==="open"?<div style={{display:"flex",gap:6,flexWrap:"wrap"}}><button className="btn ghost" type="button" onClick={()=>resolveException(ex.id,"accepted")}>Accept / Track</button><button className="btn ghost" type="button" onClick={()=>resolveException(ex.id,"resolved")}>Resolve</button><button className="btn ghost" type="button" onClick={()=>resolveException(ex.id,"rejected")}>Reject</button></div>:"—"}</td></tr>)}{!state.exceptions.length&&<tr><td colSpan={5} className="subtle">No release exceptions recorded.</td></tr>}</tbody></table></div></section>
  </>;
}
