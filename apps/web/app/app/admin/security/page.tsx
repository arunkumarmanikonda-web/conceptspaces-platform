export default function SecurityAdmin(){
  const findings=[
    ['SEC-041','Dependency','High','Remediating','Due before production activation'],
    ['SEC-040','Configuration','Medium','Open','CSP hardening review'],
    ['SEC-039','Secret scan','Critical','Verified','No committed secret']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Security</div><h1>Security Assurance</h1><div className="subtle">Findings, remediation, evidence, time-bounded risk acceptance and compensating controls remain visible to authorised security governance.</div></div></div>
    <div className="panel"><table><thead><tr><th>Finding</th><th>Source</th><th>Severity</th><th>Status</th><th>Control</th></tr></thead><tbody>{findings.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Critical-risk rule.</b> A critical security finding cannot be silently waived. Acceptance requires named authority, explicit compensating controls, an expiry date and recurring review.</div>
  </>;
}
