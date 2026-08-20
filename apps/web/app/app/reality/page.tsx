export default function RealityCapturePage(){
  const captures=[
    ['RC-0248','LiDAR','Level 04','Review Required','3 major / 0 critical'],
    ['RC-0247','360','Retail Podium','Accepted','0 major / 0 critical'],
    ['RC-0246','Drone','Roof Services','Review Required','1 major / 1 critical']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Reality Capture / Model-to-Field</div><h1>Drawing-to-Reality Intelligence</h1><div className="subtle">Compare photos, 360 imagery, drones, point clouds and LiDAR against the governed design model. AI detects; qualified people disposition material deviations.</div></div><button className="btn">Register Capture</button></div>
    <div className="panel"><table><thead><tr><th>Capture</th><th>Mode</th><th>Zone</th><th>Status</th><th>Deviation Summary</th></tr></thead><tbody>{captures.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>No autonomous acceptance.</b> A detected geometric or quality deviation is evidence, not a verdict. Major and critical deviations require professional review and may create an NCR or controlled design change.</div>
  </>;
}
