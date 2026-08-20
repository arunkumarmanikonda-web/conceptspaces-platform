import Link from "next/link";

const lanes=[
  ['Programme Intelligence','/app/programme','Typology-driven spaces, adjacencies, areas and client priorities.'],
  ['Climate & Environment','/app/climate','Solar, daylight, wind, energy, water, flood and carbon context.'],
  ['Development Economics','/app/economics','Yield, capex, value, absorption, sensitivity and value engineering.'],
  ['Site Truth','/app/site-truth','Verified geometry, constraints, source confidence and jurisdiction.'],
  ['Design Intelligence','/app/design','Generate and compare options only after inputs are sufficiently trustworthy.']
];

export default function FeasibilityPage(){
  return <>
    <div className="topbar"><div><div className="demo">Feasibility Intelligence / Pre-Design</div><h1>Development Feasibility</h1><div className="subtle">Convert a site, regulations, client intent, climate and commercial assumptions into a traceable development scenario before design commitment.</div></div><button className="btn">Create Scenario</button></div>
    <div className="kpis">{[['Site Truth','B'],['Programme','Draft'],['Climate Context','C'],['Scenarios','03'],['Critical Unknowns','02']].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Illustrative</div></div>)}</div>
    <div className="grid-3" style={{marginTop:18}}>{lanes.map(([name,href,desc],index)=><Link href={href} className="card" key={name}><div className="eyebrow">0{index+1}</div><h3>{name}</h3><p>{desc}</p><span className="badge">Open Workspace</span></Link>)}</div>
    <div className="panel" style={{marginTop:18}}><h3>Feasibility Trust Chain</h3><p className="subtle">Verified site truth → applicable regulation → programme brief → climate/environmental context → design scenario → cost/value assumptions → sensitivity → decision ledger. A scenario with material D-confidence assumptions is not represented as decision-grade.</p></div>
  </>;
}
