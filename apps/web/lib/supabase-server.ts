import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { supabaseRuntimeConfig } from "@/lib/supabase-config";

export async function createServerSupabaseClient(){
  const cookieStore = await cookies();
  const { url, publishableKey } = supabaseRuntimeConfig();
  return createServerClient(url,publishableKey,{
    cookies:{
      getAll(){ return cookieStore.getAll(); },
      setAll(cookiesToSet){
        try { cookiesToSet.forEach(({name,value,options})=>cookieStore.set(name,value,options)); }
        catch { /* Server Components cannot always mutate cookies; Route Handlers/Actions can. */ }
      }
    }
  });
}
