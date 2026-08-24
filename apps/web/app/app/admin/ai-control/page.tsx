import {requireWorkspaceUser} from "@/lib/auth";
import AIControlGovernanceClient from "@/components/AIControlGovernanceClient";

export const dynamic="force-dynamic";

export default async function AIControlPage(){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.rpc("list_ai_control_workspace");
 if(error)throw new Error(error.message);
 const workspace=(data||{agents:[],models:[],prompts:[],evaluation_cases:[],evaluation_results:[],learning_candidates:[]}) as any;
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / AI Governance</div><h1>AI Control Plane</h1><div className="subtle">Governed models, agents, prompts, evaluations, autonomy and evidence-based activation. Missing evidence fails closed.</div></div></div>
  <AIControlGovernanceClient workspace={workspace}/>
 </>;
}
