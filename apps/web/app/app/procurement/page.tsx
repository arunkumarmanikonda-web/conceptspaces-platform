const tenders=[
  ["TP-001","Civil & Structure","RFQ","8","28 Aug 2026"],
  ["TP-002","Façade Package","Evaluation","5","Closed"],
  ["TP-003","HVAC","Draft","0","06 Sep 2026"],
  ["TP-004","Interior Joinery","Bid Received","7","31 Aug 2026"]
];

export default function ProcurementPage(){
  return <>
    <div className="topbar"><div><div className="demo">Tender / Procurement / P2P</div><h1>Procurement</h1><div className="subtle">BOQ-linked packages, vendor KYC, bid comparison and award governance</div></div><button className="btn">Create Tender</button></div>
    <div className="kpis">{[["Open Packages","07"],["Qualified Vendors","36"],["Bids Received","18"],["Under Evaluation","03"],["Awarded","04"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Tender Packages</h3><table className="table"><thead><tr><th>Package</th><th>Title</th><th>Status</th><th>Vendors</th><th>Bid Due</th></tr></thead><tbody>{tenders.map(row=><tr key={row[0]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td><td>{row[3]}</td><td>{row[4]}</td></tr>)}</tbody></table></section>
    <div className="panel-grid"><section className="panel"><h3>Evaluation Basis</h3><p className="subtle">Normalised BOQ rates, exclusions, technical deviations, commercial deviations, delivery commitments, vendor KYC and historical performance are evaluated separately before award recommendation.</p></section><section className="panel"><h3>Vendor Governance</h3><p className="subtle">GSTIN / PAN / Udyam fields, KYC status, categories, suspension/blacklist controls and award history are designed into the vendor master.</p></section></div>
  </>;
}
