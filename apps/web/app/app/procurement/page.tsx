import {requireWorkspaceUser} from "@/lib/auth";
import ProcurementWorkspaceClient from "@/components/ProcurementWorkspaceClient";
import {emptyProcurementWorkspace,type ProcurementWorkspaceState,type ProjectRow} from "@/components/lifecycle-runtime-types";

export const dynamic="force-dynamic";

type ProcurementState=ProcurementWorkspaceState&{organisation_id?:string;invites?:unknown[]};
export default async function ProcurementPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
 if(projectError)throw new Error(projectError.message);
 const projects=(projectData||[]) as ProjectRow[];
 const params=await searchParams;
 const project=projects.find(p=>p.id===params.project)||projects[0];
 let state:ProcurementState={...emptyProcurementWorkspace,organisation_id:undefined,invites:[]};
 if(project){const {data,error}=await supabase.rpc("list_procurement_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||state) as ProcurementState;}
 return <>
  <div className="topbar"><div><div className="demo">Tender / Procurement / P2P</div><h1>Procurement</h1><div className="subtle">Approved-BOQ tender packages, qualified bidders, controlled bid opening, evidence-hashed evaluation, award-bound POs, receipts and three-way invoice matching.</div></div></div>
  {project?<ProcurementWorkspaceClient projects={projects} projectId={project.id} state={state}/>:<div className="note">No accessible project exists yet.</div>}
  <div className="note"><b>Sealed-bid boundary.</b> Internal users do not receive competitor commercial content until the configured opening time and governed opening action. Vendor submission is handled through a separate vendor-scoped workspace.</div>
 </>;
}
