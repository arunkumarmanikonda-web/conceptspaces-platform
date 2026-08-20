import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { canonicalRegulaInput,evaluateRegula,type RegulaInput } from "../_shared/regula.ts";
import { sha256Hex } from "../_shared/providers.ts";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply({error:"method_not_allowed"},405);const auth=req.headers.get("authorization")||"";if(!auth.startsWith("Bearer "))return reply({error:"authentication_required"},401);
 let body:{project_id?:string;as_of?:string};try{body=await req.json();}catch{return reply({error:"invalid_json"},400);}const projectId=String(body.project_id||"");if(!/^[0-9a-f-]{36}$/i.test(projectId))return reply({error:"valid_project_id_required"},400);const asOf=/^\d{4}-\d{2}-\d{2}$/.test(String(body.as_of||""))?String(body.as_of):new Date().toISOString().slice(0,10);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});const {data:{user:identity}}=await user.auth.getUser();if(!identity)return reply({error:"authentication_required"},401);
 const {data:prepared,error:prepareError}=await user.rpc("prepare_regula_evaluation",{target_project_id:projectId,target_as_of:asOf});if(prepareError||!prepared)return reply({error:prepareError?.message||"regula_prepare_failed"},403);const input=prepared as RegulaInput;
 try{
  const canonical=canonicalRegulaInput(input);const inputHash=await sha256Hex(canonical);const result=evaluateRegula(input);const resultHash=await sha256Hex(JSON.stringify(result));const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:runId,error:persistError}=await service.rpc("persist_regula_evaluation",{target_project_id:projectId,target_actor_id:identity.id,target_as_of:asOf,target_engine:result.engine,target_engine_version:result.engine_version,target_input_hash:inputHash,target_result_hash:resultHash,target_results:result.findings});if(persistError)throw new Error(persistError.message);
  return reply({ok:true,evaluation_run_id:runId,input_hash:inputHash,result_hash:resultHash,...result});
 }catch(error){return reply({error:error instanceof Error?error.message:"regula_evaluation_failed"},400);}
});
