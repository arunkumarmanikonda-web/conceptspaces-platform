const models=[
  ["Architecture Federation","Architecture","IFC 4.3","P03","Validated"],
  ["Structure Model","Structure","IFC 4.3","P02","For Review"],
  ["MEP Coordination","MEP","IFC 4.3","P01","Clash Review"],
  ["Interiors Model","Interiors","IFC 4.3","P01","Work in Progress"]
];

export default function ModelsPage(){
  return <>
    <div className="topbar"><div><div className="demo">OpenBIM / Model Federation</div><h1>Models</h1><div className="subtle">IFC, IDS and BCF-first coordination with controlled proprietary adapters</div></div><button className="btn">Register Model</button></div>
    <div className="kpis">{[["Federated Models","04"],["Clashes","38"],["Critical Clashes","00"],["IDS Checks","87%"],["Coordinate Match","100%"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Model Register</h3><table className="table"><thead><tr><th>Model</th><th>Discipline</th><th>Schema</th><th>Revision</th><th>State</th></tr></thead><tbody>{models.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section>
    <div className="note"><b>Open data principle.</b> The canonical project model is not dependent on Revit, Autodesk or any single authoring vendor. Proprietary formats may be connected through authorised adapters while IFC/IDS/BCF remain first-class exchange and validation contracts.</div>
  </>;
}
