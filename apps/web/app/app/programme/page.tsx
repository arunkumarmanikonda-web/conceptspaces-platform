import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import {ProgrammeWorkspaceClient} from "@/components/PlanningIntelligenceClients";
import {emptyProgrammeWorkspace,type ProgrammeWorkspaceState,type DesignProject} from "@/components/design-domain-runtime-types";

export const dynamic="force-dynamic";
export default async function ProgrammePage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as DesignProject[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state:ProgrammeWorkspaceState=emptyProgrammeWorkspace;
 if(project){const {data,error}=await supabase.rpc("list_programme_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyProgrammeWorkspace) as ProgrammeWorkspaceState;}
 return <><div className="topbar"><div><div className="demo">Programme Builder / Requirements Trace</div><h1>Programme Intelligence</h1><div className="subtle">Versioned spatial programme, operational logic, source confidence and requirement traceability.</div></div></div><section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/programme?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{!project&&<div className="note">No accessible project exists yet.</div>}</section>{project&&<ProgrammeWorkspaceClient projectId={project.id} state={state}/>}<div className="note"><b>Programme rule.</b> Benchmarks and typology precedent may inform a draft, but only source-linked programme items approved as a versioned baseline become project authority.</div></>;
}