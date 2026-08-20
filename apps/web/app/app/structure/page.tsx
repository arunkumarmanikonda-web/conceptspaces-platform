const runs=[
  ['STR-LOAD-001','Gravity load model','Deterministic','Completed','B'],
  ['STR-LAT-001','Lateral system study','Physics simulation','Draft','C'],
  ['STR-FND-001','Foundation concept','Rules + engineering review','Pending inputs','D']
];

export default function StructurePage(){
  return <>
    <div className="topbar"><div><div className="demo">Structural Engineering / Governed Computation</div><h1>Structural Intelligence</h1><div className="subtle">Schemes, loads, analysis evidence and professional review. No LLM-only structural result is treated as engineering output.</div></div><button className="btn">New Structural Scheme</button></div>
    <div className="kpis">{[['Active Scheme','01'],['Calculation Runs','03'],['Approved Engines','00'],['Open Assumptions','05'],['Critical Exceptions','00']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Calculation Provenance</h3><table className="table"><thead><tr><th>Run</th><th>Purpose</th><th>Method</th><th>Status</th><th>Confidence</th></tr></thead><tbody>{runs.map(r=><tr key={r[0]}>{r.map((v,i)=><td key={i}>{i===4?<span className="badge">{v}</span>:v}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Release Preconditions</h3><p className="subtle">A structural package cannot progress to professional review unless the calculation run is complete, input/output hashes are present, units and assumptions are explicit, and the exact engine/version is certified or conditionally approved.</p><div className="note"><b>Human authority remains mandatory.</b> C3/C4 structural releases require a credential-eligible structural professional review bound to the exact resource hash.</div></section></div>
  </>;
}
