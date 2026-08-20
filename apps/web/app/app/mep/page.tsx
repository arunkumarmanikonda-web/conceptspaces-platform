const systems=[
  ['MECH-HVAC-01','Mechanical','HVAC design criteria','Criteria'],
  ['ELEC-LV-01','Electrical','Connected + demand load','Sizing'],
  ['PLB-WTR-01','Plumbing','Water demand + storage','Coordination'],
  ['FIRE-01','Fire','Firefighting / life safety','For Review'],
  ['ELV-01','ELV','ICT / security / access','Criteria'],
  ['VT-01','Vertical Transport','Lift traffic basis','Criteria']
];

export default function MepPage(){
  return <>
    <div className="topbar"><div><div className="demo">MEPF + ELV + VT / Integrated Systems</div><h1>Building Systems Engineering</h1><div className="subtle">Design criteria, load calculations, equipment selection, coordinated models and review evidence.</div></div><button className="btn">Add System</button></div>
    <div className="kpis">{[['Systems','06'],['Load Runs','04'],['Coordination Issues','03'],['Equipment Selections','08'],['Critical Blocks','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>System Register</h3><table className="table"><thead><tr><th>Code</th><th>Discipline</th><th>Current Basis</th><th>State</th></tr></thead><tbody>{systems.map(s=><tr key={s[0]}><td>{s[0]}</td><td>{s[1]}</td><td>{s[2]}</td><td><span className="badge">{s[3]}</span></td></tr>)}</tbody></table></section><section className="panel"><h3>Integrated Validation</h3><p className="subtle">MEPF outputs remain tied to stated design criteria, calculation runs, equipment assumptions and spatial coordination. Fire/life-safety rules are treated as critical governance inputs, not stylistic suggestions.</p><div className="note"><b>Coordination before issue.</b> Architecture, structure and services must close relevant C3/C4 clashes or carry an explicitly approved deviation before a release gate can advance.</div></section></div>
  </>;
}
