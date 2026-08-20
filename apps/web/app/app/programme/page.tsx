const programme=[
  ['HOT-KEY','Guest Rooms','Keys',120,'38 sqm','B'],
  ['HOT-ADR','All Day Dining','F&B',1,'220 sqm','B'],
  ['HOT-BANQ','Convention / Banquet','Events',1,'650 sqm','C'],
  ['HOT-BOH','Back of House','Operations',1,'1,050 sqm','C'],
  ['HOT-PARK','Parking','Mobility',95,'stalls','C']
];

export default function ProgrammePage(){
  return <>
    <div className="topbar"><div><div className="demo">Programme Builder / Typology Intelligence</div><h1>Programme Intelligence</h1><div className="subtle">Convert raw client intent into a measurable, traceable spatial programme with adjacencies, operating logic and confidence.</div></div><button className="btn">Add Programme Item</button></div>
    <div className="kpis">{[['Net Programme','8,420'],['Gross Programme','11,360'],['Target Efficiency','74%'],['Mandatory Items','18'],['D-Confidence Items','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative sqm</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Programme Schedule</h3><table className="table"><thead><tr><th>Code</th><th>Space</th><th>Category</th><th>Qty</th><th>Basis</th><th>Confidence</th></tr></thead><tbody>{programme.map(row=><tr key={row[0] as string}>{row.map((v,i)=><td key={i}>{i===5?<span className="badge">{v}</span>:v}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Typology Knowledge Pack</h3><p className="subtle">Knowledge packs provide programme categories, amenity patterns, operational principles, engineering considerations and commercial drivers. They accelerate briefing without replacing project-specific requirements.</p><div className="note"><b>No benchmark becomes a requirement automatically.</b> Every programme item retains its source and confidence so global precedent never silently overrides client intent or jurisdiction.</div></section></div>
  </>;
}
