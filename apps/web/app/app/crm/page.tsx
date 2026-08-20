const leads=[
  ["LD-2401","Delhi Hotel Development","Qualified","₹ 18.0 Cr","Proposal due"],
  ["LD-2402","Noida Mixed Use Campus","Discovery","₹ 42.0 Cr","Site brief"],
  ["LD-2403","Private Residence","Nurture","₹ 6.5 Cr","Follow-up"]
];

export default function CRMPage(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>CRM & Growth</h1><div className="subtle">Leads, opportunities, next actions and conversion intelligence</div></div><button className="btn">New Lead</button></div>
    <div className="kpis">{[["Open Leads","18"],["Qualified","07"],["Proposal Pipeline","₹ 2.46 Cr"],["Weighted Pipeline","₹ 1.31 Cr"],["Next Actions","11"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Opportunity Pipeline</h3><table className="table"><thead><tr><th>Reference</th><th>Opportunity</th><th>Stage</th><th>Project Value</th><th>Next Action</th></tr></thead><tbody>{leads.map(row=><tr key={row[0]}>{row.map((cell,i)=><td key={cell}>{i===2?<span className="badge">{cell}</span>:cell}</td>)}</tr>)}</tbody></table></section>
  </>;
}
