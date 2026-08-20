const engines=[
  ['ENG-DEMO-STRUCT','Structural Solver Adapter','Structure','0.1.0','Benchmarking','C2'],
  ['ENG-DEMO-HVAC','HVAC Load Engine','MEP','0.1.0','Uncertified','C1'],
  ['ENG-DEMO-DAYLIGHT','Daylight Simulation Adapter','Sustainability','0.1.0','Conditionally Approved','C2']
];

export default function EngineeringEnginesAdmin(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Verification & Validation</div><h1>Engineering Engine Registry</h1><div className="subtle">Versioned solver registry, benchmark evidence, supported standards, unit systems and maximum permitted criticality.</div></div><button className="btn">Register Engine Version</button></div>
    <div className="kpis">{[['Registered Engines','03'],['Approved','00'],['Benchmarking','01'],['Suspended','00'],['Critical Overrides','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Certification Registry</h3><table className="table"><thead><tr><th>Code</th><th>Engine</th><th>Discipline</th><th>Version</th><th>Certification</th><th>Max Criticality</th></tr></thead><tbody>{engines.map(e=><tr key={e[0]}><td>{e[0]}</td><td>{e[1]}</td><td>{e[2]}</td><td>{e[3]}</td><td><span className="badge">{e[4]}</span></td><td>{e[5]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Certification Rule</h3><p className="subtle">An engine/version is not promoted because it is popular or returns plausible numbers. Promotion requires defined benchmark cases, expected references, tolerances, reproducible execution evidence and controlled review.</p><div className="note"><b>Version lock.</b> A professional review remains bound to the exact calculation output hash and engine version. Engine upgrades do not retroactively validate prior outputs.</div></section></div>
  </>;
}
