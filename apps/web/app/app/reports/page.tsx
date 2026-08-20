export default function ReportsPage(){
  const reports=[
    ['Feasibility Decision Report','P02','Approved','Project Truth + REGULA + Economics'],
    ['Design Development Report','P04','For Review','Requirements + Architecture + Engineering'],
    ['Monthly Progress Report','M06','Draft','Site + Cost + Risk + Programme'],
    ['Release Safety Case','C03','Approved','Assurance Ledger + Reviews + Evidence']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Project Intelligence / Reporting</div><h1>Governed Reports</h1><div className="subtle">Generate branded reports from immutable project snapshots with explicit provenance, revision and approval status.</div></div><button className="btn">Generate Report</button></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">Snapshot</div><h3>Project Truth</h3><p>Facts, assumptions, decisions and requirements frozen at report time.</p></div>
      <div className="card"><div className="eyebrow">Template</div><h3>Version Locked</h3><p>Only approved, checksum-locked template versions may produce controlled outputs.</p></div>
      <div className="card"><div className="eyebrow">Issue</div><h3>Proof Before Publish</h3><p>Critical defects and missing approvals block issue.</p></div>
    </div>
    <div className="panel" style={{marginTop:18}}><table><thead><tr><th>Report</th><th>Revision</th><th>Status</th><th>Source Snapshot</th></tr></thead><tbody>{reports.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
