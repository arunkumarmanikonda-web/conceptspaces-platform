export default function ReliabilityPage(){
  const slos=[
    ['Web availability','99.95%','30d','Within budget'],
    ['Critical API success','99.90%','30d','Within budget'],
    ['P95 application response','800 ms','7d','Within target'],
    ['Restore readiness','RTO 120m / RPO 60m','Quarterly drill','Evidence required']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Platform Reliability / SRE</div><h1>Reliability & Continuity</h1><div className="subtle">Service objectives, error budgets, restore drills, feature flags and release health make production quality measurable.</div></div></div>
    <div className="panel"><table><thead><tr><th>Objective</th><th>Target</th><th>Window</th><th>State</th></tr></thead><tbody>{slos.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Error-budget policy.</b> Feature velocity is reduced when reliability consumes the approved error budget. Critical assurance functions receive stricter recovery objectives.</div>
  </>;
}
