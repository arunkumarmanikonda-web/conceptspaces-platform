import Link from "next/link";

const projects=[
  ['CS-DEMO-001','Hospitality Feasibility','Concept',62],
  ['CS-DEMO-002','Mixed Use Study','Site Truth',45],
  ['CS-DEMO-003','Residential Development','Briefing',28]
];

export default function Dashboard(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>Platform Command Centre</h1><div className="subtle">Foundation release • Build Pack 01</div></div><Link className="btn" href="/app/projects/new">New Project</Link></div>
    <div className="kpis">{[['Active Projects','03'],['Project Truth Issues','04'],['Pending Decisions','07'],['Release Gates','00'],['Critical Exceptions','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Project Portfolio</h3><div className="project-cards">{projects.map(([id,name,stage,progress])=><div className="project-card" key={id as string}><div className="project-thumb"></div><div className="subtle" style={{marginTop:12}}>{id}</div><h4>{name}</h4><span className="badge">{stage}</span><div className="progress"><i style={{width:`${progress}%`}}/></div></div>)}</div></section><section className="panel"><h3>System Posture</h3><table className="table"><tbody><tr><td><span className="status-dot"/>Audit ledger</td><td>Ready</td></tr><tr><td><span className="status-dot"/>Authority model</td><td>Ready</td></tr><tr><td><span className="status-dot"/>Project Truth</td><td>Ready</td></tr><tr><td><span className="status-dot"/>Supabase</td><td>Provisioning</td></tr><tr><td><span className="status-dot"/>Git remote</td><td>Connected</td></tr></tbody></table></section></div>
    <div className="panel-grid"><section className="panel"><h3>Proof Before Publish</h3><table className="table"><thead><tr><th>Gate</th><th>Policy</th><th>Status</th></tr></thead><tbody><tr><td>Project Truth</td><td>No unresolved critical source conflicts</td><td><span className="badge">Enforced</span></td></tr><tr><td>Professional Authority</td><td>Release role + credential eligibility</td><td><span className="badge">Enforced</span></td></tr><tr><td>Engineering Validation</td><td>Discipline-specific validation evidence</td><td><span className="badge">Planned</span></td></tr><tr><td>Immutable Audit</td><td>All critical state transitions logged</td><td><span className="badge">Enforced</span></td></tr></tbody></table></section><section className="panel"><h3>Foundation Sequence</h3><p className="subtle">1. Isolated Supabase<br/>2. Initial migration + RLS<br/>3. GitHub source of truth<br/>4. Vercel deployment<br/>5. CI/CD and health controls</p></section></div>
  </>;
}
