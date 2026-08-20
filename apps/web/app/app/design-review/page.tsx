export default function DesignReviewPage(){
  const reviews=[
    ['Design Council','Architecture + programme','2 warnings','Review Required'],
    ['Red Team','Regulation + life safety','0 critical / 1 major','Review Required'],
    ['Constructability','Structure + MEPF','3 coordination issues','Open'],
    ['Operability','Plant + maintenance access','1 major','Open'],
    ['Maintainability','Interior/MEP access','0 major','Accepted']
  ];
  return <>
    <div className="topbar"><div><div className="demo">AI Design Review Council / Red Team</div><h1>Adversarial Design Review</h1><div className="subtle">Independent review agents challenge assumptions, compliance, constructability, operability and maintainability before people approve critical outcomes.</div></div><button className="btn">Run Review</button></div>
    <div className="panel"><table><thead><tr><th>Review</th><th>Focus</th><th>Findings</th><th>Status</th></tr></thead><tbody>{reviews.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Independence rule.</b> The agent that generated an option is not sufficient as its sole reviewer. Critical findings remain unresolved until evidence and accountable human review close them.</div>
  </>;
}
