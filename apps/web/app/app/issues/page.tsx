const issues=[
  ["ISS-042","Door clearance at service core","Coordination","C2","In Progress","24 Aug"],
  ["RFI-017","Structural connection at canopy","RFI","C3","Answered","22 Aug"],
  ["ISS-051","MEP shaft conflict Level 05","Coordination","C3","Open","23 Aug"],
  ["QA-011","Waterproofing detail mismatch","Quality","C2","Open","25 Aug"]
];

export default function IssuesPage(){
  return <>
    <div className="topbar"><div><div className="demo">BCF / RFI / Coordination</div><h1>Issues & RFIs</h1><div className="subtle">Object-linked coordination, technical queries, evidence and closure</div></div><button className="btn">Create Issue</button></div>
    <div className="kpis">{[["Open","18"],["C3 / C4","02"],["Overdue","03"],["Awaiting Reply","06"],["Closed This Week","14"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Coordination Queue</h3><table className="table"><thead><tr><th>Issue</th><th>Title</th><th>Type</th><th>Criticality</th><th>Status</th><th>Due</th></tr></thead><tbody>{issues.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td><td>{row[5]}</td></tr>)}</tbody></table></section>
  </>;
}
