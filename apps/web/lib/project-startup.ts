import type { SupabaseClient } from "@supabase/supabase-js";

type GeometryParcel={
  vertices:Array<{x:number;y:number}>;
  unit:"m"|"ft";
  coordinate_system?:string;
  source_type:"manual";
  source_reference?:string;
};

export type ProjectStartupResult={
  baseline:Record<string,unknown>|null;
  geometry:Record<string,unknown>|null;
  compiler:Record<string,unknown>|null;
  issues:string[];
};

function message(value:unknown,fallback:string){
  if(value&&typeof value==="object"&&"message" in value&&typeof value.message==="string") return value.message;
  return fallback;
}

export async function initialiseProjectStartup(supabase:SupabaseClient,projectId:string):Promise<ProjectStartupResult>{
  const issues:string[]=[];
  const {data:baselineData,error:baselineError}=await supabase.rpc("initialise_project_intake_baseline",{target_project_id:projectId});
  if(baselineError) throw new Error(baselineError.message);
  const baseline=(baselineData&&typeof baselineData==="object"?baselineData:null) as Record<string,unknown>|null;
  const parcel=baseline?.geometry_parcel as GeometryParcel|undefined|null;
  let geometry:Record<string,unknown>|null=null;
  if(parcel){
    const {data,error}=await supabase.functions.invoke("geometry-evaluate",{body:{project_id:projectId,parcel}});
    if(error) issues.push(message(error,"Geometry initialization failed."));
    else if(data&&typeof data==="object"&&"error" in data) issues.push(String((data as {error:unknown}).error));
    else geometry=(data&&typeof data==="object"?data:null) as Record<string,unknown>|null;
  }

  const {data:compilerData,error:compilerError}=await supabase.functions.invoke("compiler-run",{body:{project_id:projectId,objective:"balanced",seed:"intake-baseline-v1"}});
  let compiler:Record<string,unknown>|null=null;
  if(compilerError) issues.push(message(compilerError,"Initial compiler run failed."));
  else if(compilerData&&typeof compilerData==="object"&&"error" in compilerData) issues.push(String((compilerData as {error:unknown}).error));
  else compiler=(compilerData&&typeof compilerData==="object"?compilerData:null) as Record<string,unknown>|null;

  return {baseline,geometry,compiler,issues};
}
