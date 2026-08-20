import Link from "next/link";

export default function Projects(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>Projects</h1><div className="subtle">One governed record per project</div></div><Link className="btn" href="/app/projects/new">Create Project</Link></div>
    <div className="panel"><h3>Portfolio</h3><table className="table"><thead><tr><th>Project</th><th>Type</th><th>Stage</th><th>Truth State</th><th>Lead Architect</th></tr></thead><tbody><tr><td>CS-DEMO-001 / Hospitality Feasibility</td><td>Hotel</td><td>Concept</td><td><span className="badge">B — system validated</span></td><td>Unassigned</td></tr><tr><td>CS-DEMO-002 / Mixed Use Study</td><td>Mixed Use</td><td>Site Truth</td><td><span className="badge">D — inputs pending</span></td><td>Unassigned</td></tr></tbody></table></div>
  </>;
}
