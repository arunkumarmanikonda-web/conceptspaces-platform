import { createBrowserClient } from "@supabase/ssr";
import { supabasePublicConfig } from "@/lib/public-runtime-config";

export function createClient(){
  return createBrowserClient(
    supabasePublicConfig.url,
    supabasePublicConfig.publishableKey
  );
}
