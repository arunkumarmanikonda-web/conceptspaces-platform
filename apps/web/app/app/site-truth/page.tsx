import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import SiteGeometryClient,{type GeometryRow} from "@/components/SiteGeometryClient";
import ProjectTruthClient,{type TruthRow} from "@/components/ProjectTruthClient";

export const dynamic="force-dynamic";
type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
export default async function SiteTruthPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as ProjectRow[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let truth:TruthRow[]=[];let geometries:GeometryRow[]=[];
 if(project){const [{data:t,error:te},{data:g,error:ge}]=await Promise.all([supabase.rpc("list_project_truth_state",{target_project_id:project.id}),supabase.rpc("list_project_site_geometry",{target_project_id:project.id})]);if(te)throw new Error(te.message);if(ge)throw new Error(ge.message);truth=(t||[]) as TruthRow[];geometries=(g||[]) as GeometryRow[];}
 const verified=truth.filter(t=>t.status==="verified").length,assumptions=truth.filter(t=>t.kind==="assumption").length,unknowns=truth.filter(t=>t.status!=="verified"&&(t.criticality==="C2"||t.criticality==="C3"||t.criticality==="C4")).length;const latestGeometry=geometries[0];
 return <>
  <div className="topbar"><div><div className="demo">Project Truth / Site</div><h1>Site Truth + Precision Geometry</h1><div className="subtle">Verified facts, declared inputs, immutable parcel evidence and professional geometry authority.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/site-truth?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet. Create a project through the governed intake.</div>}</section>
  {project&&<><div className="kpis" style={{marginTop:16}}>{[["Verified Facts",String(verified)],["Assumptions",String(assumptions)],["Critical Unknowns",String(unknowns)],["Geometry Evidence",String(geometries.length)],["Geometry State",latestGeometry?latestGeometry.verification.replaceAll("_"," "):"Not verified"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:l==="Geometry State"?18:34}}>{v}</div><div className="subtle">Live database</div></div>)}</div>
  <div style={{marginTop:18}}><ProjectTruthClient projectId={project.id} rows={truth}/></div>
  <div style={{marginTop:18}}><SiteGeometryClient projectId={project.id} rows={geometries}/></div></>}
 </>;
}
