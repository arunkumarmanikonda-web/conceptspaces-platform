"use server";

import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export async function updatePassword(formData:FormData){
  const password=String(formData.get("password")||"");
  const confirmation=String(formData.get("password_confirmation")||"");
  if(password.length<12) redirect("/account/update-password?error=Use%20at%20least%2012%20characters");
  if(password!==confirmation) redirect("/account/update-password?error=The%20passwords%20do%20not%20match");
  const supabase=await createServerSupabaseClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user) redirect("/login?error=Your%20recovery%20session%20has%20expired");
  const {error}=await supabase.auth.updateUser({password});
  if(error) redirect(`/account/update-password?error=${encodeURIComponent(error.message)}`);
  redirect("/app");
}
