const assets=[
  ["AHU-L05-01","Air Handling Unit","Level 05 Plant","Commissioned","Mar 2028"],
  ["PMP-B1-03","Fire Pump","Basement B1","Commissioned","Jan 2029"],
  ["LIFT-T1-02","Passenger Lift","Tower 1","Handover Pending","Dec 2027"],
  ["DG-01","Diesel Generator","Utility Yard","Commissioned","Apr 2028"]
];

export default function TwinPage(){
  return <>
    <div className="topbar"><div><div className="demo">Building Passport / Digital Twin</div><h1>Operate</h1><div className="subtle">Asset passports, commissioning, warranties, maintenance and post-occupancy learning</div></div><button className="btn">Register Asset</button></div>
    <div className="kpis">{[["Asset Passports","284"],["Commissioned","231"],["Open Handover Items","18"],["Warranty Alerts","07"],["Maintenance Due","11"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Asset Register</h3><table className="table"><thead><tr><th>Asset</th><th>Type</th><th>Location</th><th>Status</th><th>Warranty</th></tr></thead><tbody>{assets.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td><span className="badge">{row[3]}</span></td><td>{row[4]}</td></tr>)}</tbody></table></section>
    <div className="note"><b>Closed learning loop.</b> Post-occupancy, maintenance, defect and performance outcomes can feed the Design Genome only through the governed learning-promotion pipeline: evidence → privacy/anonymisation → expert review → benchmarks → shadow mode → controlled production.</div>
  </>;
}
