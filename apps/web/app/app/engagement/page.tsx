const negotiation=[
  ['v1','Concept Spaces','Proposal sent','₹18.40 L','12 modules','Complete'],
  ['v1','Client','Counter offer','₹16.75 L','10 modules','Received'],
  ['v2','Concept Spaces','Scope revised','₹17.60 L','11 modules','Pending Client']
];

const activation=[
  ['Proposal accepted','Required','Pending'],
  ['Contract executed','Required','Pending'],
  ['Initial payment satisfied','Required','Pending'],
  ['Required KYC satisfied','Required','Ready']
];

export default function EngagementPage(){
  return <>
    <div className="topbar"><div><div className="demo">Engagement / Commercial Activation</div><h1>Proposal → Negotiation → Activation</h1><div className="subtle">One auditable commercial thread from selected scope through counter-offer, contract, payment and project activation.</div></div><button className="btn">Create Proposal Version</button></div>
    <div className="kpis">{[['Opportunity Stage','Negotiation'],['Proposal Version','02'],['Current Offer','₹17.60L'],['Activation Gates','01 / 04'],['Critical Blocks','03']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Negotiation History</h3><table className="table"><thead><tr><th>Version</th><th>Party</th><th>Event</th><th>Amount</th><th>Scope</th><th>State</th></tr></thead><tbody>{negotiation.map(r=><tr key={`${r[0]}-${r[1]}-${r[2]}`}>{r.map((v,i)=><td key={i}>{i===5?<span className="badge">{v}</span>:v}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Activation Gates</h3><table className="table"><tbody>{activation.map(r=><tr key={r[0]}><td>{r[0]}</td><td>{r[1]}</td><td><span className="badge">{r[2]}</span></td></tr>)}</tbody></table><div className="note"><b>Fail closed.</b> A won opportunity does not become an active delivery project until the configured commercial, contract, payment and KYC prerequisites are satisfied.</div></section></div>
    <div className="panel" style={{marginTop:18}}><h3>Commercial Integrity</h3><p className="subtle">Every counter-offer and scope change creates a dated negotiation event tied to a proposal version. Accepted commercial terms become an immutable contract snapshot rather than overwriting the history that led to agreement.</p></div>
  </>;
}
