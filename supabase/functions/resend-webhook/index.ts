import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { sha256Hex,verifyResendWebhook,type RuntimeMaterial } from "../_shared/providers.ts";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function loadMaterial(service:ReturnType<typeof createClient>,org:string,environment:string){const {data,error}=await service.rpc("provider_runtime_material",{target_organisation_id:org,target_provider_key:"resend",target_environment:environment});if(error||!data)throw new Error(error?.message||"resend_not_configured");return data as RuntimeMaterial;}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return reply({error:"method_not_allowed"},405);const urlObj=new URL(req.url);const org=urlObj.searchParams.get("org")||"";const environment=urlObj.searchParams.get("environment")||"production";if(!/^[0-9a-f-]{36}$/i.test(org)||!['production','sandbox'].includes(environment))return reply({error:"invalid_webhook_scope"},400);
  const raw=await req.text();const eventId=req.headers.get("svix-id")||"";if(!eventId)return reply({error:"missing_event_id"},400);
  const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  let runtime:RuntimeMaterial;try{runtime=await loadMaterial(service,org,environment);}catch{return reply({error:"provider_not_configured"},503);}const webhookSecret=runtime.secrets.webhook_secret;if(!webhookSecret)return reply({error:"webhook_secret_not_configured"},503);
  if(!await verifyResendWebhook(raw,req.headers,webhookSecret))return reply({error:"invalid_signature"},400);
  let event:Record<string,unknown>;try{event=JSON.parse(raw);}catch{return reply({error:"invalid_json"},400);}const type=String(event.type||"");const data=(event.data||{}) as Record<string,unknown>;const emailId=String(data.email_id||data.id||"");const rawHash=await sha256Hex(raw);
  const receipt={provider:"resend",provider_event_id:eventId,raw_body_hash:rawHash,signature_present:true,signature_verified:true,status:"verified",idempotency_key:eventId,correlation_id:crypto.randomUUID(),metadata:{event_type:type,organisation_id:org,environment,email_id:emailId}};
  const {error:receiptError}=await service.from("webhook_receipts").upsert(receipt,{onConflict:"provider,idempotency_key",ignoreDuplicates:true});if(receiptError)return reply({error:"receipt_persist_failed"},500);
  const map:Record<string,string>={"email.sent":"sent","email.delivered":"delivered","email.bounced":"failed","email.failed":"failed","email.complained":"failed"};
  const process=async()=>{try{const status=map[type];if(status&&emailId){const {error}=await service.rpc("apply_provider_delivery_event",{target_provider_key:"resend",target_provider_message_id:emailId,target_status:status,target_event_id:eventId,target_raw_hash:rawHash,target_metadata:{event_type:type,data}});if(error)throw new Error(error.message);}await service.from("webhook_receipts").update({status:"processed",error_code:null}).eq("provider","resend").eq("idempotency_key",eventId);}catch(error){await service.from("webhook_receipts").update({status:"failed",error_code:error instanceof Error?error.message.slice(0,180):"processing_failed"}).eq("provider","resend").eq("idempotency_key",eventId);}};
  const edge=(globalThis as unknown as {EdgeRuntime?:{waitUntil:(p:Promise<unknown>)=>void}}).EdgeRuntime;if(edge?.waitUntil)edge.waitUntil(process());else await process();return reply({ok:true,received:true});
});
