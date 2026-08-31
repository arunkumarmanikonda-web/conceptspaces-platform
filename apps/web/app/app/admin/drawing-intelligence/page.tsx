import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";
type ReferencePack={id:string;name:string;typology:string;source_title:string;source_checksum:string;status:string;extracted_features:Record<string,unknown>;design_principles:unknown[];created_at:string};
function pretty(value:string){return value.replaceAll("_"," ").replace(/\b\w/g,c=>c.toUpperCase());}

export default async function DrawingIntelligencePage(){
 const {supabase}=await requireWorkspaceUser();const {data,error}=await supabase.from("drawing_reference_packs").select("*").order("created_at",{ascending:false});if(error)throw new Error(error.message);const packs=(data||[]) as ReferencePack[];
 return <><div className="topbar"><div><div className="demo">Super Admin / Drawing Intelligence</div><h1>Drawing Reference Intelligence</h1><div className="subtle">Private, provenance-bound architectural references converted into explicit spatial rules. References guide preliminary generation but never become statutory or construction authority.</div></div></div>
 <div className="kpis">{[["Reference Packs",packs.length],["Active",packs.filter(p=>p.status==="active_reference").length],["Residential",packs.filter(p=>p.typology==="residential").length],["Unverified",packs.filter(p=>p.status!=="active_reference").length]].map(([l,v])=><div className="kpi" key={String(l)}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Governed registry</div></div>)}</div>
 {packs.map(pack=><section className="panel" style={{marginTop:18}} key={pack.id}><div style={{display:"flex",justifyContent:"space-between",gap:16,flexWrap:"wrap"}}><div><div className="eyebrow">{pack.typology} / {pretty(pack.status)}</div><h2 style={{margin:"8px 0"}}>{pack.name}</h2><div className="subtle">{pack.source_title}</div></div><span className="badge">SHA-256 {pack.source_checksum.slice(0,12)}…</span></div><div className="panel-grid"><div><h3>Extracted spatial grammar</h3><pre style={{whiteSpace:"pre-wrap",fontSize:12,lineHeight:1.6}}>{JSON.stringify(pack.extracted_features,null,2)}</pre></div><div><h3>Generation principles</h3><ol>{pack.design_principles.map((p,i)=><li key={i} style={{marginBottom:10}}>{String(p)}</li>)}</ol></div></div><div className="note"><b>Use boundary:</b> This pack is approved as a design reference only. Dimensions, setbacks, structure, fire/life-safety, services and release still require project evidence and professional review.</div></section>)}
 {!packs.length&&<div className="note">No drawing reference has been ingested.</div>}</>;
}
