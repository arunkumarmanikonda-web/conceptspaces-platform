import { createHash } from "node:crypto";
import { NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase-server";
import { generateProjectReport,type ReportPayload } from "@/lib/project-report-generator";

export const runtime="nodejs";
export const dynamic="force-dynamic";

function safe(value:string){return value.replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/-+/g,"-").replace(/^-|-$/g,"").slice(0,100)||"report";}

export async function POST(request:Request){
  const supabase=await createServerSupabaseClient();
  const {data:{user}}=await supabase.auth.getUser();
  if(!user)return NextResponse.json({error:"authentication_required"},{status:401});

  let body:{project_id?:string;report_type?:string;output_format?:string};
  try{body=await request.json();}catch{return NextResponse.json({error:"invalid_json"},{status:400});}
  const projectId=String(body.project_id||"");const reportType=String(body.report_type||"project_report");const format=String(body.output_format||"pdf").toLowerCase();
  if(!/^[0-9a-f-]{36}$/i.test(projectId))return NextResponse.json({error:"valid_project_id_required"},{status:400});

  const {data:prepared,error:prepareError}=await supabase.rpc("prepare_project_generation",{target_project_id:projectId,target_report_type:reportType,target_output_format:format});
  if(prepareError||!prepared)return NextResponse.json({error:prepareError?.message||"generation_prepare_failed"},{status:403});
  const prep=prepared as {job_id:string;input_hash:string;payload:ReportPayload;output_format:string;report_type:string};
  let objectKey="";
  try{
    const generated=await generateProjectReport(format,prep.payload);
    const outputHash=createHash("sha256").update(generated.bytes).digest("hex");
    const projectCode=safe(prep.payload.project.code);const name=`Concept-Spaces-${projectCode}-${safe(reportType)}-${prep.job_id.slice(0,8)}.${generated.extension}`;
    objectKey=`${projectId}/generated/${prep.job_id}/${name}`;
    const {error:uploadError}=await supabase.storage.from("project-cde").upload(objectKey,generated.bytes,{contentType:generated.mime,upsert:false,cacheControl:"3600"});
    if(uploadError)throw new Error(`artifact_upload_failed:${uploadError.message}`);
    const {data:artifactId,error:completeError}=await supabase.rpc("complete_project_generation",{target_job_id:prep.job_id,target_object_ref:objectKey,target_output_hash:outputHash,target_title:`${prep.payload.project.name} · ${reportType.replaceAll("_"," ")}`});
    if(completeError)throw new Error(`generation_finalize_failed:${completeError.message}`);
    return NextResponse.json({ok:true,job_id:prep.job_id,artifact_id:artifactId,object_ref:objectKey,input_hash:prep.input_hash,output_hash:outputHash,format});
  }catch(error){
    if(objectKey)await supabase.storage.from("project-cde").remove([objectKey]);
    await supabase.rpc("fail_project_generation",{target_job_id:prep.job_id,target_error_code:error instanceof Error?error.message.slice(0,180):"generation_failed"});
    return NextResponse.json({error:error instanceof Error?error.message:"generation_failed",job_id:prep.job_id},{status:500});
  }
}
