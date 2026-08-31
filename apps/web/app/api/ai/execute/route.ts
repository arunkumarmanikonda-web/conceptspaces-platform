import {createHash} from "node:crypto";
import {generateText} from "ai";
import {NextResponse} from "next/server";
import {createServerSupabaseClient} from "@/lib/supabase-server";

export const runtime="nodejs";
export const dynamic="force-dynamic";

type ExecuteBody={organisation_id?:string;project_id?:string;agent_code?:string;model_profile_id?:string;criticality?:string;input?:string;input_ref?:string;evidence_refs?:unknown[]};

export async function POST(request:Request){
 const supabase=await createServerSupabaseClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:"authentication_required"},{status:401});
 let body:ExecuteBody;try{body=await request.json();}catch{return NextResponse.json({error:"invalid_json"},{status:400});}
 const organisationId=String(body.organisation_id||"");const projectId=String(body.project_id||"");const agentCode=String(body.agent_code||"");const modelProfileId=String(body.model_profile_id||"");const criticality=String(body.criticality||"C1").toUpperCase();const input=String(body.input||"").trim();const evidence=Array.isArray(body.evidence_refs)?body.evidence_refs:[];
 if(!organisationId||!projectId||!agentCode||!modelProfileId||!input)return NextResponse.json({error:"organisation_project_agent_model_and_input_required"},{status:400});
 if(input.length>50000)return NextResponse.json({error:"input_too_large"},{status:413});
 const [{data:model,error:modelError},{data:prompt,error:promptError}]=await Promise.all([
  supabase.schema("ai").from("model_profiles").select("id,provider,model,enabled").eq("id",modelProfileId).eq("enabled",true).single(),
  supabase.schema("ai").from("prompt_versions").select("id,template,status").eq("agent_code",agentCode).eq("status","active").order("version",{ascending:false}).limit(1).single()
 ]);
 if(modelError||promptError||!model||!prompt)return NextResponse.json({error:"approved_model_and_active_prompt_required"},{status:409});
 const {data:runId,error:startError}=await supabase.rpc("start_ai_agent_run",{target_organisation_id:organisationId,target_project_id:projectId,target_agent_code:agentCode,target_model_profile_id:modelProfileId,target_criticality:criticality,target_input_ref:String(body.input_ref||"inline:governed-request"),target_evidence_refs:evidence});
 if(startError||!runId)return NextResponse.json({error:startError?.message||"ai_run_start_failed"},{status:403});
 try{
  const result=await generateText({model:`${model.provider}/${model.model}`,system:String(prompt.template),prompt:input,providerOptions:{gateway:{user:user.id,tags:[`feature:conceptspaces`,`agent:${agentCode}`,`criticality:${criticality}`],disallowPromptTraining:true,zeroDataRetention:true}}});
  if(!result.text)throw new Error("gateway_returned_no_text");const hash=createHash("sha256").update(result.text).digest("hex");
  const {data:completion,error:completeError}=await supabase.rpc("complete_ai_agent_run",{target_run_id:runId,target_succeeded:true,target_output_ref:`ai-run://${runId}`,target_output_payload:{text:result.text,response_id:result.response.id,model:`${model.provider}/${model.model}`,finish_reason:result.finishReason,usage:result.totalUsage,warnings:result.warnings},target_authoritative:false,target_output_hash:hash});
  if(completeError)throw new Error(completeError.message);return NextResponse.json({ok:true,run_id:runId,output:result.text,output_hash:hash,governance:completion});
 }catch(error){await supabase.rpc("complete_ai_agent_run",{target_run_id:runId,target_succeeded:false,target_output_ref:"",target_output_payload:{error:error instanceof Error?error.message:"gateway_execution_failed"},target_authoritative:false,target_output_hash:undefined});return NextResponse.json({error:"ai_gateway_execution_failed",run_id:runId},{status:502});}
}
