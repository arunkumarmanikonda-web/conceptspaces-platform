import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { supabasePublicConfig } from "@/lib/public-runtime-config";

export async function updateSupabaseSession(request:NextRequest){
  let response=NextResponse.next({request});
  const supabase=createServerClient(supabasePublicConfig.url,supabasePublicConfig.publishableKey,{
    cookies:{
      getAll(){return request.cookies.getAll();},
      setAll(cookiesToSet){
        cookiesToSet.forEach(({name,value})=>request.cookies.set(name,value));
        response=NextResponse.next({request});
        cookiesToSet.forEach(({name,value,options})=>response.cookies.set(name,value,options));
      }
    }
  });
  await supabase.auth.getUser();
  return response;
}
