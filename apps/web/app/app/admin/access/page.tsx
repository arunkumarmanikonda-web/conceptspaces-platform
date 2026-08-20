const roles=[
  ["Super Admin","Platform-wide","C4 approvals excluded unless professionally eligible"],
  ["Lead Architect","Project-scoped","Design coordination + client SPOC"],
  ["Structural Engineer","Discipline-scoped","Structural review + evidence"],
  ["Finance","Organisation-scoped","Invoices, receipts, reconciliation"],
  ["Client","Project-scoped","Portal, approvals, commercial visibility"]
];

export default function AccessPage(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Access Control</div><h1>Identity & Authority</h1><div className="subtle">RBAC + project scope + discipline + criticality + professional eligibility</div></div><button className="btn">Invite User</button></div>
    <div className="kpis">{[["Active Users","12"],["Pending Invites","03"],["Professional Credentials","08"],["Access Reviews Due","01"],["Privileged Roles","04"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="panel-grid"><section className="panel"><h3>Role Catalogue</h3><table className="table"><thead><tr><th>Role</th><th>Default Scope</th><th>Authority Note</th></tr></thead><tbody>{roles.map(row=><tr key={row[0]}>{row.map(cell=><td key={cell}>{cell}</td>)}</tr>)}</tbody></table></section><section className="panel"><h3>Authority Principle</h3><p className="subtle">A role never grants authority beyond professional eligibility. A Super Admin may configure the platform but cannot impersonate a discipline signatory or bypass a C3/C4 professional release gate.</p></section></div>
  </>;
}
