export default function ChangeImpactPage(){
  const impact=[
    ['Requirement','REQ-HOTEL-042','Banquet capacity / back-of-house'],
    ['Regulation','FIRE-EGRESS-07','Travel distance re-evaluation'],
    ['Architecture','A-L02-118','Plan + core coordination'],
    ['Structure','S-GRID-02','Grid review required'],
    ['MEPF','M-DUCT-14','Riser and plant sizing impact'],
    ['Cost','BOQ-11.4','Estimated +₹18.6 lakh'],
    ['Programme','WBS-DD-04','Estimated +6 days']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Change Impact Engine™</div><h1>Blast Radius & Reversal Cost</h1><div className="subtle">Before a change is approved, trace the downstream requirements, rules, disciplines, documents, model objects, cost, contracts and programme it can disturb.</div></div><button className="btn">Analyse Change</button></div>
    <div className="panel"><table><thead><tr><th>Domain</th><th>Reference</th><th>Impact</th></tr></thead><tbody>{impact.map(r=><tr key={r[0]+r[1]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="grid-3" style={{marginTop:18}}><div className="card"><div className="eyebrow">Decision Reversal Cost™</div><h3>₹28.4 lakh</h3><p>Illustrative only until live project data is connected.</p></div><div className="card"><div className="eyebrow">Criticality</div><h3>C3</h3><p>Professional review required before execution.</p></div><div className="card"><div className="eyebrow">Confidence</div><h3>B</h3><p>Validated inputs; downstream quantities remain provisional.</p></div></div>
  </>;
}
