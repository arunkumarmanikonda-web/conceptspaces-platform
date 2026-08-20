import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import CDEWorkspace from "@/components/CDEWorkspace";

export const dynamic="force-dynamic";

type Project={id:string;code:string;name:string};
type CDEData={documents?:Array<Record<string,unknown>>;models?:Array<Record<string,unknown>>;transmittals?:Array<Record<string,unknown>>};

export default async function DocumentsPage({searchParams}:{searchParams:Promise<{project?:string}>}){
  const {supabase}=await requireWorkspaceUser();
  const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
  if(projectError) throw new Error(projectError.message);
  const projects=(projectData||[]) as Project[];
  const params=await searchParams;
  const selected=projects.find(p=>p.id===params.project)||projects[0];
  let cde:CDEData={documents:[],models:[],transmittals:[]};
  if(selected){
    const {data,error}=await supabase.rpc("list_project_cde",{target_project_id:selected.id});
    if(error) throw new Error(error.message);
    cde=(data||{}) as CDEData;
  }
  const documents=(cde.documents||[]) as never[];
  const models=(cde.models||[]) as never[];
  const transmittals=(cde.transmittals||[]) as never[];
  const review=documents.filter((d:{status:string})=>d.status==="for_review").length;
  const approval=documents.filter((d:{status:string})=>d.status==="for_approval").length;
  const issued=documents.filter((d:{status:string})=>d.status==="issued").length;
  const superseded=documents.filter((d:{status:string})=>d.status==="superseded").length;

  return <>
    <div className="topbar"><div><div className="demo">Live Common Data Environment</div><h1>Documents, Models & Transmittals</h1><div className="subtle">Private project storage · immutable SHA-256 versions · WIP → Shared → Published → Archived</div></div></div>
    <div className="kpis">{[["Registered",String(documents.length)],["For Review",String(review)],["For Approval",String(approval)],["Issued",String(issued)],["Superseded",String(superseded)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live project state</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Project CDE</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link className={selected?.id===p.id?"btn":"btn ghost"} style={{padding:"9px 12px"}} key={p.id} href={`/app/documents?project=${p.id}`}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet. Create a project through Project Setup before registering controlled information.</div>}</section>
    {selected&&<CDEWorkspace projectId={selected.id} documents={documents} models={models} transmittals={transmittals}/>} 
  </>;
}
