"use client";
import Link from "next/link";
import {useState,useTransition} from "react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase";

export type AskProjectRef={id:string;code:string;name:string;access_mode?:"internal"|"client"};
type Citation={domain:string;resource_type:string;resource_id:string;label:string;status?:string;confidence?:string;hash?:string|null;summary?:string};
type AskResult={conversation_id:string;message_id:string;answer:string;citations:Citation[];confidence:string;response_status:string};

const pretty=(v?:string|null)=>v?v.replaceAll("_"," "):"—";
const shortHash=(v?:string|null)=>v?`${v.slice(0,12)}…`:"—";

export default function AskProjectWorkspaceClient({projects,projectId,basePath}:{projects:AskProjectRef[];projectId?:string;basePath:string}){
 const supabase=createClient();const router=useRouter();const [question,setQuestion]=useState("");const [result,setResult]=useState<AskResult|null>(null);const [message,setMessage]=useState("");const [busy,startTransition]=useTransition();
 const project=projects.find(p=>p.id===projectId)||projects[0];
 async function ask(){
  if(!project||!question.trim())return;
  setMessage("");
  const {data,error}=await supabase.rpc("ask_project_grounded",{target_project_id:project.id,target_question:question.trim(),target_conversation_id:result?.conversation_id||null});
  if(error){setMessage(error.message);return;}
  setResult(data as AskResult);setQuestion("");
 }
 async function flag(){
  if(!result)return;
  const reason=window.prompt("Why should this grounded answer be reviewed?");if(!reason?.trim())return;
  const {error}=await supabase.rpc("flag_project_answer",{target_message_id:result.message_id,target_reason:reason.trim()});
  if(error){setMessage(error.message);return;}setMessage("Answer flagged for review with an auditable reason.");
 }
 function changeProject(id:string){setResult(null);setQuestion("");startTransition(()=>router.push(`${basePath}?project=${id}`));}
 return <>
  {message&&<div className="note" style={{marginBottom:16}}><b>Ask Your Project:</b> {message}</div>}
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><button key={p.id} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}} disabled={busy} onClick={()=>changeProject(p.id)}>{p.code} · {p.name}</button>)}</div>{projects.length===0&&<div className="note">No authorised project is available to this identity.</div>}</section>
  {project&&<>
   <div className="topbar" style={{marginTop:18}}><div><div className="demo">Ask Your Project™ / Grounded Runtime</div><h1>{project.name}</h1><div className="subtle">Answers are generated only from authorised Project Graph records and always return source citations. Missing evidence returns Not Verified.</div></div><Link className="btn ghost" href={basePath.startsWith("/client")?`/client?project=${project.id}`:"/app/client-portal?project="+project.id}>Project Portal</Link></div>
   <div className="panel-grid">
    <section className="panel"><h3>Ask</h3><div className="field"><label>Question</label><textarea rows={7} value={question} onChange={e=>setQuestion(e.target.value)} placeholder="What is blocking the next release? What changed this week? Which decisions are overdue?"/></div><button className="btn" disabled={!question.trim()} onClick={ask}>Run Grounded Query</button></section>
    <section className="panel"><h3>Answer Policy</h3><p className="subtle">The runtime resolves your authenticated project permissions first, then searches only authorised records. Client users never receive internal WIP, unshared documents, hidden risks or masked commercial data. C3/C4 answers remain informational and never constitute professional approval.</p><div className="note"><b>Proof Before Publish:</b> when evidence is absent or insufficient, the answer states <b>Not Verified</b> rather than inferring a fact.</div></section>
   </div>
   <section className="panel"><h3>Grounded Answer</h3>{result?<><div className="note" style={{marginTop:0}}><b>{pretty(result.response_status)}</b> · confidence {result.confidence}</div><p style={{fontSize:18,lineHeight:1.65}}>{result.answer}</p><div style={{display:"flex",gap:8,flexWrap:"wrap"}}><button className="btn ghost" onClick={flag}>Flag Answer</button><button className="btn ghost" onClick={()=>{setResult(null);setQuestion("");}}>New Conversation</button></div></>:<div className="subtle">No answer yet. The workspace remains empty rather than displaying illustrative evidence.</div>}</section>
   <section className="panel"><h3>Evidence Citations</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Domain</th><th>Resource</th><th>Status</th><th>Confidence</th><th>Hash</th><th>Evidence summary</th></tr></thead><tbody>{(result?.citations||[]).map((c,i)=><tr key={`${c.resource_type}-${c.resource_id}-${i}`}><td>{pretty(c.domain)}</td><td><b>{c.label}</b><div className="subtle">{c.resource_type} · {c.resource_id.slice(0,8)}</div></td><td><span className="badge">{pretty(c.status)}</span></td><td>{c.confidence||"—"}</td><td><code>{shortHash(c.hash)}</code></td><td>{c.summary||"—"}</td></tr>)}{(!result||result.citations.length===0)&&<tr><td colSpan={6} className="subtle">No citations yet.</td></tr>}</tbody></table></div></section>
  </>}
 </>;
}
