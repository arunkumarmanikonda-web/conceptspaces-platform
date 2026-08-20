const sources=[
  ["Project Truth","Plot area / verified source","B"],
  ["REGULA™","Applicable setback rule","A"],
  ["CDE","A-101 / P03","A"],
  ["Commercial","Contract milestone 02","A"]
];

export default function AskProjectPage(){
  return <>
    <div className="topbar"><div><div className="demo">Ask Your Project™</div><h1>Grounded Project Intelligence</h1><div className="subtle">Answers from the Project Graph, not from model memory</div></div><button className="btn">New Conversation</button></div>
    <div className="panel-grid"><section className="panel"><h3>Ask</h3><div className="note" style={{marginTop:0}}><b>Example:</b> “What is blocking the next architecture release, what changed this week, and which client decisions are overdue?”</div><div className="field" style={{marginTop:18}}><textarea rows={7} placeholder="Ask anything about this project…"/></div><button className="btn" style={{marginTop:14}}>Run Grounded Query</button></section><section className="panel"><h3>Answer Policy</h3><p className="subtle">Every substantive answer must cite project resources and their versions. If evidence conflicts, the conflict is surfaced. If a critical fact is unknown, the answer states Not Verified. C3/C4 responses are advisory only and can never constitute professional approval.</p></section></div>
    <section className="panel" style={{marginTop:16}}><h3>Evidence Sources / Illustrative</h3><table className="table"><thead><tr><th>Domain</th><th>Resource</th><th>Confidence</th></tr></thead><tbody>{sources.map(row=><tr key={row[1]}><td>{row[0]}</td><td>{row[1]}</td><td><span className="badge">{row[2]}</span></td></tr>)}</tbody></table></section>
  </>;
}
