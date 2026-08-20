export default function QualityGatesAdmin(){
  const gates=[
    ['TYPECHECK','Pull Request','Blocking','Configured'],
    ['TESTS','Pull Request','Blocking','Configured'],
    ['SECURITY','Pull Request','Blocking','Configured'],
    ['PROD_BUILD','Pull Request','Blocking','Configured'],
    ['RUNTIME_SMOKE','Production','Blocking','Configured']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Quality Gates</div><h1>Release Quality Gates</h1><div className="subtle">Define evidence-bearing gates by stage and criticality. Blocking gates cannot be bypassed without an auditable, authorised waiver.</div></div></div>
    <div className="panel"><table><thead><tr><th>Gate</th><th>Stage</th><th>Behaviour</th><th>State</th></tr></thead><tbody>{gates.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
