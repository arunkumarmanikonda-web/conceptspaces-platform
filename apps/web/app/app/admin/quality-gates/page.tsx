import {revalidatePath} from "next/cache";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

async function setGate(formData:FormData){"use server";const {supabase}=await requireWorkspaceUser();const id=String(formData.get("id")||"");const enabled=String(formData.get("enabled"))==="true";const {error}=await supabase.from("quality_gate_definitions").update({enabled}).eq("id",id);if(error)throw new Error(error.message);revalidatePath("/app/admin/quality-gates");}

export default async function QualityGatesAdmin(){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.from("quality_gate_definitions").select("*").order("stage").order("code");if(error)throw new Error(error.message);const gates=data||[];
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / Live Quality Gates</div><h1>Release Quality Gates</h1><div className="subtle">Persisted evidence requirements used for commit, preview, production and release assurance.</div></div></div>
  <div className="kpis">{[["Configured",gates.length],["Enabled",gates.filter(g=>g.enabled).length],["Blocking",gates.filter(g=>g.blocking&&g.enabled).length]].map(([l,v])=><div className="kpi" key={String(l)}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live database state</div></div>)}</div>
  <div className="panel" style={{marginTop:16,overflowX:"auto"}}><table className="table"><thead><tr><th>Gate</th><th>Stage</th><th>Behaviour</th><th>Evidence</th><th>State</th><th>Action</th></tr></thead><tbody>{gates.map(g=><tr key={g.id}><td><b>{g.code}</b><div className="subtle">{g.name}</div></td><td>{g.stage}</td><td>{g.blocking?"Blocking":"Advisory"}</td><td>{(g.evidence_required||[]).join(", ")}</td><td><span className="badge">{g.enabled?"enabled":"disabled"}</span></td><td><form action={setGate}><input type="hidden" name="id" value={g.id}/><input type="hidden" name="enabled" value={String(!g.enabled)}/><button className="btn ghost">{g.enabled?"Disable":"Enable"}</button></form></td></tr>)}</tbody></table></div>
 </>;
}
