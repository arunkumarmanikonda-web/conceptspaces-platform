"use server";

import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { applicationOrigin } from "@/lib/application-origin";

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
  const supabase=await createServerSupabaseClient();
  const { error }=await supabase.auth.signInWithOtp({
    email,
    options:{ emailRedirectTo:`${origin}/auth/callback?next=/app`, shouldCreateUser:false }
  });
  if(error){
    console.error("[auth.magic_link] delivery failed",{status:error.status,code:error.code});
    redirect("/login?error=Unable%20to%20send%20a%20secure%20link%20right%20now");
  }
  redirect("/login?sent=1");
}

export async function signOut(){
  const supabase=await createServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/");
}
