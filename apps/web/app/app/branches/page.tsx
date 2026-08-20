export default function BranchesPage(){
  const branches=[
    ['main','Approved design direction','a17f…9c','Active'],
    ['yield-study','Commercial yield alternative','4b02…f1','Active'],
    ['low-carbon','Embodied-carbon alternative','3e91…a8','Active'],
    ['client-option-b','Client-requested branch','88cd…42','Frozen']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Building Git / Branching</div><h1>Project Branches</h1><div className="subtle">Explore alternatives without corrupting the approved project state. Every object-level change has lineage, author and content hash.</div></div><button className="btn">Create Branch</button></div>
    <div className="panel"><table><thead><tr><th>Branch</th><th>Purpose</th><th>Head</th><th>Status</th></tr></thead><tbody>{branches.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Merge control.</b> Branch merge is a governed project change. Conflicting requirements, rules, model objects and approved releases must be explicitly reconciled before merge.</div>
  </>;
}
