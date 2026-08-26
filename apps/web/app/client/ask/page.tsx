import AskProjectWorkspaceClient,{type AskProjectRef} from "@/components/AskProjectWorkspaceClient";
import {requireAuthenticatedUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function ClientAskProjectPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireAuthenticatedUser();
 const {data,error}=await supabase.rpc("list_client_portal_projects");if(error)throw new Error(error.message);
 const projects=((data||[]) as AskProjectRef[]).filter(p=>p.access_mode==="client");
 const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];
 return <main className="main" style={{maxWidth:1440,margin:"0 auto",padding:"24px"}}><AskProjectWorkspaceClient projects={projects} projectId={project?.id} basePath="/client/ask"/></main>;
}
