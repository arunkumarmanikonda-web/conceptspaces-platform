export default function LearningPage(){
  const stages=[
    ['Observation','Signals collected from approved outcomes'],['Evidence','Enough examples and source quality'],['Privacy Review','Reusable without exposing client data'],
    ['Expert Review','Qualified reviewers assess principle'],['Benchmark','Measured against controlled cases'],['Shadow','Runs without production effect'],
    ['Controlled Production','Bounded use with monitoring and rollback']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Design Genome™ / Learning Promotion</div><h1>Learn Without Self-Corruption</h1><div className="subtle">Approved outcomes can improve the platform only through evidence, privacy review, expert review, benchmarks, shadow operation and reversible promotion.</div></div></div>
    <div className="grid-3">{stages.map((s,i)=><div className="card" key={s[0]}><div className="eyebrow">0{i+1}</div><h3>{s[0]}</h3><p>{s[1]}</p></div>)}</div>
    <div className="note" style={{marginTop:18}}><b>No direct self-training.</b> A client preference, one successful project or an AI-generated output never becomes platform truth by repetition. Outcome evidence must pass the full promotion pipeline and retain rollback capability.</div>
  </>;
}
