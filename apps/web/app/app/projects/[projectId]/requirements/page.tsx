import Link from "next/link";
import { DEMO_PROJECTS } from "@/lib/demo-data";

const requirements=[
  ["REQ-001","Owner","Hotel programme","Provide 120 keys including accessible inventory","Open","C2"],
  ["REQ-002","Planning","Site","Respect verified setbacks and buildable envelope","Blocked by source","C3"],
  ["REQ-003","Life Safety","Fire","Fire access and egress must pass applicable authority rule set","Open","C4"],
  ["REQ-004","Commercial","Yield","Compare development yield against owner target","Open","C1"],
  ["REQ-005","Sustainability","Energy","Evaluate applicable energy-code requirements and passive strategies","Open","C2"]
];

export default async function Requirements({params}:{params:Promise<{projectId:string}>}){
  const {projectId}=await params;
  const project=DEMO_PROJECTS.find(p=>p.id===projectId) ?? DEMO_PROJECTS[0];
  return <>
    <div className="topbar"><div><div className="demo">Requirements Traceability™ / Illustrative</div><h1>Requirements Register</h1><div className="subtle">Every promise and constraint must reach a verifiable acceptance condition.</div></div><Link className="btn ghost" href={`/app/projects/${project.id}`}>Back to Project</Link></div>
    <div className="kpis"><div className="kpi"><div className="label">Total Requirements</div><div className="value">05</div></div><div className="kpi"><div className="label">Satisfied</div><div className="value">00</div></div><div className="kpi"><div className="label">Blocked</div><div className="value">01</div></div><div className="kpi"><div className="label">C4 Life Safety</div><div className="value">01</div></div><div className="kpi"><div className="label">Untraceable</div><div className="value">00</div></div></div>
    <div className="panel" style={{marginTop:16}}><h3>Traceability Matrix</h3><table className="table"><thead><tr><th>Code</th><th>Category</th><th>Source</th><th>Requirement</th><th>Status</th><th>Criticality</th></tr></thead><tbody>{requirements.map(row=><tr key={row[0]}><td><code>{row[0]}</code></td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td>{row[4]}</td><td><span className="badge">{row[5]}</span></td></tr>)}</tbody></table></div>
    <div className="note"><b>Release rule:</b> C3/C4 requirements cannot be marked satisfied by an AI assertion. Satisfaction requires the configured evidence class and appropriate professional authority.</div>
  </>;
}
