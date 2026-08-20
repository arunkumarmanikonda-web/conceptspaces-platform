const docs=[
  ["A-101","General Arrangement Plan","Architecture","P03","For Review"],
  ["A-301","Building Sections","Architecture","P02","Shared"],
  ["S-101","Structural Framing Plan","Structure","P01","For Approval"],
  ["M-201","HVAC Zoning","MEP","P01","Work in Progress"],
  ["ID-401","Typical Room Interior Elevation","Interiors","P02","For Review"]
];

export default function DocumentsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Common Data Environment</div><h1>Documents & Drawings</h1><div className="subtle">WIP → Shared → Published → Archived, with immutable versions and transmittals</div></div><button className="btn">Upload / Register</button></div>
    <div className="kpis">{[["Registered Documents","128"],["For Review","16"],["For Approval","07"],["Issued","42"],["Superseded","19"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Drawing Register</h3><table className="table"><thead><tr><th>Number</th><th>Title</th><th>Discipline</th><th>Revision</th><th>Status</th></tr></thead><tbody>{docs.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
  </>;
}
