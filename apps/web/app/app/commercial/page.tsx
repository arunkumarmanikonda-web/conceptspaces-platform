const proposals=[
  ["PR-2026-001","Hospitality Feasibility","Internal Review","₹ 18,50,000","30 Aug 2026"],
  ["PR-2026-002","Mixed Use Concept + DD","Sent","₹ 42,75,000","04 Sep 2026"],
  ["PR-2026-003","Residence Architecture","Countered","₹ 9,80,000","24 Aug 2026"]
];
const invoices=[
  ["CS/26-27/001","₹ 4,25,000","Issued","27 Aug 2026"],
  ["CS/26-27/002","₹ 2,10,000","Part Paid","22 Aug 2026"],
  ["CS/26-27/003","₹ 6,80,000","Draft","05 Sep 2026"]
];

export default function CommercialPage(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>Commercial OS</h1><div className="subtle">Proposal → negotiation → contract → milestone → invoice → payment</div></div><button className="btn">Create Proposal</button></div>
    <div className="kpis">{[["Proposal Value","₹ 71.05 L"],["Contracted Fees","₹ 34.80 L"],["Receivables","₹ 11.05 L"],["TDS Receivable","₹ 1.14 L"],["Overdue","₹ 0"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Proposals & Negotiations</h3><table className="table"><thead><tr><th>Proposal</th><th>Opportunity</th><th>Status</th><th>Fee</th><th>Validity</th></tr></thead><tbody>{proposals.map(row=><tr key={row[0]}>{row.map((cell,i)=><td key={cell}>{i===2?<span className="badge">{cell}</span>:cell}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Commercial Controls</h3><p className="subtle">Maker-checker on commercial approvals<br/><br/>Versioned client counteroffers<br/><br/>Scope option toggles<br/><br/>No payment marked successful without verified provider event<br/><br/>All invoice/payment transitions audited</p></section></div>
    <section className="panel" style={{marginTop:16}}><h3>Invoices & Collections</h3><table className="table"><thead><tr><th>Invoice</th><th>Amount</th><th>Status</th><th>Due</th></tr></thead><tbody>{invoices.map(row=><tr key={row[0]}>{row.map((cell,i)=><td key={cell}>{i===2?<span className="badge">{cell}</span>:cell}</td>)}</tr>)}</tbody></table></section>
  </>;
}
