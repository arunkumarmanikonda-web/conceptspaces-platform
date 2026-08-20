import Link from "next/link";

export default function CompilerPage(){
  const stages=[
    ['01','Project Truth','Validated inputs and uncertainty'],['02','REGULA™','Applicable jurisdiction rules'],['03','Programme','Typology and requirements'],
    ['04','Feasibility','Development envelope and economics'],['05','Option Generation','Pareto exploration'],['06','Architecture','Spatial and drawing intelligence'],
    ['07','Engineering','Structure + MEPF deterministic checks'],['08','Interiors','Design DNA and execution packages'],['09','Cost','QTO / BOQ / value engineering'],
    ['10','Coordination','Clash + dependency impact'],['11','Assurance','Proof Before Publish']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Building Compiler™ / Command</div><h1>Compile the Project</h1><div className="subtle">One governed compilation chain from project truth and intent to coordinated design, engineering, cost and release evidence.</div></div><Link className="btn" href="/app/projects/new">New Input Session</Link></div>
    <div className="grid-3">{stages.map(s=><div className="card" key={s[0]}><div className="eyebrow">{s[0]}</div><h3>{s[1]}</h3><p>{s[2]}</p><span className="badge">Gate Controlled</span></div>)}</div>
    <div className="note" style={{marginTop:18}}><b>Compiler rule.</b> A stage is not “complete” because an AI produced output. Critical stages require deterministic or rule-based validation, evidence, and the applicable human/professional gate.</div>
  </>;
}
