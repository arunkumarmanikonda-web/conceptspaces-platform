const modules=[
  ['FEAS','Feasibility + Development Economics','Pre-design','Included','Fixed / milestone'],
  ['ARCH','Architecture','Design','Included','Sqft / fixed / milestone'],
  ['INT','Interior Design','Design','Optional','Sqft / fixed'],
  ['STR','Structural Engineering','Engineering','Included','Fixed / sqft'],
  ['MEPF','MEPF + Fire + ELV','Engineering','Included','Fixed / sqft'],
  ['BIM','BIM / CDE / Coordination','Information','Included','Fixed / retainer'],
  ['BOQ','QTO / BOQ / Cost Intelligence','Cost','Optional','Fixed / milestone'],
  ['PROC','Tender + Procurement','Delivery','Excluded','Percent / fixed'],
  ['PMC','PMC + Site Delivery','Delivery','Excluded','Percent / monthly retainer'],
  ['TWIN','Handover + Digital Twin','Operations','Optional','Fixed / subscription']
];

export default function ScopePage(){
  return <>
    <div className="topbar"><div><div className="demo">Scope Configurator / Modular Engagement</div><h1>Scope Architecture</h1><div className="subtle">Select, price and dependency-check the engagement without hiding what each module includes or requires.</div></div><button className="btn">Create Scope Version</button></div>
    <div className="kpis">{[['Included','05'],['Optional','03'],['Excluded','02'],['Dependency Conflicts','00'],['Pricing Models','09']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Module Catalogue</h3><table className="table"><thead><tr><th>Code</th><th>Module</th><th>Category</th><th>State</th><th>Pricing</th></tr></thead><tbody>{modules.map(r=><tr key={r[0]}><td>{r[0]}</td><td>{r[1]}</td><td>{r[2]}</td><td><span className="badge">{r[3]}</span></td><td>{r[4]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Dependency Control</h3><p className="subtle">Scope modules may declare prerequisites. A module cannot silently remain active if a required upstream service has been removed without an explicit alternative responsibility.</p><div className="note"><b>Transparent exclusions.</b> Excluded scope remains visible in the engagement record so later variations cannot be confused with services originally promised.</div></section></div>
  </>;
}
