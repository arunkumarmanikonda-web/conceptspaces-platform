import {requireWorkspaceUser} from "@/lib/auth";
import DesignGenomeClient,{type LearningProject,type LearningWorkspaceState} from "@/components/DesignGenomeClient";

export const dynamic="force-dynamic";
const emptyState:LearningWorkspaceState={is_platform_admin:false,signals:[],candidates:[],events:[]};

export default async function LearningPage(){
  const {supabase}=await requireWorkspaceUser();
  const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
  if(projectError)throw new Error(projectError.message);
  const {data:learningData,error:learningError}=await supabase.rpc("list_learning_workspace");
  if(learningError)throw new Error(learningError.message);
  const projects=(projectData||[]) as LearningProject[];
  const state=(learningData||emptyState) as LearningWorkspaceState;

  return <>
    <div className="topbar"><div><div className="demo">Design Genome™ / Governed Learning Runtime</div><h1>Learn Without Self-Corruption</h1><div className="subtle">Turn verified project outcomes into reusable principles through evidence, privacy, expert review, benchmark, shadow operation and reversible controlled production.</div></div></div>
    <DesignGenomeClient projects={projects} state={state}/>
  </>;
}
