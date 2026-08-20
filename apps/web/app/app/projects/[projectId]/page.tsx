import Link from "next/link";
import { DEMO_PROJECTS, DEMO_TRUTH } from "@/lib/demo-data";

export default async function ProjectWorkspace({params}:{params:Promise<{projectId:string}>}){
  const {projectId}=await params;
  const project=DEMO_PROJECTS.find(p=>p.id===projectId) ?? DEMO_PROJECTS[0];
  return <>
    <div className="topbar"><div><div className="demo">Demonstration Project</div><h1>{project.name}</h1><div className="subtle">{project.code} • {project.typology} • {project.location}</div></div><span className="badge">Criticality {project.criticality}</span></div>
    <div className="kpis">
      <div className="kpi"><div className="label">Project Truth Health</div><div className="value">{project.truthHealth}%</div><div className="subtle">Illustrative</div></div>
      <div className="kpi"><div className="label">Stage</div><div className="value" style={{fontSize:22}}>{project.stage.replaceAll('_',' ')}</div><div className="subtle">Current lifecycle state</div></div>
      <div className="kpi"><div className="label">Open Issues</div><div className="value">{project.openIssues}</div><div className="subtle">Requires coordination</div></div>
      <div className="kpi"><div className="label">Pending Decisions</div><div className="value">{project.pendingDecisions}</div><div className="subtle">Owner / professional action</div></div>
      <div className="kpi"><div className="label">Critical Escapes</div><div className="value">0</div><div className="subtle">Zero permitted</div></div>
    </div>
    <div className="grid-3" style={{marginTop:18}}>
      <Link className="card" href={`/app/projects/${project.id}/truth`}><div className="eyebrow">Project Truth™</div><h3>Facts, assumptions and decisions</h3><p>See source, confidence, verification state and downstream impact before design depends on an input.</p></Link>
      <Link className="card" href={`/app/projects/${project.id}/requirements`}><div className="eyebrow">Traceability™</div><h3>Requirements</h3><p>Track every client promise, statutory requirement and technical criterion from brief to acceptance.</p></Link>
      <Link className="card" href={`/app/projects/${project.id}/releases`}><div className="eyebrow">Proof Before Publish</div><h3>Release Gates</h3><p>Issue only when required evidence, professional authority and zero-critical-defect rules are satisfied.</p></Link>
    </div>
    <div className="panel-grid"><section className="panel"><h3>Current Project Truth Snapshot</h3><table className="table"><thead><tr><th>Record</th><th>Value</th><th>Confidence</th><th>Source</th></tr></thead><tbody>{DEMO_TRUTH.map(row=><tr key={row.key}><td>{row.label}</td><td>{row.value}</td><td><span className="badge">{row.confidence}</span></td><td>{row.source}</td></tr>)}</tbody></table></section><section className="panel"><h3>Ask Your Project™</h3><p className="subtle">Grounded project assistant will answer only from accessible project records, evidence and approved knowledge. Unknowns remain explicitly unknown.</p><div className="note">Example: “Which assumptions currently affect buildable area?”</div></section></div>
  </>;
}
