import { NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export const runtime="nodejs";
export const dynamic="force-dynamic";

const allowed:Record<string,string[]>={
  resend:["api_key","webhook_secret"],
  razorpay:["key_id","key_secret","webhook_secret"],
  aisensy:["api_key"],
  fast2sms:["api_key"],
  godaddy:["api_key","api_secret"]
};
const required:Record<string,string[]>={
  resend:["api_key"],razorpay:["key_id","key_secret","webhook_secret"],aisensy:["api_key"],fast2sms:["api_key"],godaddy:["api_key","api_secret"]
};

function sanitizeObject(value:unknown,maxEntries=30){
  if(!value||typeof value!=="object"||Array.isArray(value))return {};
  return Object.fromEntries(Object.entries(value as Record<string,unknown>).slice(0,maxEntries).filter(([k,v])=>k.length<=80&&(typeof v==="string"||typeof v==="number"||typeof v==="boolean"||v===null)).map(([k,v])=>[k,typeof v==="string"?v.slice(0,1000):v]));
}

export async function POST(request:Request){
  const supabase=await createServerSupabaseClient();const {data:{user}}=await supabase.auth.getUser();if(!user)return NextResponse.json({error:"authentication_required"},{status:401});
  let body:{organisation_id?:string;provider_key?:string;environment?:string;config?:unknown;secrets?:unknown;enabled?:boolean};try{body=await request.json();}catch{return NextResponse.json({error:"invalid_json"},{status:400});}
  const org=String(body.organisation_id||"");const provider=String(body.provider_key||"").toLowerCase();const environment=String(body.environment||"production").toLowerCase();if(!/^[0-9a-f-]{36}$/i.test(org))return NextResponse.json({error:"valid_organisation_id_required"},{status:400});if(!allowed[provider])return NextResponse.json({error:"unsupported_provider"},{status:400});if(!["sandbox","production"].includes(environment))return NextResponse.json({error:"unsupported_environment"},{status:400});
  const config=sanitizeObject(body.config);const supplied=sanitizeObject(body.secrets,10);const secrets:Record<string,string>={};for(const field of allowed[provider]){const value=supplied[field];if(typeof value==="string"&&value.trim()&&value!=="••••••••"){if(value.length>5000)return NextResponse.json({error:`${field}_too_long`},{status:400});secrets[field]=value.trim();}}
  if(body.enabled===true){const {data:instances}=await supabase.rpc("list_provider_instances",{target_organisation_id:org});const current=((instances||[]) as Array<{provider_key:string;environment:string;configured_secret_fields:string[]}>).find(i=>i.provider_key===provider&&i.environment===environment);const configured=new Set([...(current?.configured_secret_fields||[]),...Object.keys(secrets)]);const missing=required[provider].filter(k=>!configured.has(k));if(missing.length)return NextResponse.json({error:"required_credentials_missing",fields:missing},{status:400});}
  const {data,error}=await supabase.rpc("configure_provider_instance",{target_organisation_id:org,target_provider_key:provider,target_environment:environment,target_config:config,secret_updates:secrets,target_enabled:body.enabled===true});
  if(error)return NextResponse.json({error:error.message},{status:403});return NextResponse.json({ok:true,instance_id:data,provider_key:provider,environment,configured_secret_fields:Object.keys(secrets)});
}
