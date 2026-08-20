import Link from "next/link";
import { DEMO_PROJECTS } from "@/lib/demo-data";

const gates=[
  ["GATE-SITE-01","Verified Site Truth","Architecture","C3","Blocked","Survey + jurisdiction evidence","0 critical defects"],
  ["GATE-CONCEPT-01","Concept Issue","Architecture","C2","Not ready","Truth snapshot + client decision","0 critical defects"],
  ["GATE-STR-01","Structural Design Issue","Structure","C4","Not ready","Engineering check + credentialed sign-off","0 critical defects"],
  ["GATE-MEP-01","MEPF Coordination Issue","MEPF","C4","Not ready","Engineering + coordination + sign-off","0 critical defects"],
  ["GATE-IFC-01","Issued for Construction","Integrated","C4","Not ready","All discipline gates + document hashes","0 critical defects"]
];

export default async function Releases({params}:{params:Promise<{projectId:string}>}){
  const {projectId}=await params;
  const project=DEMO_PROJECTS.find(p=>p.id===projectId) ?? DEMO_PROJECTS[0];
  return <>
    <div className="topbar"><div><div className="demo">Proof Before Publish / Illustrative</div><h1>Release Safety Cases</h1><div className="subtle">A release is an evidence-backed state transition, not a file export.</div></div><Link className="btn ghost" href={`/app/projects/${project.id}`}>Back to Project</Link></div>
    <div className="panel"><h3>Release Gates</h3><table className="table"><thead><tr><th>Gate</th><th>Name</th><th>Discipline</th><th>Criticality</th><th>State</th><th>Required evidence</th><th>Defect rule</th></tr></thead><tbody>{gates.map(row=><tr key={row[0]}><td><code>{row[0]}</code></td><td>{row[1]}</td><td>{row[2]}</td><td><span className="badge">{row[3]}</span></td><td>{row[4]}</td><td>{row[5]}</td><td>{row[6]}</td></tr>)}</tbody></table></div>
    <div className="grid-3" style={{marginTop:18}}><div className="card"><div className="eyebrow">01 / Truth</div><h3>Canonical snapshot</h3><p>The release records which version of facts, assumptions, decisions, requirements and rules it relied on.</p></div><div className="card"><div className="eyebrow">02 / Verification</div><h3>Machine evidence</h3><p>Deterministic checks, coordination results, document hashes and rule evaluations become immutable evidence.</p></div><div className="card"><div className="eyebrow">03 / Authority</div><h3>Human accountability</h3><p>C3/C4 issue authority requires the configured professional credential and explicit approval event.</p></div></div>
  </>;
}
