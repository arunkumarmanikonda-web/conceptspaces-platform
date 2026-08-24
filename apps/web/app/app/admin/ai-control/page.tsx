import {requireWorkspaceUser} from "@/lib/auth";
import AIControlGovernanceClient from "@/components/AIControlGovernanceClient";
import AIRuntimeLearningClient,{emptyAIRuntimeWorkspace,type AIRuntimeWorkspace} from "@/components/AIRuntimeLearningClient";

export const dynamic="force-dynamic";

export default async function AIControlPage(){
 const {supabase}=await requireWorkspaceUser();
 const [{data,error},{data:runtimeData,error:runtimeError}]=await Promise.all([
  supabase.rpc("list_ai_control_workspace"),
  supabase.rpc("list_ai_runtime_workspace")
 ]);
 if(error)throw new Error(error.message);
 if(runtimeError)throw new Error(runtimeError.message);
 const workspace=(data||{agents:[],models:[],prompts:[],evaluation_cases:[],evaluation_results:[],learning_candidates:[]}) as any;
 const runtime=(runtimeData||emptyAIRuntimeWorkspace) as AIRuntimeWorkspace;
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / AI Governance</div><h1>AI Control Plane</h1><div className="subtle">Governed models, agents, prompts, evaluations, execution-time criticality, grounding, learning promotion and evidence-based activation. Missing evidence fails closed.</div></div></div>
  <AIControlGovernanceClient workspace={workspace}/>
  <div className="topbar" style={{marginTop:28}}><div><div className="demo">Execution-Time Governance / Learning Promotion</div><h2>Runtime & Learning Authority</h2><div className="subtle">Actual model/agent criticality is rechecked at execution; authoritative ungrounded outputs become Not Verified; learning cannot reach production without privacy, expert, benchmark and rollback gates.</div></div></div>
  <AIRuntimeLearningClient workspace={runtime}/>
 </>;
}
