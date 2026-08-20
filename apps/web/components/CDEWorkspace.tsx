"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { getBrowserSupabaseClient } from "@/lib/supabase-browser";

export type CDEVersion={id:string;version:number;object_key:string;mime_type:string;size_bytes:number;checksum:string;created_at:string};
export type CDEDocument={id:string;document_number:string;title:string;discipline:string;document_type:string;cde_state:string;status:string;revision:string;current_version_id?:string|null;current_version?:CDEVersion|null;updated_at:string};
export type CDEModel={id:string;model_name:string;discipline:string;format:string;schema_version?:string|null;object_key:string;checksum:string;status:string;created_at:string};
export type CDETransmittal={id:string;transmittal_number:string;message?:string|null;issued_at?:string|null;created_at:string;item_count:number};

type Props={projectId:string;documents:CDEDocument[];models:CDEModel[];transmittals:CDETransmittal[]};

function safeName(value:string){return value.normalize("NFKD").replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/-+/g,"-").replace(/^-|-$/g,"").slice(0,120)||"file";}
async function sha256(file:File){const digest=await crypto.subtle.digest("SHA-256",await file.arrayBuffer());return Array.from(new Uint8Array(digest)).map(b=>b.toString(16).padStart(2,"0")).join("");}

export default function CDEWorkspace({projectId,documents,models,transmittals}:Props){
  const supabase=useMemo(()=>getBrowserSupabaseClient(),[]);
  const router=useRouter();
  const [message,setMessage]=useState("");
  const [busy,startTransition]=useTransition();
  const refresh=(text:string)=>{setMessage(text);startTransition(()=>router.refresh());};

  async function registerDocument(formData:FormData){
    setMessage("Registering document and uploading private version…");
    const file=formData.get("file") as File|null;
    if(!file||file.size===0){setMessage("Select a file.");return;}
    const checksum=await sha256(file);
    const {data:documentId,error:docError}=await supabase.rpc("register_cde_document",{input_payload:{project_id:projectId,document_number:String(formData.get("document_number")||""),title:String(formData.get("title")||""),discipline:String(formData.get("discipline")||"GEN"),document_type:String(formData.get("document_type")||"document"),revision:String(formData.get("revision")||"P01"),scale:String(formData.get("scale")||"")}});
    if(docError||!documentId){setMessage(docError?.message||"Document registration failed.");return;}
    const id=String(documentId);
    const objectKey=`${projectId}/documents/${id}/v1/${safeName(file.name)}`;
    const {error:uploadError}=await supabase.storage.from("project-cde").upload(objectKey,file,{upsert:false,contentType:file.type||"application/octet-stream",cacheControl:"3600"});
    if(uploadError){await supabase.rpc("discard_empty_cde_document",{target_document_id:id});setMessage(`Private upload failed and empty document shell was discarded: ${uploadError.message}`);return;}
    const {error:versionError}=await supabase.rpc("register_cde_file_version",{target_document_id:id,object_key:objectKey,mime_type:file.type||"application/octet-stream",size_bytes:file.size,checksum_sha256:checksum});
    if(versionError){await supabase.storage.from("project-cde").remove([objectKey]);await supabase.rpc("discard_empty_cde_document",{target_document_id:id});setMessage(`Version registration failed; storage and empty shell were rolled back: ${versionError.message}`);return;}
    refresh("Document registered with immutable SHA-256 version provenance.");
  }

  async function addVersion(formData:FormData){
    setMessage("Uploading new immutable version…");
    const documentId=String(formData.get("document_id")||"");
    const file=formData.get("file") as File|null;
    const doc=documents.find(d=>d.id===documentId);
    if(!doc||!file||file.size===0){setMessage("Select a document and file.");return;}
    const next=(doc.current_version?.version||0)+1;
    const checksum=await sha256(file);
    const objectKey=`${projectId}/documents/${documentId}/v${next}/${safeName(file.name)}`;
    const {error:uploadError}=await supabase.storage.from("project-cde").upload(objectKey,file,{upsert:false,contentType:file.type||"application/octet-stream",cacheControl:"3600"});
    if(uploadError){setMessage(uploadError.message);return;}
    const {error}=await supabase.rpc("register_cde_file_version",{target_document_id:documentId,object_key:objectKey,mime_type:file.type||"application/octet-stream",size_bytes:file.size,checksum_sha256:checksum});
    if(error){await supabase.storage.from("project-cde").remove([objectKey]);setMessage(`Version metadata failed; object removed: ${error.message}`);return;}
    refresh(`Version ${next} registered.`);
  }

  async function downloadVersion(documentId:string){
    const key=documents.find(d=>d.id===documentId)?.current_version?.object_key;
    if(!key)return;
    setMessage("Preparing authenticated private download…");
    const {data,error}=await supabase.storage.from("project-cde").download(key);
    if(error||!data){setMessage(error?.message||"Download failed.");return;}
    const url=URL.createObjectURL(data);const a=document.createElement("a");a.href=url;a.download=key.split("/").pop()||"document";document.body.appendChild(a);a.click();a.remove();URL.revokeObjectURL(url);setMessage("Private download completed.");
  }

  async function transition(documentId:string,status:string,state:string){
    setMessage("Applying governed CDE transition…");
    const {error}=await supabase.rpc("transition_cde_document",{target_document_id:documentId,target_status:status,target_cde_state:state,evidence_note:"CDE workspace transition"});
    if(error){setMessage(error.message);return;}refresh(`Document moved to ${state} / ${status}.`);
  }

  async function requestApproval(documentId:string){
    const doc=documents.find(d=>d.id===documentId);const hash=doc?.current_version?.checksum;
    if(!doc||!hash){setMessage("A registered file version is required first.");return;}
    const discipline=doc.discipline.toUpperCase();
    const role=discipline.startsWith("STR")?"structural_engineer":discipline.startsWith("MEP")?"mep_engineer":"lead_architect";
    const {error}=await supabase.rpc("request_governed_approval",{input_payload:{project_id:projectId,resource_type:"document",resource_id:documentId,role_required:role,criticality:"C3",comments:`Review exact SHA-256 ${hash}`}});
    if(error){setMessage(error.message);return;}refresh(`C3 ${role} approval requested against the current SHA-256 hash.`);
  }

  async function uploadModel(formData:FormData){
    setMessage("Uploading governed model…");
    const file=formData.get("file") as File|null;if(!file||file.size===0){setMessage("Select a model file.");return;}
    const checksum=await sha256(file);const token=crypto.randomUUID();const objectKey=`${projectId}/models/${token}/${safeName(file.name)}`;
    const {error:uploadError}=await supabase.storage.from("project-cde").upload(objectKey,file,{upsert:false,contentType:file.type||"application/octet-stream"});if(uploadError){setMessage(uploadError.message);return;}
    const format=(file.name.split(".").pop()||"").toLowerCase();
    const {error}=await supabase.rpc("register_cde_model",{input_payload:{project_id:projectId,model_name:String(formData.get("model_name")||file.name),discipline:String(formData.get("discipline")||"GEN"),format,schema_version:String(formData.get("schema_version")||""),coordinate_system:String(formData.get("coordinate_system")||""),object_key:objectKey,checksum}});
    if(error){await supabase.storage.from("project-cde").remove([objectKey]);setMessage(`Model registration failed and upload was rolled back: ${error.message}`);return;}refresh("Model uploaded with SHA-256 provenance.");
  }

  async function createTransmittal(formData:FormData){
    const documentIds=formData.getAll("document_ids").map(String);
    const {data,error}=await supabase.rpc("create_cde_transmittal",{input_payload:{project_id:projectId,transmittal_number:String(formData.get("transmittal_number")||""),message:String(formData.get("message")||""),purpose:String(formData.get("purpose")||"information"),recipient_refs:String(formData.get("recipients")||"").split(",").map(v=>v.trim()).filter(Boolean),acknowledgement_required:formData.get("acknowledgement_required")==="on"},document_ids:documentIds,model_ids:[]});
    if(error){setMessage(error.message);return;}refresh(`Transmittal ${String(data).slice(0,8)} created as draft.`);
  }

  async function issueTransmittal(id:string){const {error}=await supabase.rpc("issue_cde_transmittal",{target_transmittal_id:id});if(error){setMessage(error.message);return;}refresh("Transmittal issued and audit-bound.");}

  return <>
    {message&&<div className="note" style={{marginBottom:16}}><b>System:</b> {message}{busy?" Refreshing…":""}</div>}
    <div className="panel-grid">
      <section className="panel"><h3>Register Document + First Version</h3><form action={registerDocument}><div className="field-grid"><div className="field"><label>Document Number</label><input name="document_number" required placeholder="A-101"/></div><div className="field"><label>Title</label><input name="title" required/></div><div className="field"><label>Discipline</label><input name="discipline" defaultValue="ARCH"/></div><div className="field"><label>Type</label><input name="document_type" defaultValue="drawing"/></div><div className="field"><label>Revision</label><input name="revision" defaultValue="P01"/></div><div className="field"><label>Scale</label><input name="scale" placeholder="1:100"/></div></div><div className="field" style={{marginTop:12}}><label>Private File</label><input name="file" type="file" required/></div><button className="btn" style={{marginTop:14}}>Register & Upload</button></form></section>
      <section className="panel"><h3>Add Version</h3><form action={addVersion}><div className="field"><label>Document</label><select name="document_id" required><option value="">Select</option>{documents.filter(d=>!["published","archived"].includes(d.cde_state)&&!["issued","superseded","withdrawn"].includes(d.status)).map(d=><option key={d.id} value={d.id}>{d.document_number} · {d.revision} · v{d.current_version?.version||0}</option>)}</select></div><div className="field"><label>New File</label><input name="file" type="file" required/></div><button className="btn ghost" style={{marginTop:14}}>Upload New Version</button></form><div className="note"><b>Immutability.</b> Published, archived, issued, superseded and withdrawn records cannot receive a replacement file. A new revision must be registered instead.</div></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Document Register</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Number</th><th>Title</th><th>Discipline</th><th>Revision</th><th>Version</th><th>State</th><th>Status</th><th>Checksum</th><th>Actions</th></tr></thead><tbody>{documents.map(d=><tr key={d.id}><td>{d.document_number}</td><td>{d.title}</td><td>{d.discipline}</td><td>{d.revision}</td><td>v{d.current_version?.version||0}</td><td>{d.cde_state}</td><td><span className="badge">{d.status}</span></td><td style={{fontFamily:"monospace",fontSize:10}}>{d.current_version?.checksum?.slice(0,12)||"—"}</td><td><div style={{display:"grid",gap:5,minWidth:170}}>{d.current_version&&<button className="btn ghost" style={{padding:7}} onClick={()=>downloadVersion(d.id)}>Download</button>}{d.status==="draft"&&d.current_version&&<button className="btn ghost" style={{padding:7}} onClick={()=>transition(d.id,"for_review","shared")}>Share for Review</button>}{d.status==="for_review"&&<button className="btn ghost" style={{padding:7}} onClick={()=>transition(d.id,"for_approval","shared")}>Move for Approval</button>}{d.status==="for_approval"&&<button className="btn ghost" style={{padding:7}} onClick={()=>requestApproval(d.id)}>Request C3 Approval</button>}{d.status==="for_approval"&&<button className="btn" style={{padding:7}} onClick={()=>transition(d.id,"issued","published")}>Publish Exact Approved Hash</button>}</div></td></tr>)}{documents.length===0&&<tr><td colSpan={9} className="subtle">No CDE documents registered for this project.</td></tr>}</tbody></table></div></section>

    <div className="panel-grid">
      <section className="panel"><h3>Models</h3><form action={uploadModel}><div className="field-grid"><div className="field"><label>Model Name</label><input name="model_name" required/></div><div className="field"><label>Discipline</label><input name="discipline" defaultValue="ARCH"/></div><div className="field"><label>Schema Version</label><input name="schema_version" placeholder="IFC 4.3"/></div><div className="field"><label>Coordinate System</label><input name="coordinate_system" placeholder="EPSG / project local"/></div></div><div className="field"><label>Model File</label><input type="file" name="file" accept=".ifc,.dwg,.dxf,.rvt,.nwd,.nwc,.pdf,.gbxml,.json" required/></div><button className="btn" style={{marginTop:12}}>Upload Model</button></form><table className="table"><thead><tr><th>Model</th><th>Discipline</th><th>Format</th><th>Status</th></tr></thead><tbody>{models.map(m=><tr key={m.id}><td>{m.model_name}</td><td>{m.discipline}</td><td>{m.format.toUpperCase()}</td><td>{m.status}</td></tr>)}{models.length===0&&<tr><td colSpan={4} className="subtle">No models registered.</td></tr>}</tbody></table></section>
      <section className="panel"><h3>Create Transmittal</h3><form action={createTransmittal}><div className="field"><label>Reference</label><input name="transmittal_number" placeholder="TR-001"/></div><div className="field"><label>Recipients</label><input name="recipients" placeholder="client@example.com, reviewer@example.com"/></div><div className="field"><label>Purpose</label><select name="purpose" defaultValue="information"><option value="information">Information</option><option value="review">Review</option><option value="approval">Approval</option><option value="construction">Construction</option><option value="record">Record</option></select></div><div className="field"><label>Message</label><textarea name="message"/></div><label className="subtle"><input type="checkbox" name="acknowledgement_required"/> Acknowledgement required</label><div style={{marginTop:10}}>{documents.filter(d=>["shared","published"].includes(d.cde_state)&&d.current_version).map(d=><label key={d.id} style={{display:"block",fontSize:12,padding:"4px 0"}}><input type="checkbox" name="document_ids" value={d.id}/> {d.document_number} · {d.revision} · v{d.current_version?.version}</label>)}</div><button className="btn" style={{marginTop:12}}>Create Draft Transmittal</button></form></section>
    </div>

    <section className="panel" style={{marginTop:16}}><h3>Transmittal Register</h3><table className="table"><thead><tr><th>Reference</th><th>Items</th><th>Created</th><th>Issued</th><th>Action</th></tr></thead><tbody>{transmittals.map(t=><tr key={t.id}><td>{t.transmittal_number}</td><td>{t.item_count}</td><td>{new Date(t.created_at).toLocaleString("en-IN")}</td><td>{t.issued_at?new Date(t.issued_at).toLocaleString("en-IN"):"Draft"}</td><td>{!t.issued_at&&<button className="btn ghost" style={{padding:7}} onClick={()=>issueTransmittal(t.id)}>Issue</button>}</td></tr>)}{transmittals.length===0&&<tr><td colSpan={5} className="subtle">No transmittals.</td></tr>}</tbody></table></section>
  </>;
}
