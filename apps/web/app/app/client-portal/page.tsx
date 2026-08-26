import ClientPortalWorkspaceClient,{type ClientPortalInvitation,type ClientPortalProject,type ClientPortalWorkspace} from "@/components/ClientPortalWorkspaceClient";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function ClientPortalPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const [{data:inviteData,error:inviteError},{data:projectData,error:projectError}]=await Promise.all([
  supabase.rpc("list_my_client_portal_invitations"),
  supabase.rpc("list_client_portal_projects")
 ]);
 if(inviteError)throw new Error(inviteError.message);if(projectError)throw new Error(projectError.message);
 const invitations=(inviteData||[]) as ClientPortalInvitation[];const projects=(projectData||[]) as ClientPortalProject[];
 const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state:ClientPortalWorkspace|null=null;
 if(project){const {data,error}=await supabase.rpc("list_client_portal_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=data as ClientPortalWorkspace;}
 return <>
  <div className="topbar"><div><div className="demo">Client Portal / Internal Preview</div><h1>Client Experience</h1><div className="subtle">Preview the same permission-filtered project view an authorised client receives. Internal WIP and unrestricted commercial records are intentionally excluded.</div></div></div>
  <ClientPortalWorkspaceClient projects={projects} invitations={invitations} projectId={project?.id} state={state} basePath="/app/client-portal"/>
 </>;
}
