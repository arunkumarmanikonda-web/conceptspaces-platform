import Link from "next/link";

export default function NotFound(){
  return <main style={{minHeight:'100vh',display:'grid',placeItems:'center',background:'#F6F7F8',fontFamily:'Inter,Arial,sans-serif',color:'#0F1D33'}}><section style={{maxWidth:620,padding:40,background:'#fff',border:'1px solid #E1E4E8'}}><div style={{fontSize:11,letterSpacing:'.18em',color:'#3D6DF0'}}>404 / PROJECT GRAPH</div><h1 style={{fontWeight:450,fontSize:42}}>This resource is not in the current graph.</h1><p style={{color:'#65707B',lineHeight:1.7}}>The route may have moved, been superseded or may require project access.</p><Link href="/app" style={{display:'inline-block',padding:'12px 18px',background:'#0F1D33',color:'#fff'}}>Return to Command Centre</Link></section></main>;
}
