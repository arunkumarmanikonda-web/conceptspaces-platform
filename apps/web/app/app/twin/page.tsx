import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import TwinOperationsClient from "@/components/TwinOperationsClient";
import {emptyHandoverWorkspace,type HandoverWorkspaceState,type ProjectRow} from "@/components/lifecycle-runtime-types";

export const dynamic="force-dynamic";

export default async function TwinPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
 if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ProjectRow[];
 const params=await searchParams;
 const project=projects.find(p=>p.id===params.project)||projects[0];
 let state:HandoverWorkspaceState=emptyHandoverWorkspace;
 if(project){const {data,error}=await supabase.rpc("list_handover_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyHandoverWorkspace) as HandoverWorkspaceState;}
 return <>
  <div className="topbar"><div><div className="demo">Handover / Building Passport / Digital Twin</div><h1>Operate</h1><div className="subtle">Mandatory handover evidence, asset and material passports, commissioning, immutable Building Passport issuance, maintenance and governed digital-twin bindings.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/twin?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<div style={{marginTop:16}}><TwinOperationsClient projectId={project.id} state={state}/></div>}
 </>;
}
