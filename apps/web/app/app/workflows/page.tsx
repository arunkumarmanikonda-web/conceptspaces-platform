const tasks=[
  ['WF-REL-014','Release evidence review','Professional Reviewer','High','Submitted','18 min'],
  ['WF-PROP-006','Proposal maker-checker','Commercial Checker','Normal','Open','4 h'],
  ['WF-RULE-009','REGULA rule publication','Technical Checker','High','In Progress','1 d'],
  ['WF-AP-022','Vendor invoice approval','Finance Checker','Normal','Open','6 h']
];

export default function WorkflowsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Workflow Operations / Maker-Checker</div><h1>Work Queue</h1><div className="subtle">Human, agent, system and integration work coordinated through explicit tasks, evidence, SLAs and independent checks.</div></div><button className="btn">Start Workflow</button></div>
    <div className="kpis">{[['Open Tasks','18'],['SLA Risk','03'],['Awaiting Checker','05'],['Agent Tasks','07'],['Failed Workflows','00']].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Priority Queue</h3><table className="table"><thead><tr><th>ID</th><th>Task</th><th>Assignee</th><th>Priority</th><th>State</th><th>Due</th></tr></thead><tbody>{tasks.map(r=><tr key={r[0]}>{r.map((v,i)=><td key={i}>{i===4?<span className="badge">{v}</span>:v}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Maker-Checker Boundary</h3><p className="subtle">Where independent review is required, the person or agent preparing a controlled action cannot satisfy the checker role for the same action.</p><div className="note"><b>Automation does not erase accountability.</b> A workflow may automate routing, evidence collection and reminders while keeping the approval authority explicit.</div></section></div>
  </>;
}
