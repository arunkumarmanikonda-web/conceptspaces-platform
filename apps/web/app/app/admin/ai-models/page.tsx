const purposes=[
  ["Orchestration","System task routing, tool selection and workflow planning","AI draft","C0–C2"],
  ["Reasoning","Design analysis, comparison, requirements and project Q&A","AI draft","C0–C3 advisory"],
  ["Vision","Drawing, image and site-evidence interpretation","AI draft","C0–C3 advisory"],
  ["Speech","Architect voice-to-intent transcription and structured commands","Execute after approval","C0–C2"],
  ["Embedding","Project knowledge retrieval and semantic search","Bounded autonomous","C0–C3"],
  ["Rendering","Conceptual visualisation and design communication","AI draft","C0–C2"],
  ["Document","Briefs, reports, schedules and structured extraction","AI draft","C0–C3 advisory"],
  ["Code","Internal automation and system engineering","Execute after approval","Internal"]
];

export default function AiModels(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / AI Governance</div><h1>Model Registry</h1><div className="subtle">Provider-neutral routing by purpose, risk, data classification and maximum autonomy.</div></div><button className="btn">Register Model</button></div>
    <div className="panel"><h3>AI Capability Profiles</h3><table className="table"><thead><tr><th>Purpose</th><th>Permitted use</th><th>Maximum autonomy</th><th>Criticality envelope</th></tr></thead><tbody>{purposes.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td></tr>)}</tbody></table></div>
    <div className="panel-grid"><section className="panel"><h3>No-Hallucination Zones</h3><p className="subtle">Regulatory applicability, engineering calculations, quantities, BOQ financial totals, invoice posting, payment release and contract execution must return <b>Not Verified</b> when the required deterministic source or authority is unavailable.</p></section><section className="panel"><h3>C4 Policy</h3><p className="subtle">No model, regardless of provider or benchmark score, may autonomously issue life-safety/statutory-critical work. C4 AI remains assistive and evidence-producing.</p></section></div>
  </>;
}
