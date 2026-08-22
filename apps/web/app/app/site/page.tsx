import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";
import SiteProgrammeClient,{emptySiteProgrammeState,type SiteProgrammeState} from "@/components/SiteProgrammeClient";
import SiteDeliveryClient,{emptySiteDeliveryState,type SiteDeliveryState} from "@/components/SiteDeliveryClient";
import RealityVerificationClient from "@/components/RealityVerificationClient";
import {emptyRealityWorkspace,type ProjectRow,type RealityWorkspaceState} from "@/components/lifecycle-runtime-types";

export const dynamic="force-dynamic";

export default async function SitePage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
 if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ProjectRow[];
 const params=await searchParams;
 const project=projects.find(p=>p.id===params.project)||projects[0];
 let programme:SiteProgrammeState=emptySiteProgrammeState;
 let delivery:SiteDeliveryState=emptySiteDeliveryState;
 let reality:RealityWorkspaceState=emptyRealityWorkspace;
 if(project){
   const [programmeResult,deliveryResult,realityResult]=await Promise.all([
     supabase.rpc("list_site_programme_workspace",{target_project_id:project.id}),
     supabase.rpc("list_site_delivery_workspace",{target_project_id:project.id}),
     supabase.rpc("list_reality_workspace",{target_project_id:project.id})
   ]);
   if(programmeResult.error)throw new Error(programmeResult.error.message);
   if(deliveryResult.error)throw new Error(deliveryResult.error.message);
   if(realityResult.error)throw new Error(realityResult.error.message);
   programme=(programmeResult.data||emptySiteProgrammeState) as SiteProgrammeState;
   delivery=(deliveryResult.data||emptySiteDeliveryState) as SiteDeliveryState;
   reality=(realityResult.data||emptyRealityWorkspace) as RealityWorkspaceState;
 }
 return <>
  <div className="topbar"><div><div className="demo">PMC / Construction / Reality Verification</div><h1>Site & Delivery</h1><div className="subtle">Governed programme baselines, field evidence, QA/QC, RFIs, submittals, progress certification, variations, offline control and exact-model reality verification.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/site?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<>
    <SiteProgrammeClient projectId={project.id} state={programme} vendors={delivery.vendors||[]}/>
    <SiteDeliveryClient projectId={project.id} state={delivery}/>
    <RealityVerificationClient projectId={project.id} state={reality}/>
  </>}
  <div className="note" style={{marginTop:16}}><b>Controlled field truth.</b> Superseded offline packages fail closed; inspections and progress require evidence; failed inspections create NCRs; RFIs/submittals retain exact source revision provenance; and reality comparisons are bound to approved model checksums.</div>
 </>;
}
