import { NextResponse } from "next/server";
import { initialiseProjectStartup } from "@/lib/project-startup";
import { createServerSupabaseClient } from "@/lib/supabase-server";

const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function POST(_request:Request,{params}:{params:Promise<{id:string}>}){
  const {id}=await params;
  if(!uuid.test(id)) return NextResponse.json({error:"valid_project_id_required"},{status:400});
  const supabase=await createServerSupabaseClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user) return NextResponse.json({error:"authentication_required"},{status:401});
  try{
    const startup=await initialiseProjectStartup(supabase,id);
    return NextResponse.json({ok:true,...startup},{headers:{"cache-control":"no-store"}});
  }catch(error){
    const reference=crypto.randomUUID().slice(0,8).toUpperCase();
    console.error("[projects.bootstrap] initialization failed",{reference,projectId:id,error:error instanceof Error?error.message:String(error)});
    return NextResponse.json({error:"project_startup_failed",detail:`The project baseline could not be initialized. Reference: ${reference}`},{status:500});
  }
}
