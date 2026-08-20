export default function PresentationsPage(){
  const decks=[
    ['Client Concept Presentation','P03','PPTX + PDF','Approved'],
    ['Feasibility Options Board','P02','PPTX + PDF','For Review'],
    ['Interior Design DNA','P05','PPTX + PDF','Draft'],
    ['Investor / Lender Data Room Summary','P01','PDF','Draft']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Project Intelligence / Presentations</div><h1>Client & Stakeholder Presentations</h1><div className="subtle">Controlled presentations generated from the same project graph as drawings, reports, costs and approvals.</div></div><button className="btn">New Presentation</button></div>
    <div className="panel"><table><thead><tr><th>Presentation</th><th>Revision</th><th>Output</th><th>Status</th></tr></thead><tbody>{decks.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Single source principle.</b> A deck cannot silently diverge from the underlying project facts. Regeneration records the exact snapshot and template version used.</div>
  </>;
}
