export default function SiteQualityPage(){
  const items=[
    ['ITP-STR-014','Podium slab reinforcement','Hold Point','Approved'],
    ['INS-00284','Level 02 waterproofing','Pass with comments','Verification'],
    ['NCR-00041','Service penetration fire seal','C4','Open'],
    ['CHG-00023','Riser route adjustment','C3','Impact Assessment']
  ];
  return <>
    <div className="topbar"><div><div className="demo">PMC / Quality Assurance</div><h1>Site Quality & Inspections</h1><div className="subtle">Inspection test plans, hold points, measurements, NCRs, corrective action and controlled site changes remain tied to project objects and evidence.</div></div><button className="btn">New Inspection</button></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">ITP</div><h3>Hold & Witness Points</h3><p>Work cannot silently pass a mandatory inspection gate.</p></div>
      <div className="card"><div className="eyebrow">NCR</div><h3>Corrective Action</h3><p>Use-as-is and redesign dispositions require explicit deviation authority.</p></div>
      <div className="card"><div className="eyebrow">Change</div><h3>Blast Radius</h3><p>Site changes trace affected requirements, drawings, model objects, cost and programme.</p></div>
    </div>
    <div className="panel" style={{marginTop:18}}><table><thead><tr><th>Reference</th><th>Subject</th><th>Control</th><th>Status</th></tr></thead><tbody>{items.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
