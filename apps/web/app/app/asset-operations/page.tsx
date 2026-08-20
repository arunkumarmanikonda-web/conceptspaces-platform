export default function AssetOperationsPage(){
  const assets=[
    ['AHU-02-01','Air Handling Unit','Active','Telemetry verified','PM due 14 Sep'],
    ['FIRE-P-01','Fire Pump','Active','No telemetry','Statutory due 01 Sep'],
    ['LIFT-03','Passenger Lift','Commissioning','Disabled','Handover blocked']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Digital Twin / Building Passport</div><h1>Asset Operations</h1><div className="subtle">Commissioned assets, material passports, warranties, documents, model bindings, telemetry and maintenance obligations continue the project graph into operations.</div></div><button className="btn">Add Work Order</button></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">Passport</div><h3>Asset Identity</h3><p>Manufacturer, model, serial, location, warranty, commissioning and controlled documents.</p></div>
      <div className="card"><div className="eyebrow">Twin</div><h3>Telemetry Binding</h3><p>External telemetry is bound to a verified asset identity and schema.</p></div>
      <div className="card"><div className="eyebrow">Maintenance</div><h3>Lifecycle Work</h3><p>Preventive, predictive, corrective and statutory work orders retain evidence.</p></div>
    </div>
    <div className="panel" style={{marginTop:18}}><table><thead><tr><th>Asset</th><th>Type</th><th>Status</th><th>Twin</th><th>Next Action</th></tr></thead><tbody>{assets.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
