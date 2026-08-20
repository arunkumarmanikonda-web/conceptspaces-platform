export default function CommissioningPage(){
  const tests=[
    ['CHW-P-01','Chilled water pump','Functional performance','Pass','Accepted'],
    ['FAS-L2','Fire alarm Level 02','Cause & effect','Conditional','Defects open'],
    ['DG-01','Emergency generator','Load test','Pass','Accepted'],
    ['LIFT-03','Passenger lift 03','Integrated test','Fail','Blocked']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Commissioning / Handover</div><h1>Systems Commissioning</h1><div className="subtle">Procedures, measured readings, witnesses, defects, acceptance and asset-passport readiness are controlled before operational handover.</div></div><button className="btn">Record Test</button></div>
    <div className="panel"><table><thead><tr><th>System / Asset</th><th>Name</th><th>Test</th><th>Result</th><th>Gate</th></tr></thead><tbody>{tests.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Operations gate.</b> Assets with failed commissioning, missing controlled documents or unresolved critical defects cannot be promoted to operational status.</div>
  </>;
}
