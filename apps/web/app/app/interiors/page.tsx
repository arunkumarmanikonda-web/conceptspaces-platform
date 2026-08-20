const rooms=[
  ["Guest Room Type A","Modern Elite / Warm Minimal","DD","12 / 14","For Review"],
  ["All Day Dining","Contemporary Craft","Concept","8 / 11","Client Review"],
  ["Lobby","Monumental / Natural Stone","DD","16 / 18","Coordinating"],
  ["Executive Suite","Quiet Luxury","Shop Drawing","22 / 24","For Approval"]
];

export default function InteriorsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Interiors / Design DNA</div><h1>Interiors</h1><div className="subtle">Design language, material intelligence, room packages, renders and execution drawings</div></div><button className="btn">Create Design DNA</button></div>
    <div className="kpis">{[["Room Types","18"],["Approved Materials","64"],["Samples Pending","12"],["Shop Drawings","38"],["Design DNA Version","v03"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>7?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Room / Space Packages</h3><table className="table"><thead><tr><th>Space</th><th>Design Language</th><th>Stage</th><th>Selections</th><th>Status</th></tr></thead><tbody>{rooms.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
    <div className="panel-grid"><section className="panel"><h3>Design DNA / Illustrative</h3><p className="subtle">Language: quiet luxury, contemporary craft, warm modern<br/><br/>Materials: natural stone, solid wood, textured plaster, selective metal accents<br/><br/>Lighting: layered, warm, indirect + task emphasis<br/><br/>Exclusions: synthetic marble effect, high-gloss laminates, decorative clutter</p></section><section className="panel"><h3>Material Assurance</h3><p className="subtle">Material selections can carry fire/slip ratings, manufacturer/product references, embodied-carbon indicators, cost band, sample approval and substitution history.</p></section></div>
  </>;
}
