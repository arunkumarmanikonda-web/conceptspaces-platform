import ClientPortalWorkspaceClient,{type ClientPortalInvitation,type ClientPortalProject,type ClientPortalWorkspace} from "@/components/ClientPortalWorkspaceClient";
import {requireAuthenticatedUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function ExternalClientPortalPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase,user}=await requireAuthenticatedUser();
 const [{data:inviteData,error:inviteError},{data:projectData,error:projectError}]=await Promise.all([
  supabase.rpc("list_my_client_portal_invitations"),
  supabase.rpc("list_client_portal_projects")
 ]);
 if(inviteError)throw new Error(inviteError.message);if(projectError)throw new Error(projectError.message);
 const invitations=(inviteData||[]) as ClientPortalInvitation[];const projects=((projectData||[]) as ClientPortalProject[]).filter(p=>p.access_mode==="client");
 const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state:ClientPortalWorkspace|null=null;
 if(project){const {data,error}=await supabase.rpc("list_client_portal_workspace",{target_project_id:project.id});if(error)throw new Error(error.message);state=data as ClientPortalWorkspace;}
 return <main className="main" style={{maxWidth:1440,margin:"0 auto",padding:"24px"}}>
  <div className="topbar"><div><div className="demo">Concept Spaces / Client Access</div><h1>Project Portal</h1><div className="subtle">Authenticated as {user.email||"client user"}. Only explicitly authorised project information is available here.</div></div></div>
  <ClientPortalWorkspaceClient projects={projects} invitations={invitations} projectId={project?.id} state={state} basePath="/client"/>
 </main>;
}
