"use server";

import { redirect } from "next/navigation";
import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { applicationOrigin } from "@/lib/application-origin";
import { supabasePublicConfig } from "@/lib/public-runtime-config";

function createDeviceIndependentMagicLinkClient(){
  return createSupabaseClient(
    supabasePublicConfig.url,
    supabasePublicConfig.publishableKey,
    {
      auth:{
        flowType:"implicit",
        autoRefreshToken:false,
        persistSession:false,
        detectSessionInUrl:false
      }
    }
  );
}

export async function signInWithPassword(formData:FormData){
  const email=String(formData.get("email")||"").trim();
  const password=String(formData.get("password")||"");
  if(!email||!password) redirect("/login?error=Email%20and%20password%20are%20required");
  const supabase=await createServerSupabaseClient();
  const { error }=await supabase.auth.signInWithPassword({email,password});
  if(error) redirect("/login?error=The%20email%20or%20password%20is%20incorrect");
  redirect("/app");
}

export async function sendMagicLink(formData:FormData){
  const email=String(formData.get("email")||"").trim();
  if(!email) redirect("/login?error=Email%20is%20required");
  const origin=await applicationOrigin();
  // A PKCE link depends on the browser that requested it retaining a code
  // verifier. Email is commonly opened on another browser or device, so this
  // one-time link intentionally uses the implicit flow. The callback forwards
  // its URL fragment to /auth/complete, which immediately removes the tokens
  // from the address bar before persisting the session.
  const supabase=createDeviceIndependentMagicLinkClient();
  const { error }=await supabase.auth.signInWithOtp({
    email,
    options:{ emailRedirectTo:`${origin}/auth/callback?next=/app`, shouldCreateUser:false }
  });
  if(error){
    console.error("[auth.magic_link] delivery failed",{status:error.status,code:error.code});
    if(error.status===429||error.code==="over_email_send_rate_limit"){
      redirect("/login?sent=1&cooldown=1");
    }
    redirect("/login?error=Unable%20to%20send%20a%20secure%20link%20right%20now");
  }
  redirect("/login?sent=1");
}

export async function signOut(){
  const supabase=await createServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/");
}
