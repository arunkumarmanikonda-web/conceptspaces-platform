import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { sendAiSensy,sendFast2Sms,sendResend,type OutboundMessage,type RuntimeMaterial } from "../_shared/providers.ts";

const jsonHeaders={"content-type":"application/json","cache-control":"no-store"};
const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:jsonHeaders});

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return reply({error:"method_not_allowed"},405);
  const auth=req.headers.get("authorization")||"";if(!auth.startsWith("Bearer "))return reply({error:"authentication_required"},401);
  const url=Deno.env.get("SUPABASE_URL")!;const anon=Deno.env.get("SUPABASE_ANON_KEY")!;const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const userClient=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});
  const {data:{user},error:userError}=await userClient.auth.getUser();if(userError||!user)return reply({error:"authentication_required"},401);
  let body:{message_id?:string};try{body=await req.json();}catch{return reply({error:"invalid_json"},400);}const messageId=String(body.message_id||"");if(!/^[0-9a-f-]{36}$/i.test(messageId))return reply({error:"valid_message_id_required"},400);
  const {data:authorized,error:authError}=await userClient.rpc("authorize_provider_dispatch",{target_message_id:messageId});if(authError||authorized!==true)return reply({error:"dispatch_not_authorized"},403);
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:claimed,error:claimError}=await service.rpc("claim_provider_message",{target_message_id:messageId});if(claimError||!claimed)return reply({error:claimError?.message||"message_claim_failed"},409);
  const message=claimed as OutboundMessage;const start=Date.now();
  try{
    const {data:materialData,error:materialError}=await service.rpc("provider_runtime_material",{target_organisation_id:message.organisation_id,target_provider_key:message.provider_key,target_environment:message.environment});
    if(materialError||!materialData)throw new Error(materialError?.message||"provider_material_unavailable");const material=materialData as RuntimeMaterial;
    const result=message.channel==="email"?await sendResend(message,material):message.channel==="whatsapp"?await sendAiSensy(message,material):await sendFast2Sms(message,material);
    await service.rpc("complete_provider_message",{target_message_id:message.id,target_status:result.status,target_provider_message_id:result.providerMessageId||null,target_error:null});
    await service.rpc("record_provider_health",{target_provider_key:message.provider_key,target_environment:message.environment,target_status:"healthy",target_latency_ms:Date.now()-start,target_error_code:null});
    return reply({ok:true,message_id:message.id,provider:message.provider_key,status:result.status,provider_message_id:result.providerMessageId||null});
  }catch(error){
    const code=error instanceof Error?error.message.slice(0,240):"provider_dispatch_failed";
    await service.rpc("complete_provider_message",{target_message_id:message.id,target_status:"failed",target_provider_message_id:null,target_error:{code}});
    await service.rpc("record_provider_health",{target_provider_key:message.provider_key,target_environment:message.environment,target_status:"degraded",target_latency_ms:Date.now()-start,target_error_code:code.slice(0,120)});
    return reply({error:code,message_id:message.id},502);
  }
});
