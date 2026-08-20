const packages=[
  ["Concept Architecture","Concept","v04","94%","For Review"],
  ["GA Plans","Schematic","v03","97%","Coordinating"],
  ["Elevations & Sections","Schematic","v02","91%","Coordinating"],
  ["Door / Window Schedules","DD","v01","76%","Draft"]
];

export default function ArchitecturePage(){
  return <>
    <div className="topbar"><div><div className="demo">Architecture / Building Compiler™</div><h1>Architecture</h1><div className="subtle">Programme, zoning, circulation, drawings, model coordination and requirement coverage</div></div><button className="btn">New Architecture Package</button></div>
    <div className="kpis">{[["Programme Coverage","96%"],["Active Packages","04"],["Open Coordination","11"],["Client Decisions","03"],["Release Confidence","B"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>8?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Architecture Packages</h3><table className="table"><thead><tr><th>Package</th><th>Stage</th><th>Version</th><th>Requirement Coverage</th><th>Status</th></tr></thead><tbody>{packages.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
    <div className="grid-3"><div className="card"><div className="eyebrow">Space Programme</div><h3>Every room traces to intent</h3><p>Areas, adjacencies, capacity, access, servicing, daylight and operational requirements remain linked to project requirements rather than becoming disconnected drawing notes.</p></div><div className="card"><div className="eyebrow">Change Impact</div><h3>Design changes expose blast radius</h3><p>A planning change identifies affected structure, MEP, interiors, cost, regulation, documentation and client decisions before release.</p></div><div className="card"><div className="eyebrow">Issue Authority</div><h3>Draft is not issued</h3><p>Architecture packages become issued deliverables only through the applicable coordination and professional approval gates.</p></div></div>
  </>;
}
