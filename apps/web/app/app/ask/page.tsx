import AskProjectWorkspaceClient,{type AskProjectRef} from "@/components/AskProjectWorkspaceClient";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

export default async function AskProjectPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.rpc("list_accessible_projects");if(error)throw new Error(error.message);
 const projects=((data||[]) as AskProjectRef[]).map(p=>({...p,access_mode:"internal" as const}));
 const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];
 return <AskProjectWorkspaceClient projects={projects} projectId={project?.id} basePath="/app/ask"/>;
}
