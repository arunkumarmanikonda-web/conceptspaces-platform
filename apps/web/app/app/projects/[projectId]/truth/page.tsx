import Link from "next/link";
import { DEMO_PROJECTS, DEMO_TRUTH } from "@/lib/demo-data";

const blast=[
  ["planning.far","Massing options, sellable area, parking demand, development economics","High"],
  ["site.area","Coverage, setbacks, FAR area, landscape, fire access","High"],
  ["site.location","Climate, jurisdiction, airport height screening, environmental overlays","Critical"]
];

export default async function TruthLedger({params}:{params:Promise<{projectId:string}>}){
  const {projectId}=await params;
  const project=DEMO_PROJECTS.find(p=>p.id===projectId) ?? DEMO_PROJECTS[0];
  return <>
    <div className="topbar"><div><div className="demo">Project Truth™ / Illustrative</div><h1>Truth & Assumption Ledger</h1><div className="subtle">{project.code} • No silent assumptions</div></div><Link className="btn ghost" href={`/app/projects/${project.id}`}>Back to Project</Link></div>
    <div className="panel"><h3>Canonical Records</h3><table className="table"><thead><tr><th>Key</th><th>Record</th><th>Value</th><th>Grade</th><th>Status</th><th>Source</th></tr></thead><tbody>{DEMO_TRUTH.map(row=><tr key={row.key}><td><code>{row.key}</code></td><td>{row.label}</td><td>{row.value}</td><td><span className="badge">{row.confidence}</span></td><td>{row.status}</td><td>{row.source}</td></tr>)}</tbody></table></div>
    <div className="panel-grid"><section className="panel"><h3>Assumption Expiry</h3><p className="subtle">Every assumption carries an owner, confidence grade, expiry/verification trigger and affected downstream objects. Expired assumptions block governed releases when their criticality requires it.</p><div className="note"><b>planning.height</b><br/>Not verified. Authority/airport screening source required before height-dependent design can progress to an issued state.</div></section><section className="panel"><h3>Confidence Scale</h3><table className="table"><tbody><tr><td>A</td><td>Professionally approved / verified</td></tr><tr><td>B</td><td>System validated, human approval pending</td></tr><tr><td>C</td><td>Conceptual / preliminary</td></tr><tr><td>D</td><td>Insufficient source or verification</td></tr></tbody></table></section></div>
    <div className="panel" style={{marginTop:16}}><h3>Dependency & Blast Radius</h3><table className="table"><thead><tr><th>Input</th><th>Downstream impact</th><th>Impact</th></tr></thead><tbody>{blast.map(row=><tr key={row[0]}><td><code>{row[0]}</code></td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td></tr>)}</tbody></table></div>
  </>;
}
