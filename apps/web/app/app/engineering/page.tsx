import Link from "next/link";

const disciplines=[
  ['Architecture','/app/architecture','Spatial programme, zoning, drawings, models and requirement coverage.'],
  ['Interiors','/app/interiors','Design DNA, room packages, materials, joinery, lighting and approvals.'],
  ['Structure','/app/structure','Schemes, loads, solver provenance, calculations and professional review.'],
  ['MEPF Systems','/app/mep','Mechanical, electrical, plumbing, fire, ELV, BMS and vertical transport.'],
  ['Coordination','/app/coordination','Cross-discipline dependencies, clashes, deviations and blast radius.']
];

export default function EngineeringPage(){
  return <>
    <div className="topbar"><div><div className="demo">Engineering / Discipline Command</div><h1>Integrated Engineering</h1><div className="subtle">One governed path from design intent through discipline computation, coordination, review and release evidence.</div></div><Link href="/app/admin/engineering-engines" className="btn">Engine Registry</Link></div>
    <div className="grid-3">{disciplines.map(([name,href,desc],index)=><Link href={href} className="card" key={name}><div className="eyebrow">0{index+1}</div><h3>{name}</h3><p>{desc}</p><span className="badge">Open Workspace</span></Link>)}</div>
    <div className="panel" style={{marginTop:18}}><h3>Engineering Trust Chain</h3><p className="subtle">Verified Project Truth → explicit design criteria → certified engine/version where computation is required → reproducible calculation evidence → cross-discipline coordination → credential-eligible professional review → Release Safety Case.</p></div>
  </>;
}
