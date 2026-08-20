import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { createRazorpayOrder,type RuntimeMaterial } from "../_shared/providers.ts";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function material(service:ReturnType<typeof createClient>,org:string){for(const env of ["production","sandbox"]){const {data,error}=await service.rpc("provider_runtime_material",{target_organisation_id:org,target_provider_key:"razorpay",target_environment:env});if(!error&&data)return {data:data as RuntimeMaterial,environment:env};}throw new Error("razorpay_not_configured");}

Deno.serve(async(req:Request)=>{
  if(req.method!=="POST")return reply({error:"method_not_allowed"},405);const auth=req.headers.get("authorization")||"";if(!auth.startsWith("Bearer "))return reply({error:"authentication_required"},401);
  let body:{invoice_id?:string};try{body=await req.json();}catch{return reply({error:"invalid_json"},400);}const invoiceId=String(body.invoice_id||"");if(!/^[0-9a-f-]{36}$/i.test(invoiceId))return reply({error:"valid_invoice_id_required"},400);
  const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});const {data:{user:identity}}=await user.auth.getUser();if(!identity)return reply({error:"authentication_required"},401);
  const {data:prepared,error:prepareError}=await user.rpc("prepare_invoice_payment",{target_invoice_id:invoiceId});if(prepareError||!prepared)return reply({error:prepareError?.message||"payment_prepare_failed"},403);
  const prep=prepared as {invoice_id:string;organisation_id:string;project_id?:string|null;invoice_number:string;currency:string;amount_minor:number;receipt:string;idempotency_key:string};const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  try{
    const runtime=await material(service,prep.organisation_id);const order=await createRazorpayOrder(runtime.data,{amount_minor:Number(prep.amount_minor),currency:prep.currency,receipt:prep.receipt,invoice_id:prep.invoice_id,idempotency_key:prep.idempotency_key});
    const {data:transactionId,error:registerError}=await service.rpc("register_razorpay_order",{target_invoice_id:prep.invoice_id,target_order_id:order.orderId,target_amount_minor:prep.amount_minor,target_currency:prep.currency,target_idempotency_key:prep.idempotency_key,target_metadata:{environment:runtime.environment,created_by:identity.id}});if(registerError)throw new Error(registerError.message);
    return reply({ok:true,transaction_id:transactionId,order_id:order.orderId,key_id:order.keyId,amount:prep.amount_minor,currency:prep.currency,invoice_id:prep.invoice_id,environment:runtime.environment});
  }catch(error){return reply({error:error instanceof Error?error.message:"razorpay_order_failed"},502);}
});
