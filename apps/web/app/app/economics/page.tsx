const scenarios=[
  ['DEV-A','Balanced Yield','₹128 Cr','₹167 Cr','18.6%','B'],
  ['DEV-B','Maximum FAR','₹149 Cr','₹191 Cr','17.2%','C'],
  ['DEV-C','Lower Capex','₹112 Cr','₹144 Cr','19.1%','C']
];

export default function EconomicsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Development Economics / Decision Intelligence</div><h1>Development Economics</h1><div className="subtle">Compare yield, capex, value, programme, operating assumptions and sensitivity without disguising uncertain inputs as precise forecasts.</div></div><button className="btn">New Scenario</button></div>
    <div className="kpis">{[['Scenarios','03'],['Selected','00'],['Assumptions','27'],['D-Confidence','02'],['VE Options','06']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Scenario Comparison</h3><table className="table"><thead><tr><th>Code</th><th>Scenario</th><th>Development Cost</th><th>Gross Value</th><th>Indicative IRR</th><th>Confidence</th></tr></thead><tbody>{scenarios.map(s=><tr key={s[0]}><td>{s[0]}</td><td>{s[1]}</td><td>{s[2]}</td><td>{s[3]}</td><td>{s[4]}</td><td><span className="badge">{s[5]}</span></td></tr>)}</tbody></table></section><section className="panel"><h3>Decision Discipline</h3><p className="subtle">Every economic assumption stores category, unit, effective date, source and confidence. IRR/NPV/value metrics are outputs of a disclosed assumption set, not facts about the future.</p><div className="note"><b>Sensitivity is mandatory before selection.</b> Material changes in construction cost, sale/rent assumptions, absorption, finance cost, duration or regulatory yield must be visible before a scenario is promoted.</div></section></div>
  </>;
}
