const gates=[
  ["GATE-TRUTH","Project Truth","C3","Approved","0"],
  ["GATE-REG","Regulatory","C4","Blocked","1"],
  ["GATE-ARCH","Architecture","C3","Ready for review","0"],
  ["GATE-COORD","Coordination","C3","Not ready","0"],
  ["GATE-CLIENT","Client Approval","C2","Not ready","0"]
];

export default function ReleasesPage(){
  return <>
    <div className="topbar"><div><div className="demo">Proof Before Publish</div><h1>Release Assurance</h1><div className="subtle">Safety case, evidence, professional authority and zero critical escape</div></div><button className="btn">Assemble Safety Case</button></div>
    <div className="kpis">{[["Release Package","DD-ARCH-01"],["Critical Defects","01"],["Approvals","2 / 4"],["Evidence Items","18"],["Issue State","BLOCKED"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>8?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Release Gates</h3><table className="table"><thead><tr><th>Gate</th><th>Discipline / Basis</th><th>Criticality</th><th>State</th><th>Critical Defects</th></tr></thead><tbody>{gates.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td><span className="badge">{row[3]}</span></td><td>{row[4]}</td></tr>)}</tbody></table></section>
    <div className="note"><b>ZERO CRITICAL ESCAPE:</b> an issued package may never contain an unresolved C3/C4 validation failure. Administrative privilege cannot override this gate. A qualified professional approval is evidence, not decoration, and remains bound to the exact package hash/version reviewed.</div>
  </>;
}
