const packs=[
  ['TYP-HOTEL','Hotel / Resort','4','Review','Operational + key mix + F&B + events'],
  ['TYP-MIXED','Mixed Use','3','Draft','Retail + office + hospitality + circulation'],
  ['TYP-RESI','Residential','5','Review','Unit mix + amenity + efficiency + parking'],
  ['TYP-HOSP','Hospital','2','Draft','Clinical flows + engineering intensity + life safety'],
  ['TYP-RETAIL','Retail / Mall','4','Review','Anchor / vanilla / cinema / F&B / parking']
];

export default function TypologiesAdmin(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Knowledge Governance</div><h1>Typology Knowledge Packs</h1><div className="subtle">Versioned programme, amenity, operational, engineering, sustainability and commercial knowledge packs.</div></div><button className="btn">Create Pack Version</button></div>
    <div className="panel-grid"><section className="panel"><h3>Knowledge Pack Registry</h3><table className="table"><thead><tr><th>Code</th><th>Typology</th><th>Version</th><th>State</th><th>Focus</th></tr></thead><tbody>{packs.map(p=><tr key={p[0]}><td>{p[0]}</td><td>{p[1]}</td><td>{p[2]}</td><td><span className="badge">{p[3]}</span></td><td>{p[4]}</td></tr>)}</tbody></table></section><section className="panel"><h3>Knowledge Promotion</h3><p className="subtle">A knowledge pack is not an uncontrolled AI memory. Sources, benchmark provenance, applicability, professional review and version state remain explicit before publication.</p><div className="note"><b>Principles, not copying.</b> Global precedents may contribute transferable planning or operational principles. Concept Spaces must not clone protected design expression or silently treat precedent as jurisdictional compliance.</div></section></div>
  </>;
}
