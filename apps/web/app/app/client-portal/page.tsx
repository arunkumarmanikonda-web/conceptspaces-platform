const timeline=[
  ['01','Brief received','Complete','Client intake and initial requirements captured'],
  ['02','Feasibility','In Progress','Site truth, regulation, programme and development scenarios'],
  ['03','Design','Pending','Architecture, interiors and engineering coordination'],
  ['04','Commercial','Pending','Proposal, contract, invoices and payments'],
  ['05','Delivery','Pending','Tender, procurement, site and handover']
];

export default function ClientPortalPage(){
  return <>
    <div className="topbar"><div><div className="demo">Client Portal / Illustrative</div><h1>Your Project</h1><div className="subtle">One transparent view of decisions, deliverables, approvals, commercial status and progress.</div></div><button className="btn">Message Project Team</button></div>
    <div className="kpis">{[['Project Stage','Feasibility'],['Open Decisions','03'],['Approvals Needed','02'],['Invoices Due','00'],['Critical Issues','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Project Journey</h3><table className="table"><thead><tr><th>Stage</th><th>Milestone</th><th>Status</th><th>Meaning</th></tr></thead><tbody>{timeline.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Client Actions</h3><p className="subtle">Review programme brief<br/>Approve scope selection<br/>Respond to design decision<br/>Review proposal / counteroffer<br/>Approve milestone release</p><div className="note"><b>Client control without technical ambiguity.</b> Client approvals do not replace statutory or professional approvals where those are independently required.</div></section></div>
  </>;
}
