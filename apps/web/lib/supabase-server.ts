import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { supabasePublicConfig } from "@/lib/public-runtime-config";

export async function createServerSupabaseClient(){
  const cookieStore = await cookies();
  return createServerClient(supabasePublicConfig.url,supabasePublicConfig.publishableKey,{
    cookies:{
      getAll(){ return cookieStore.getAll(); },
      setAll(cookiesToSet){
        try { cookiesToSet.forEach(({name,value,options})=>cookieStore.set(name,value,options)); }
        catch { /* Server Components cannot always mutate cookies; Route Handlers/Actions can. */ }
      }
    }
  });
}
