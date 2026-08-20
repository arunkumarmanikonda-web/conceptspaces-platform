const options=[
  ["Option A","Balanced","31,480 sqm","82%","B"],
  ["Option B","Commercial Yield","33,120 sqm","74%","B"],
  ["Option C","Environmental","29,860 sqm","91%","B"]
];

export default function DesignPage(){
  return <>
    <div className="topbar"><div><div className="demo">Building Compiler / Concept</div><h1>Design Intelligence</h1><div className="subtle">Generate, compare, branch, validate and explain design options</div></div><button className="btn">Generate Options</button></div>
    <div className="kpis">{[["Active Options","03"],["Requirements Traced","96%"],["Compliance Passed","28 / 31"],["Critical Failures","00"],["Client Selection","Pending"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Pareto Design Options</h3><table className="table"><thead><tr><th>Option</th><th>Optimisation</th><th>Buildable Area</th><th>Daylight Score</th><th>Confidence</th></tr></thead><tbody>{options.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
    <div className="grid-3"><div className="card"><div className="eyebrow">Building Git</div><h3>Branch without losing truth</h3><p>Every design alternative has a parent, rationale, requirement baseline and change-impact trail. A discarded option is retained as history, not silently overwritten.</p></div><div className="card"><div className="eyebrow">Voice to Design</div><h3>Structured intent, not raw prompting</h3><p>Architect voice, text or sketch inputs are converted into explicit structured changes before implementation and revalidation.</p></div><div className="card"><div className="eyebrow">Design Assurance Ledger</div><h3>Explain every important decision</h3><p>What changed, why, source, confidence, author, approver, affected requirements and downstream blast radius remain traceable.</p></div></div>
  </>;
}
