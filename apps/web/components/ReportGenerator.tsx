"use client";

import { useMemo,useState,useTransition } from "react";
import { useRouter } from "next/navigation";
import { getBrowserSupabaseClient } from "@/lib/supabase-browser";

export type GeneratedArtifact={id:string;title:string;output_format:string;object_ref:string;checksum:string;status:string;revision:string;source_snapshot_id:string;created_at:string};

type Props={projectId:string;artifacts:GeneratedArtifact[]};

export default function ReportGenerator({projectId,artifacts}:Props){
  const supabase=useMemo(()=>getBrowserSupabaseClient(),[]);const router=useRouter();const [message,setMessage]=useState("");const [busy,startTransition]=useTransition();
  async function generate(formData:FormData){
    setMessage("Freezing project snapshot and generating controlled artifact…");
    const res=await fetch("/api/reports/generate",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({project_id:projectId,report_type:String(formData.get("report_type")||"project_report"),output_format:String(formData.get("output_format")||"pdf")})});
    const result=await res.json() as {error?:string;artifact_id?:string;output_hash?:string};
    if(!res.ok){setMessage(result.error||"Generation failed.");return;}
    setMessage(`Artifact ${result.artifact_id?.slice(0,8)} generated. Output SHA-256 ${result.output_hash?.slice(0,16)}…`);startTransition(()=>router.refresh());
  }
  async function download(a:GeneratedArtifact){setMessage("Preparing authenticated private download…");const {data,error}=await supabase.storage.from("project-cde").download(a.object_ref);if(error||!data){setMessage(error?.message||"Download failed.");return;}const url=URL.createObjectURL(data);const link=document.createElement("a");link.href=url;link.download=a.object_ref.split("/").pop()||`report.${a.output_format}`;document.body.appendChild(link);link.click();link.remove();URL.revokeObjectURL(url);setMessage("Download completed.");}
  return <>
    {message&&<div className="note" style={{marginTop:16}}><b>Generator:</b> {message}{busy?" Refreshing…":""}</div>}
    <div className="panel-grid">
      <section className="panel"><h3>Generate Snapshot-Bound Artifact</h3><form action={generate}><div className="field-grid"><div className="field"><label>Report Type</label><select name="report_type" defaultValue="project_report"><option value="project_report">Project Intelligence Report</option><option value="design_report">Design Report</option><option value="feasibility_report">Feasibility Report</option><option value="client_presentation">Client Presentation</option><option value="drawing_register">Drawing Register</option><option value="progress_report">Progress Report</option><option value="handover_pack">Handover Pack</option></select></div><div className="field"><label>Output</label><select name="output_format" defaultValue="pdf"><option value="pdf">PDF</option><option value="docx">Word DOCX</option><option value="xlsx">Excel XLSX</option><option value="pptx">PowerPoint PPTX</option><option value="html">HTML</option><option value="csv">CSV</option><option value="json">JSON Snapshot</option></select></div></div><button className="btn" style={{marginTop:14}}>Generate Controlled Artifact</button></form></section>
      <section className="panel"><h3>Generation Contract</h3><p className="subtle">Every output freezes Project Truth, requirements, REGULA findings, commercial state and CDE registers before rendering. The input snapshot and final binary each receive separate SHA-256 hashes.</p><div className="note"><b>No silent regeneration.</b> A later project change does not alter an existing artifact. Generate a new snapshot and revision.</div></section>
    </div>
    <section className="panel" style={{marginTop:16}}><h3>Generated Artifacts</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Title</th><th>Format</th><th>Revision</th><th>Status</th><th>Output Hash</th><th>Created</th><th></th></tr></thead><tbody>{artifacts.map(a=><tr key={a.id}><td>{a.title}</td><td>{a.output_format.toUpperCase()}</td><td>{a.revision}</td><td><span className="badge">{a.status}</span></td><td style={{fontFamily:"monospace",fontSize:10}}>{a.checksum.slice(0,16)}…</td><td>{new Date(a.created_at).toLocaleString("en-IN")}</td><td><button className="btn ghost" style={{padding:7}} onClick={()=>download(a)}>Download</button></td></tr>)}{artifacts.length===0&&<tr><td colSpan={7} className="subtle">No generated artifacts for this project yet.</td></tr>}</tbody></table></div></section>
  </>;
}
