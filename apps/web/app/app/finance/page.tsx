const journals=[
  ["JV-2026-081","20 Aug 2026","Client Invoice","₹ 4,25,000","Posted"],
  ["JV-2026-082","20 Aug 2026","Vendor Bill","₹ 1,80,000","Draft"],
  ["JV-2026-083","20 Aug 2026","Bank Receipt","₹ 2,10,000","Posted"]
];

export default function FinancePage(){
  return <>
    <div className="topbar"><div><div className="demo">Finance ERP / Project Accounting</div><h1>Finance</h1><div className="subtle">Double-entry accounting, project P&L, tax determinations, banking and period control</div></div><button className="btn">New Journal</button></div>
    <div className="kpis">{[["Revenue MTD","₹ 18.4 L"],["Receivables","₹ 11.05 L"],["Payables","₹ 7.80 L"],["TDS Receivable","₹ 1.14 L"],["Cash Position","₹ 24.6 L"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>8?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Journal Register</h3><table className="table"><thead><tr><th>Journal</th><th>Date</th><th>Source</th><th>Amount</th><th>Status</th></tr></thead><tbody>{journals.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td>{row[3]}</td><td><span className="badge">{row[4]}</span></td></tr>)}</tbody></table></section><section className="panel"><h3>Project P&L</h3><p className="subtle">Contracted revenue<br/><b>₹ 34.80 L</b><br/><br/>Recognised revenue<br/><b>₹ 18.40 L</b><br/><br/>Actual cost<br/><b>₹ 10.65 L</b><br/><br/>Forecast margin<br/><b>37.2%</b></p></section></div>
    <div className="note"><b>Accounting control.</b> Posted journals must balance. Closed fiscal periods cannot be modified by ordinary users. Reversals create linked entries rather than rewriting financial history.</div>
  </>;
}
