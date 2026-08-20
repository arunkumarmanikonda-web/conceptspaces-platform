const facts=[
  ["Boundary geometry","Survey/DWG required","D","Not verified"],
  ["Plot area","1,840.00 sqm","B","Source checked"],
  ["Road width","24.00 m","B","Source checked"],
  ["FAR / FSI","2.50","C","Client supplied"],
  ["Ground coverage","40%","C","Client supplied"],
  ["Height restriction","Pending NOCAS check","D","Not verified"]
];

export default function SiteTruthPage(){
  return <>
    <div className="topbar"><div><div className="demo">Project Truth / Site</div><h1>Site Truth</h1><div className="subtle">Coordinates, survey geometry, planning inputs, source confidence and assumptions</div></div><button className="btn">Upload Survey</button></div>
    <div className="kpis">{[["Verified Facts","08"],["Assumptions","05"],["Critical Unknowns","02"],["Source Conflicts","00"],["Geometry State","B"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Planning & Site Facts</h3><table className="table"><thead><tr><th>Fact</th><th>Value</th><th>Confidence</th><th>Verification</th></tr></thead><tbody>{facts.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Geometry Rule</h3><p className="subtle">Four side lengths do not uniquely define an arbitrary quadrilateral. Concept Spaces will accept preliminary dimensions for feasibility, but a release-capable parcel model requires verified corner coordinates, bearings/angles/diagonal information or a survey/CAD/cadastral source.</p><div className="note"><b>No hallucination zone.</b> Missing geometry is reported as Not Verified. It is never invented.</div></section></div>
  </>;
}
