const activities=[
  ["WBS-01.04","Raft Foundation","Complete","100%","Verified"],
  ["WBS-02.02","Level 02 Structure","In Progress","72%","On track"],
  ["WBS-03.01","MEP Sleeves / Inserts","In Progress","64%","Attention"],
  ["WBS-04.06","Façade Mock-up","Blocked","35%","RFI open"]
];

export default function SitePage(){
  return <>
    <div className="topbar"><div><div className="demo">PMC / Construction / Reality Capture</div><h1>Site & Delivery</h1><div className="subtle">Programme, inspections, quality, progress evidence and drawing-to-reality comparison</div></div><button className="btn">Capture Site Update</button></div>
    <div className="kpis">{[["Overall Progress","48.6%"],["Open Site Issues","11"],["NCRs","02"],["Inspections Due","06"],["Reality Captures","24"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>8?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Work Programme</h3><table className="table"><thead><tr><th>WBS</th><th>Activity</th><th>State</th><th>Progress</th><th>Evidence</th></tr></thead><tbody>{activities.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td><td>{row[4]}</td></tr>)}</tbody></table></section>
    <div className="grid-3"><div className="card"><div className="eyebrow">Reality Capture</div><h3>Compare reality to intent</h3><p>Mobile, 360, drone, point-cloud and LiDAR capture can be related back to model objects and design requirements.</p></div><div className="card"><div className="eyebrow">Quality</div><h3>Evidence before closure</h3><p>Observations, NCRs and inspections carry media/evidence refs and verifier identity before closure.</p></div><div className="card"><div className="eyebrow">Early Warning</div><h3>Schedule, cost and coordination signals</h3><p>Dependencies and field observations become early-warning inputs rather than retrospective reporting.</p></div></div>
  </>;
}
