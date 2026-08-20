const lines=[
  ["CIV-001","RCC M30","m³","1,280.45","₹ 8,950","B"],
  ["MASON-014","AAC Blockwork 150mm","m²","4,920.20","₹ 1,180","B"],
  ["FIN-041","Natural Stone Flooring","m²","2,340.00","₹ 3,850","C"],
  ["MEP-072","HVAC System Allowance","LS","1","₹ 2.85 Cr","C"]
];

export default function CostPage(){
  return <>
    <div className="topbar"><div><div className="demo">QTO / BOQ / Cost Intelligence</div><h1>Cost & Quantity</h1><div className="subtle">Traceable quantities, rates, confidence and design-to-cost impact</div></div><button className="btn">Generate Cost Plan</button></div>
    <div className="kpis">{[["Current Estimate","₹ 38.42 Cr"],["Baseline","₹ 36.90 Cr"],["Variance","+4.1%"],["Model-linked QTO","82%"],["Confidence","B"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value" style={{fontSize:String(v).length>8?18:30}}>{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>BOQ Intelligence</h3><table className="table"><thead><tr><th>Code</th><th>Description</th><th>Unit</th><th>Quantity</th><th>Rate</th><th>Confidence</th></tr></thead><tbody>{lines.map(row=><tr key={row[0]}>{row.map((cell,i)=><td key={cell}>{i===5?<span className="badge">{cell}</span>:cell}</td>)}</tr>)}</tbody></table></section>
    <div className="note"><b>Quantity integrity.</b> Model-derived quantities keep object/source references and confidence. Manual overrides remain explicit and auditable. The system does not silently convert a conceptual allowance into a verified BOQ quantity.</div>
  </>;
}
