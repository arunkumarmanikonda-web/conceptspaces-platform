const studies=[
  ['Solar exposure','Solar','Complete','B','Orientation + façade implications'],
  ['Daylight potential','Daylight','Draft','C','Floorplate depth / glazing basis'],
  ['Wind context','Wind','Draft','C','Prevailing wind + outdoor comfort'],
  ['Water balance','Water','Draft','C','Rainfall / demand / reuse opportunity'],
  ['Flood exposure','Flood','Pending source','D','No verified flood source attached']
];

export default function ClimatePage(){
  return <>
    <div className="topbar"><div><div className="demo">Climate + Environmental Intelligence</div><h1>Climate & Environment</h1><div className="subtle">Site-specific climate context and simulation evidence linked to design decisions rather than decorative sustainability claims.</div></div><button className="btn">Run Study</button></div>
    <div className="kpis">{[['Climate Zone','Composite'],['Weather Dataset','Pending'],['Studies','05'],['Verified','01'],['Critical Unknowns','01']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Environmental Study Register</h3><table className="table"><thead><tr><th>Study</th><th>Type</th><th>State</th><th>Confidence</th><th>Design Use</th></tr></thead><tbody>{studies.map(s=><tr key={s[0]}><td>{s[0]}</td><td>{s[1]}</td><td>{s[2]}</td><td><span className="badge">{s[3]}</span></td><td>{s[4]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Evidence Before Claim</h3><p className="subtle">Quantitative daylight, energy, thermal, wind, water and carbon claims require an identified dataset/engine, immutable input basis, assumptions and result evidence. Qualitative design advice remains labelled accordingly.</p><div className="note"><b>Climate uncertainty propagates.</b> A D-confidence flood, weather or air-quality input must remain visible in downstream design and feasibility decisions until resolved.</div></section></div>
  </>;
}
