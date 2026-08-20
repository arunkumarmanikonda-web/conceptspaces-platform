import Link from "next/link";
import { DEMO_PROJECTS } from "@/lib/demo-data";

export default function Projects(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>Projects</h1><div className="subtle">One governed record per project</div></div><Link className="btn" href="/app/projects/new">Create Project</Link></div>
    <div className="panel"><h3>Portfolio</h3><table className="table"><thead><tr><th>Project</th><th>Type</th><th>Stage</th><th>Truth State</th><th>Open Issues</th></tr></thead><tbody>{DEMO_PROJECTS.map(project=><tr key={project.id}><td><Link href={`/app/projects/${project.id}`}><b>{project.code}</b> / {project.name}</Link></td><td>{project.typology}</td><td>{project.stage.replaceAll('_',' ')}</td><td><span className="badge">{project.truthHealth}% truth health</span></td><td>{project.openIssues}</td></tr>)}</tbody></table></div>
  </>;
}
