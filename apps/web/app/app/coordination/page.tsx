const items=[
  ['COORD-001','Architecture','Structure','Core opening alignment','Coordinating'],
  ['COORD-002','MEP','Architecture','AHU service zone clearance','Open'],
  ['COORD-003','Fire','Architecture','Protected egress interface','Resolved'],
  ['COORD-004','Structure','MEP','Beam / duct interface','Coordinating']
];

export default function CoordinationPage(){
  return <>
    <div className="topbar"><div><div className="demo">Cross-Discipline Coordination</div><h1>Coordination Matrix</h1><div className="subtle">Explicit dependencies between architecture, interiors, structure, MEPF, fire, ELV, vertical transport and sustainability.</div></div><button className="btn">Raise Coordination Item</button></div>
    <div className="panel-grid"><section className="panel"><h3>Live Coordination</h3><table className="table"><thead><tr><th>ID</th><th>Source</th><th>Target</th><th>Subject</th><th>State</th></tr></thead><tbody>{items.map(i=><tr key={i[0]}><td>{i[0]}</td><td>{i[1]}</td><td>{i[2]}</td><td>{i[3]}</td><td><span className="badge">{i[4]}</span></td></tr>)}</tbody></table></section><section className="panel"><h3>Blast-Radius Discipline</h3><p className="subtle">A change is not considered local merely because it originates in one discipline. Coordination items must connect back to requirements, truth records, models, drawings and release gates so downstream impact is visible before acceptance.</p><div className="note"><b>No silent coordination debt.</b> Accepted deviations require an accountable owner, rationale and traceable approval.</div></section></div>
  </>;
}
