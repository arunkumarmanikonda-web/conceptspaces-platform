import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { canonicalGeometryInput,computeParcel,type ParcelInput } from "../_shared/geometry.ts";
import { sha256Hex } from "../_shared/providers.ts";

const reply=(body:unknown,status=200)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
Deno.serve(async(req:Request)=>{
 if(req.method!=="POST")return reply({error:"method_not_allowed"},405);const auth=req.headers.get("authorization")||"";if(!auth.startsWith("Bearer "))return reply({error:"authentication_required"},401);
 let body:{project_id?:string;parcel?:ParcelInput;supersedes_geometry_id?:string|null};try{body=await req.json();}catch{return reply({error:"invalid_json"},400);}const projectId=String(body.project_id||"");if(!/^[0-9a-f-]{36}$/i.test(projectId))return reply({error:"valid_project_id_required"},400);if(body.supersedes_geometry_id&&!/^[0-9a-f-]{36}$/i.test(body.supersedes_geometry_id))return reply({error:"invalid_superseded_geometry_id"},400);
 const url=Deno.env.get("SUPABASE_URL")!,anon=Deno.env.get("SUPABASE_ANON_KEY")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;const user=createClient(url,anon,{global:{headers:{Authorization:auth}},auth:{persistSession:false}});const {data:{user:identity}}=await user.auth.getUser();if(!identity)return reply({error:"authentication_required"},401);
 const {data:authorized,error:authorityError}=await user.rpc("authorize_aec_runtime",{target_project_id:projectId});if(authorityError||authorized!==true)return reply({error:"project_manage_authority_required"},403);
 if(!body.parcel||!Array.isArray(body.parcel.vertices))return reply({error:"parcel_vertices_required"},400);if(body.parcel.vertices.length>10000)return reply({error:"too_many_vertices"},413);
 try{
  const canonical=canonicalGeometryInput(body.parcel);const inputHash=await sha256Hex(canonical);const result=computeParcel(body.parcel);const contentHash=await sha256Hex(JSON.stringify({input_hash:inputHash,result}));
  const service=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});const {data:geometryId,error:persistError}=await service.rpc("persist_geometry_evaluation",{target_project_id:projectId,target_actor_id:identity.id,target_input:body.parcel,target_result:result,target_input_hash:inputHash,target_content_hash:contentHash,target_supersedes_geometry_id:body.supersedes_geometry_id||null});if(persistError)throw new Error(persistError.message);
  return reply({ok:true,geometry_id:geometryId,input_hash:inputHash,content_hash:contentHash,result});
 }catch(error){return reply({error:error instanceof Error?error.message:"geometry_evaluation_failed"},400);}
});
