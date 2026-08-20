const agents=[
  ["project-intake","Project Intake Orchestrator","C2","AI Draft","Enabled"],
  ["regula-review","Regulatory Review Agent","C3","AI Advisory","Enabled"],
  ["design-review","Adversarial Design Review","C3","AI Advisory","Enabled"],
  ["release-check","Release Safety Case Reviewer","C4","Human Only","Enabled"],
  ["commercial-assist","Commercial Drafting Agent","C2","Execute after approval","Enabled"]
];

export default function AIControlPage(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / AI Governance</div><h1>AI Control Plane</h1><div className="subtle">Models, agents, prompts, tools, evaluations, cost, autonomy and learning promotion</div></div><button className="btn">Run Evaluation Suite</button></div>
    <div className="kpis">{[["Enabled Agents","38"],["Model Profiles","06"],["Eval Pass Rate","98.7%"],["C3/C4 Autonomous","00"],["Learning Candidates","12"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>7?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Agent Authority Registry</h3><table className="table"><thead><tr><th>Code</th><th>Purpose</th><th>Max Criticality</th><th>Autonomy</th><th>Status</th></tr></thead><tbody>{agents.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
    <div className="grid-3"><div className="card"><div className="eyebrow">Evaluation Gate</div><h3>No silent model upgrades</h3><p>Model or prompt changes must pass versioned benchmark suites before controlled production.</p></div><div className="card"><div className="eyebrow">No-Hallucination Zones</div><h3>Fail closed on critical truth</h3><p>Regulations, engineering calculations, quantities, invoices, payments and contracts require deterministic evidence or Not Verified.</p></div><div className="card"><div className="eyebrow">Learning Promotion</div><h3>Self-improvement without self-corruption</h3><p>Observation → evidence → privacy → expert review → benchmark → shadow → controlled production → rollback.</p></div></div>
  </>;
}
