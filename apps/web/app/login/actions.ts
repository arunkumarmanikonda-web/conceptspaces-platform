"use server";

import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export async function signInWithPassword(formData:FormData){
  const email=String(formData.get("email")||"").trim();
  const password=String(formData.get("password")||"");
  if(!email||!password) redirect("/login?error=Email%20and%20password%20are%20required");
  const supabase=await createServerSupabaseClient();
  const { error }=await supabase.auth.signInWithPassword({email,password});
  if(error) redirect(`/login?error=${encodeURIComponent(error.message)}`);
  redirect("/app");
}

export async function sendMagicLink(formData:FormData){
  const email=String(formData.get("email")||"").trim();
  if(!email) redirect("/login?error=Email%20is%20required");
  const origin=(await headers()).get("origin") || "https://conceptspaces-platform.vercel.app";
  const supabase=await createServerSupabaseClient();
  const { error }=await supabase.auth.signInWithOtp({
    email,
    options:{ emailRedirectTo:`${origin}/auth/callback`, shouldCreateUser:true }
  });
  if(error) redirect(`/login?error=${encodeURIComponent(error.message)}`);
  redirect("/login?sent=1");
}

export async function signOut(){
  const supabase=await createServerSupabaseClient();
  await supabase.auth.signOut();
  redirect("/");
}
