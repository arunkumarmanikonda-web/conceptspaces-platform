import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import TransactionalMessagingClient,{type MessageRow,type ProjectChoice} from "@/components/TransactionalMessagingClient";

export const dynamic="force-dynamic";
type Org={id:string;name:string;role_code:string};

export default async function CommunicationsPage({searchParams}:{searchParams:Promise<{org?:string}>}){
  const {supabase}=await requireWorkspaceUser();const {data:orgData,error:orgError}=await supabase.rpc("list_user_organisations");if(orgError)throw new Error(orgError.message);const orgs=(orgData||[]) as Org[];const params=await searchParams;const org=orgs.find(o=>o.id===params.org)||orgs[0];let projects:ProjectChoice[]=[];let messages:MessageRow[]=[];
  if(org){const [{data:projectData,error:projectError},{data:messageData,error:messageError}]=await Promise.all([supabase.rpc("list_accessible_projects_for_org",{target_organisation_id:org.id}),supabase.rpc("list_provider_messages",{target_organisation_id:org.id,target_limit:100})]);if(projectError)throw new Error(projectError.message);if(messageError)throw new Error(messageError.message);projects=(projectData||[]) as ProjectChoice[];messages=(messageData||[]) as MessageRow[];}
  const queued=messages.filter(m=>m.status==="queued"||m.status==="processing").length;const sent=messages.filter(m=>["accepted","sent","delivered"].includes(m.status)).length;const failed=messages.filter(m=>m.status==="failed").length;
  return <>
    <div className="topbar"><div><div className="demo">Live Communications Runtime</div><h1>Communications</h1><div className="subtle">Transactional email, WhatsApp and SMS with encrypted provider credentials, idempotent dispatch and delivery evidence.</div></div></div>
    <section className="panel"><h3>Organisation</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{orgs.map(o=><Link key={o.id} href={`/app/communications?org=${o.id}`} className={org?.id===o.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{o.name}</Link>)}</div></section>
    <div className="kpis" style={{marginTop:16}}>{[["Queued",String(queued)],["Sent / Accepted",String(sent)],["Failed",String(failed)],["Projects",String(projects.length)],["Messages",String(messages.length)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live database</div></div>)}</div>
    {org?<div style={{marginTop:18}}><TransactionalMessagingClient organisationId={org.id} projects={projects} messages={messages}/></div>:<div className="note" style={{marginTop:18}}>No active organisation membership is available.</div>}
  </>;
}
