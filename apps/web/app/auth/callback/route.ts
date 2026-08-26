import { NextResponse } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { createServerSupabaseClient } from "@/lib/supabase-server";

function safeNextPath(value:string|null){
  return value?.startsWith("/")&&!value.startsWith("//")?value:"/app";
}

export async function GET(request:Request){
  const url=new URL(request.url);
  const code=url.searchParams.get("code");
  const tokenHash=url.searchParams.get("token_hash");
  const type=url.searchParams.get("type") as EmailOtpType|null;
  const next=safeNextPath(url.searchParams.get("next"));
  const supabase=await createServerSupabaseClient();
  if(code){
    const { error }=await supabase.auth.exchangeCodeForSession(code);
    if(error) return NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(error.message)}`,url.origin));
  }else if(tokenHash&&type){
    const {error}=await supabase.auth.verifyOtp({token_hash:tokenHash,type});
    if(error) return NextResponse.redirect(new URL(`/login?error=${encodeURIComponent(error.message)}`,url.origin));
  }else{
    return NextResponse.redirect(new URL("/login?error=The%20authentication%20link%20is%20invalid%20or%20expired",url.origin));
  }
  return NextResponse.redirect(new URL(next,url.origin));
}
