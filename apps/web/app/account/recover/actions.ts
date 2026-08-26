"use server";

import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { applicationOrigin } from "@/lib/application-origin";

export async function sendPasswordReset(formData:FormData){
  const email=String(formData.get("email")||"").trim();
  if(!email) redirect("/account/recover?error=Email%20is%20required");
  const origin=await applicationOrigin();
  const supabase=await createServerSupabaseClient();
  const {error}=await supabase.auth.resetPasswordForEmail(email,{
    redirectTo:`${origin}/auth/callback?next=/account/update-password`
  });
  if(error) console.error("[auth.password_reset] delivery failed",{status:error.status,code:error.code});
  redirect("/account/recover?sent=1");
}
