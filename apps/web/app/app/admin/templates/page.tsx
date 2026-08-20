export default function TemplatesAdmin(){
  const templates=[
    ['CS-PROPOSAL-01','Proposal','v6','PDF + DOCX','Locked'],
    ['CS-CONTRACT-01','Contract','v4','PDF + DOCX','Locked'],
    ['CS-CLIENT-DECK-01','Client Presentation','v5','PPTX + PDF','Locked'],
    ['CS-PROGRESS-01','Progress Report','v3','PDF + XLSX','Review'],
    ['CS-HANDOVER-01','Handover Pack','v2','PDF + ZIP','Draft']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Templates</div><h1>Template Registry</h1><div className="subtle">Versioned, approved and checksum-locked templates for controlled platform outputs.</div></div><button className="btn">Register Template</button></div>
    <div className="panel"><table><thead><tr><th>Code</th><th>Kind</th><th>Version</th><th>Formats</th><th>State</th></tr></thead><tbody>{templates.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
  </>;
}
