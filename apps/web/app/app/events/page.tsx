export default function EventsPage(){
  const events=[
    ['project.truth.changed','C2','Published','Project Graph'],
    ['regulation.impact.detected','C3','Pending','REGULA™'],
    ['design.release.requested','C3','Delivered','Assurance'],
    ['payment.captured','C2','Delivered','Finance']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Platform Operations / Event Backbone</div><h1>Event Operations</h1><div className="subtle">Trace domain events, correlation chains, outbox publication, delivery attempts and replay eligibility.</div></div></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">Outbox</div><h3>Transactional Publish</h3><p>Events enter the outbox with immutable payload hashes before asynchronous delivery.</p></div>
      <div className="card"><div className="eyebrow">Idempotency</div><h3>Exactly-once Effect</h3><p>Provider and subscriber side-effects are protected by idempotency records.</p></div>
      <div className="card"><div className="eyebrow">Dead Letter</div><h3>Controlled Replay</h3><p>Failed deliveries are investigated before replay; C4 events never replay automatically.</p></div>
    </div>
    <div className="panel" style={{marginTop:18}}><table><thead><tr><th>Event</th><th>Criticality</th><th>State</th><th>Domain</th></tr></thead><tbody>{events.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
