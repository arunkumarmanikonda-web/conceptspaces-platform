const domains=[
  ['ORG','Organisation & legal entities','Active','Maker-checker'],
  ['LOC','Countries / currencies / locales','Active','Maker-checker'],
  ['STAGE','Project stages & gates','Active','Maker-checker'],
  ['ROLE','Roles & authority','Active','Security checker'],
  ['FEATURE','Feature flags','Draft','Platform checker'],
  ['RET','Retention policies','Draft','Privacy checker']
];
export default function SystemConfig(){return <><div className="topbar"><div><div className="demo">Super Admin / System Configuration</div><h1>Platform Configuration</h1><div className="subtle">Versioned configuration for organisations, project lifecycle, authority, localisation, retention and feature rollout.</div></div><button className="btn">Create Config Change</button></div><div className="panel-grid"><section className="panel"><h3>Configuration Domains</h3><table className="table"><thead><tr><th>Code</th><th>Domain</th><th>State</th><th>Change Control</th></tr></thead><tbody>{domains.map(r=><tr key={r[0]}><td>{r[0]}</td><td>{r[1]}</td><td><span className="badge">{r[2]}</span></td><td>{r[3]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Configuration Principle</h3><p className="subtle">Business rules and lifecycle configuration should be data-driven, versioned and auditable instead of hidden constants scattered through application code.</p><div className="note"><b>Safe rollout.</b> Material configuration changes support review, effective dates and rollback/version history.</div></section></div></>}
