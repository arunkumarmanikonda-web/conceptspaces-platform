const rules=[
  ["GST-SVC-001","GST / Services","Published","01 Apr 2026","Technical + Finance"],
  ["TDS-PROF-001","TDS / Professional Fees","Review","01 Apr 2026","Finance + Tax"],
  ["EINV-THRESH-001","E-Invoice Applicability","Published","01 Apr 2026","Finance + Tax"],
  ["RCM-001","Reverse Charge Candidate","Draft","01 Apr 2026","Tax Review"]
];

export default function TaxRulesPage(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / India Tax Engine</div><h1>Tax Rule Packs</h1><div className="subtle">Effective-date, jurisdiction, source and maker-checker governed statutory logic</div></div><button className="btn">Draft Rule</button></div>
    <div className="kpis">{[["Published Rules","28"],["In Review","04"],["Needs Source Update","01"],["Rule Sets","07"],["Hardcoded Tax Rules","00"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Effective Rules</h3><table className="table"><thead><tr><th>Code</th><th>Rule Set</th><th>Status</th><th>Effective From</th><th>Review</th></tr></thead><tbody>{rules.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td><td>{row[4]}</td></tr>)}</tbody></table></section>
    <div className="note"><b>No hard-coded law.</b> GST, place of supply, reverse charge, TDS/TCS, e-invoice applicability and future statutory changes are versioned rule packs with source references and effective dates. Unverified applicability returns Needs Review / Not Verified.</div>
  </>;
}
