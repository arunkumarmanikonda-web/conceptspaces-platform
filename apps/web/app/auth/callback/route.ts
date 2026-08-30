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
    // Implicit-flow links return the session in the URL fragment. Fragments are
    // not sent to Route Handlers, so hand the browser off to the client-side
    // completion page. The browser preserves the fragment across this redirect.
    const completionUrl=new URL("/auth/complete",url.origin);
    completionUrl.searchParams.set("next",next);
    return NextResponse.redirect(completionUrl);
  }
  return NextResponse.redirect(new URL(next,url.origin));
}
