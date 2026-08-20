export default function DesignLinterPage(){
  const findings=[
    ['DL-ARCH-021','Architecture','Dead-end corridor exceeds preferred limit','Warning','Open'],
    ['DL-FIRE-004','Fire','Unverified door rating at protected stair','Critical','Open'],
    ['DL-MEP-017','MEPF','Maintenance clearance conflict','Error','Open'],
    ['DL-INT-011','Interiors','Wet-area finish slip rating not verified','Warning','Open']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Design Linter™</div><h1>Continuous Design Checks</h1><div className="subtle">Run deterministic and governed rule checks against project objects before issues become drawing, procurement or site problems.</div></div><button className="btn">Run Linter</button></div>
    <div className="panel"><table><thead><tr><th>Rule</th><th>Discipline</th><th>Finding</th><th>Severity</th><th>Status</th></tr></thead><tbody>{findings.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Source-aware linting.</b> Regulatory rules, professional checks and preferred design heuristics remain distinct. A heuristic warning can never masquerade as statutory non-compliance, and an unverified statutory input remains Not Verified.</div>
  </>;
}
