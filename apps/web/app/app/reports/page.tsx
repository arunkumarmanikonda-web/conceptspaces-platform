import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import ReportGenerator,{type GeneratedArtifact} from "@/components/ReportGenerator";

export const dynamic="force-dynamic";
type Project={id:string;code:string;name:string};

export default async function ReportsPage({searchParams}:{searchParams:Promise<{project?:string}>}){
  const {supabase}=await requireWorkspaceUser();
  const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);
  const projects=(projectData||[]) as Project[];const params=await searchParams;const selected=projects.find(p=>p.id===params.project)||projects[0];
  let artifacts:GeneratedArtifact[]=[];
  if(selected){const {data,error}=await supabase.rpc("list_project_generated_artifacts",{target_project_id:selected.id});if(error)throw new Error(error.message);artifacts=(data||[]) as GeneratedArtifact[];}
  return <>
    <div className="topbar"><div><div className="demo">Live Project Intelligence / Reporting</div><h1>Governed Reports</h1><div className="subtle">PDF · Word · Excel · PowerPoint · HTML · CSV · JSON generated from immutable project snapshots</div></div></div>
    <div className="grid-3"><div className="card"><div className="eyebrow">Snapshot</div><h3>Project Truth</h3><p>Facts, assumptions, decisions, requirements, regulatory findings and CDE state are frozen before generation.</p></div><div className="card"><div className="eyebrow">Template</div><h3>Version Locked</h3><p>The runtime template is checksum-locked and recorded against every generation job.</p></div><div className="card"><div className="eyebrow">Provenance</div><h3>Two Hashes</h3><p>Input snapshot SHA-256 and output binary SHA-256 are independently recorded for reproducibility.</p></div></div>
    <section className="panel" style={{marginTop:18}}><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link className={selected?.id===p.id?"btn":"btn ghost"} style={{padding:"9px 12px"}} key={p.id} href={`/app/reports?project=${p.id}`}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">Create an accessible project before generating controlled reports.</div>}</section>
    {selected&&<ReportGenerator projectId={selected.id} artifacts={artifacts}/>} 
  </>;
}
