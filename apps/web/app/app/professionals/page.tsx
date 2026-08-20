const roles=[
  ['Lead Architect','Architecture','Concept → Handover','Required','Unassigned'],
  ['Structural Engineer','Structure','Design Development → Issue','Required','Unassigned'],
  ['MEPF Lead','MEPF','Concept → Handover','Required','Unassigned'],
  ['Interior Design Lead','Interiors','Concept → Installation','Optional','Unassigned'],
  ['Quantity Surveyor','Cost','Design Development → Closeout','Required','Unassigned'],
  ['Project Manager','PMC','Tender → Handover','Optional','Unassigned']
];

export default function ProfessionalsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Professional Resource ERP</div><h1>Project Team & Authority</h1><div className="subtle">Assign the right professional by discipline, stage, credential eligibility, capacity and project authority.</div></div><button className="btn">Find Professional</button></div>
    <div className="kpis">{[['Required Roles','04'],['Assigned','00'],['Credential Blocks','00'],['Capacity Risks','00'],['SPOC','Lead Architect']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Role Requirements</h3><table className="table"><thead><tr><th>Role</th><th>Discipline</th><th>Stage</th><th>Requirement</th><th>Assignment</th></tr></thead><tbody>{roles.map(r=><tr key={r[0]}><td>{r[0]}</td><td>{r[1]}</td><td>{r[2]}</td><td>{r[3]}</td><td><span className="badge">{r[4]}</span></td></tr>)}</tbody></table></section><section className="panel"><h3>Authority Binding</h3><p className="subtle">Assignment to a project does not automatically grant approval authority. Credential type, verification state, discipline, stage, role and release criticality are evaluated separately.</p><div className="note"><b>Lead Architect as SPOC.</b> Client coordination may be centralised through the lead architect while discipline professionals retain independent technical accountability for their own governed releases.</div></section></div>
  </>;
}
