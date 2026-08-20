import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";

type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string;lead_architect_user_id:string|null;created_at:string};

export default async function Projects(){
  const { supabase }=await requireWorkspaceUser();
  const { data,error }=await supabase.rpc("list_accessible_projects");
  if(error) throw new Error(`Unable to load projects: ${error.message}`);
  const projects=(data||[]) as ProjectRow[];

  return <>
    <div className="topbar"><div><div className="demo">Live Supabase Workspace</div><h1>Projects</h1><div className="subtle">Governed project records visible through your organisation/project authority.</div></div><Link className="btn" href="/app/projects/new">Create Project</Link></div>
    <div className="panel"><h3>Portfolio</h3>
      {projects.length?<table className="table"><thead><tr><th>Project</th><th>Type</th><th>Stage</th><th>Criticality</th><th>Status</th></tr></thead><tbody>{projects.map(project=><tr key={project.id}><td><b>{project.code}</b> / {project.name}</td><td>{project.typology}</td><td>{project.stage}</td><td><span className="badge">{project.criticality}</span></td><td>{project.status}</td></tr>)}</tbody></table>:<div className="note"><b>No governed projects yet.</b> Create the first project through the guided intake. Once submitted it will persist here immediately.</div>}
    </div>
  </>;
}
