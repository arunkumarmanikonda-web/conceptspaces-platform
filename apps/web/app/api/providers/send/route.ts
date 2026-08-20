import { NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export const runtime="nodejs";export const dynamic="force-dynamic";
const purposes=new Set(["project_notification","approval_request","invoice_notice","contract_notice","security_notice","otp","system_notice"]);

export async function POST(request:Request){
  const supabase=await createServerSupabaseClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:"authentication_required"},{status:401});
  let body:{organisation_id?:string;project_id?:string|null;channel?:string;recipient?:string;purpose?:string;template_key?:string;subject?:string;payload?:Record<string,unknown>;consent_basis?:string;idempotency_key?:string};try{body=await request.json();}catch{return NextResponse.json({error:"invalid_json"},{status:400});}
  const org=String(body.organisation_id||"");const project=body.project_id?String(body.project_id):null;const channel=String(body.channel||"").toLowerCase();const purpose=String(body.purpose||"").toLowerCase();const recipient=String(body.recipient||"").trim();if(!/^[0-9a-f-]{36}$/i.test(org))return NextResponse.json({error:"valid_organisation_id_required"},{status:400});if(project&&!/^[0-9a-f-]{36}$/i.test(project))return NextResponse.json({error:"invalid_project_id"},{status:400});if(!["email","whatsapp","sms"].includes(channel))return NextResponse.json({error:"unsupported_channel"},{status:400});if(!purposes.has(purpose))return NextResponse.json({error:"unsupported_transactional_purpose"},{status:400});if(!recipient||recipient.length>320)return NextResponse.json({error:"valid_recipient_required"},{status:400});
  const payload=body.payload&&typeof body.payload==="object"&&!Array.isArray(body.payload)?body.payload:{};const serialized=JSON.stringify(payload);if(serialized.length>50000)return NextResponse.json({error:"payload_too_large"},{status:413});const idempotency=String(body.idempotency_key||`${purpose}:${project||org}:${crypto.randomUUID()}`).slice(0,180);
  const {data:messageId,error:queueError}=await supabase.rpc("queue_provider_message",{target_organisation_id:org,target_project_id:project,target_channel:channel,target_recipient:recipient,target_purpose:purpose,target_template_key:String(body.template_key||"").slice(0,180),target_subject:String(body.subject||"").slice(0,300),target_payload:payload,target_consent_basis:String(body.consent_basis||"transactional_contractual").slice(0,180),target_idempotency_key:idempotency});
  if(queueError||!messageId)return NextResponse.json({error:queueError?.message||"message_queue_failed"},{status:403});
  const {data:dispatch,error:dispatchError}=await supabase.functions.invoke("provider-dispatch",{body:{message_id:messageId}});
  if(dispatchError)return NextResponse.json({ok:true,queued:true,message_id:messageId,dispatch_error:dispatchError.message},{status:202});return NextResponse.json({ok:true,queued:true,message_id:messageId,dispatch});
}
