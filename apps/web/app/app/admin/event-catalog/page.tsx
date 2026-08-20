export default function EventCatalog(){
  const defs=[
    ['project.truth.changed','1','project','C2','Replayable'],
    ['regulation.impact.detected','1','regula','C3','Replayable'],
    ['design.release.issued','1','assurance','C4','Manual only'],
    ['payment.captured','1','finance','C2','No replay']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Event Catalog</div><h1>Domain Event Registry</h1><div className="subtle">Govern event names, versions, domain ownership, criticality, retention, PII class and replay policy.</div></div><button className="btn">Register Event</button></div>
    <div className="panel"><table><thead><tr><th>Event</th><th>Version</th><th>Owner</th><th>Criticality</th><th>Replay</th></tr></thead><tbody>{defs.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
