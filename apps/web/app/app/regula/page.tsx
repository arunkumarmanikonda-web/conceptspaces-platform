const checks=[
  ["REG-SETBACK-001","Setback applicability","Green","Pass"],
  ["REG-FAR-004","Permissible FAR / FSI","Amber","Requires interpretation"],
  ["REG-HEIGHT-006","Airport height overlay","Red","Not verified"],
  ["REG-FIRE-012","Fire tender access","Green","Pass"],
  ["REG-PARK-021","Parking requirement","Amber","Pass"]
];

export default function RegulaPage(){
  return <>
    <div className="topbar"><div><div className="demo">REGULA™ / Jurisdiction Engine</div><h1>Regulatory Intelligence</h1><div className="subtle">Effective-date-aware applicability, precedence, evidence and professional interpretation</div></div><button className="btn">Run Compliance</button></div>
    <div className="kpis">{[["Applicable Packs","06"],["Rules Evaluated","31"],["Green","24"],["Amber","06"],["Red","01"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Applicability & Findings</h3><table className="table"><thead><tr><th>Rule</th><th>Subject</th><th>Disposition</th><th>Status</th></tr></thead><tbody>{checks.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td></tr>)}</tbody></table></section>
    <div className="panel-grid"><section className="panel"><h3>Publication Governance</h3><p className="subtle">AI may discover, compare and draft regulatory interpretations. Production rules require technical/legal maker-checker review before publication. Every rule stores source reference, effective date, pack version and supersession relationships.</p></section><section className="panel"><h3>Disposition Model</h3><p className="subtle"><b>Green:</b> deterministic and directly testable.<br/><br/><b>Amber:</b> professional interpretation required.<br/><br/><b>Red:</b> authority/specialist clearance or unresolved statutory condition.</p></section></div>
  </>;
}
