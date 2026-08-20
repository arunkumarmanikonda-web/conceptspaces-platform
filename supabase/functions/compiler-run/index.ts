import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { compileProject,stableStringify,type CompilerInput } from "../_shared/compiler.ts";
import { sha256Hex } from "../_shared/providers.ts";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply({error:"method_not_allowed"},405);const auth=req.headers.get("authorization")||"";if(!auth.startsWith("Bearer "))return reply({error:"authentication_required"},401);
 let body:{project_id?:string;objective?:string};try{body=await req.json();}catch{return reply({error:"invalid_json"},400);}const projectId=String(body.project_id||"");if(!/^[0-9a-f-]{36}$/i.test(projectId))return reply({error:"valid_project_id_required"},400);const objective=String(body.objective||"balanced").slice(0,120);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});const {data:{user:identity}}=await user.auth.getUser();if(!identity)return reply({error:"authentication_required"},401);
 const {data:authorized,error:authorityError}=await user.rpc("authorize_compiler_runtime",{target_project_id:projectId});if(authorityError||authorized!==true)return reply({error:"project_manage_authority_required"},403);
 const {data:prepared,error:prepareError}=await user.rpc("prepare_compiler_input",{target_project_id:projectId,target_objective:objective});if(prepareError||!prepared)return reply({error:prepareError?.message||"compiler_prepare_failed"},403);const input=prepared as CompilerInput;
 try{
  const canonical=stableStringify(input);const inputHash=await sha256Hex(canonical);const result=compileProject(input);const stagePayload=[] as Array<Record<string,unknown>>;for(const s of result.stages){const stageInputHash=await sha256Hex(`${inputHash}|${s.stage}`);const stageOutputHash=await sha256Hex(stableStringify({stage:s.stage,status:s.status,details:s.details,evidence_refs:s.evidence_refs,assumptions:s.assumptions,engine_refs:s.engine_refs}));stagePayload.push({...s,input_hash:stageInputHash,output_hash:stageOutputHash});}
  const outputHash=await sha256Hex(stableStringify({...result,stages:stagePayload}));const truthHash=await sha256Hex(stableStringify(input.truth||[]));const regulationHash=await sha256Hex(stableStringify(input.regula||{}));const programmeHash=await sha256Hex(stableStringify(input.requirements||[]));const designHash=await sha256Hex(stableStringify(input.discipline_state||{}));
  const snapshot={engine:result.engine,engine_version:result.engine_version,hashes:{project_truth:truthHash,regulation:regulationHash,programme:programmeHash,requirements:programmeHash,design:designHash},source_refs:[...(input.truth||[]).map(x=>String(x.source_reference||`truth:${x.id||x.record_key}`)),...(input.requirements||[]).map(x=>`requirement:${String(x.id||x.code)}`)],summary:result.summary};
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});const {data:runId,error:persistError}=await service.rpc("persist_compiler_run",{target_project_id:projectId,target_actor_id:identity.id,target_objective:objective,target_input_hash:inputHash,target_output_hash:outputHash,target_snapshot:snapshot,target_stages:stagePayload,target_candidates:result.candidates,target_status:result.status,target_blocked_reasons:result.blocked_reasons});if(persistError)throw new Error(persistError.message);
  return reply({ok:true,compilation_run_id:runId,input_hash:inputHash,output_hash:outputHash,...result});
 }catch(error){return reply({error:error instanceof Error?error.message:"compiler_execution_failed"},400);}
});
