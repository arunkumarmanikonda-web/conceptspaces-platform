const domains=[
  ['Identity & Organisations','RBAC, ABAC, credentials'],
  ['Configuration','Stages, templates, rules, feature flags'],
  ['Audit & Evidence','Immutable events, release evidence'],
  ['Integrations','Supabase, Vercel, CAD/BIM, payments'],
  ['System Jobs','Workflow and compute job control'],
  ['Regulatory Packs','Jurisdiction/version registry']
];

export default function Admin(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Foundation</div><h1>Control Plane</h1><div className="subtle">Configuration, authority, audit and platform operations</div></div><button className="btn">System Health</button></div>
    <div className="grid-3">{domains.map(([heading,description],index)=><div className="card" key={heading}><div className="eyebrow">0{index+1}</div><h3>{heading}</h3><p>{description}</p><span className="badge">Foundation Enabled</span></div>)}</div>
    <div className="panel" style={{marginTop:18}}><h3>Governed Configuration</h3><table className="table"><thead><tr><th>Domain</th><th>Version</th><th>Maker</th><th>Checker</th><th>State</th></tr></thead><tbody><tr><td>India jurisdiction pack</td><td>draft-0.1</td><td>System</td><td>Required</td><td>Draft</td></tr><tr><td>Project lifecycle</td><td>1.0</td><td>Platform</td><td>Platform</td><td>Active</td></tr><tr><td>Authority matrix</td><td>1.0</td><td>Platform</td><td>Security</td><td>Active</td></tr></tbody></table></div>
  </>;
}
