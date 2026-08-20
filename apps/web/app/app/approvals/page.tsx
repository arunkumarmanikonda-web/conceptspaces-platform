const approvals=[
  ["APR-101","DD Architecture Set","Release","C3","Lead Architect","Pending"],
  ["APR-102","Structural Framing P02","Document","C4","Structural Engineer","Pending"],
  ["APR-103","Façade Material Option B","Design Option","C2","Client","Approved"],
  ["APR-104","Proposal PR-2026-003","Commercial","C2","Commercial Authority","Approved with comments"]
];

export default function ApprovalsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Maker-Checker / Authority</div><h1>Approvals</h1><div className="subtle">Role, discipline, scope and criticality-aware decisions with immutable evidence</div></div><button className="btn">Request Approval</button></div>
    <div className="kpis">{[["Pending","09"],["C3 / C4","03"],["Client Decisions","04"],["Due Today","02"],["Rejected","01"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Approval Queue</h3><table className="table"><thead><tr><th>Reference</th><th>Resource</th><th>Type</th><th>Criticality</th><th>Authority</th><th>Decision</th></tr></thead><tbody>{approvals.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td>{row[4]}</td><td><span className="badge">{row[5]}</span></td></tr>)}</tbody></table></section>
    <div className="note"><b>Authority boundary.</b> Approval is valid only when the approver is eligible for the exact resource, project scope, discipline and criticality. The approval evidence is bound to the reviewed version/hash so later modifications automatically invalidate it.</div>
  </>;
}
