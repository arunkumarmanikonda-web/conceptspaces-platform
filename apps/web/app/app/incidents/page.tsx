export default function IncidentsPage(){
  const incidents=[
    ['INC-0007','SEV2','Document generation latency','Monitoring','No data loss'],
    ['INC-0006','SEV1','Integration delivery degradation','Closed','Provider isolated'],
    ['INC-0005','SEV3','Preview route regression','Closed','No production impact']
  ];
  return <>
    <div className="topbar"><div><div className="demo">SRE / Incident Command</div><h1>Incident Management</h1><div className="subtle">Declare, command, mitigate, monitor, resolve and learn from production incidents with immutable timelines.</div></div><button className="btn">Declare Incident</button></div>
    <div className="panel"><table><thead><tr><th>Incident</th><th>Severity</th><th>Subject</th><th>Status</th><th>Impact</th></tr></thead><tbody>{incidents.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Postmortem standard.</b> SEV0/SEV1 incidents require a blameless evidence-based postmortem, corrective actions and verification before closure.</div>
  </>;
}
