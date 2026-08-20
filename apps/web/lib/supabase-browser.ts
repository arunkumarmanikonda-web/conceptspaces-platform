"use client";

import { createBrowserClient } from "@supabase/ssr";
import { supabasePublicConfig } from "@/lib/public-runtime-config";

let client: ReturnType<typeof createBrowserClient> | null = null;

export function getBrowserSupabaseClient(){
  if(!client){
    client=createBrowserClient(supabasePublicConfig.url,supabasePublicConfig.publishableKey);
  }
  return client;
}
