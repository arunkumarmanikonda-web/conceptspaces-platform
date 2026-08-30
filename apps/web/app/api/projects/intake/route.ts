import { NextResponse } from "next/server";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export async function POST(request:Request){
  const supabase=await createServerSupabaseClient();
  const { data:{ user } }=await supabase.auth.getUser();
  if(!user) return NextResponse.json({error:"authentication_required"},{status:401});

  let body:{form?:Record<string,string>;scope?:string[]};
  try { body=await request.json(); } catch { return NextResponse.json({error:"invalid_json"},{status:400}); }
  const form=body.form||{};
  const scope=Array.isArray(body.scope)?body.scope.filter(v=>typeof v==="string"):[];
  if(!form.projectName?.trim() || !form.clientName?.trim() || !form.typology?.trim()){
    return NextResponse.json({error:"project_name_client_and_typology_required"},{status:422});
  }

  const inputPayload={
    project:{name:form.projectName.trim(),typology:form.typology.trim(),subTypology:form.subTypology||null},
    client:{name:form.clientName.trim(),email:form.email||null,organisation:form.organisation||null,phone:form.phone||null},
    site:{address:form.address||null,latitude:form.latitude||null,longitude:form.longitude||null,facing:form.facing||null,plotArea:form.plotArea||null,plotAreaUnit:form.plotAreaUnit||"sqm"},
    geometry:{side1:form.side1||null,side2:form.side2||null,side3:form.side3||null,side4:form.side4||null,source:form.geometrySource||"client_estimate",evidence:form.geometryEvidence||null},
    regulation:{groundCoverage:form.groundCoverage||null,far:form.far||null,heightLimit:form.heightLimit||null,frontSetback:form.frontSetback||null,rearSetback:form.rearSetback||null,authorityReference:form.authorityReference||null},
    programme:{keyCount:form.keyCount||null,bedCount:form.bedCount||null,requirements:form.programme||null,amenities:form.amenities||null,operations:form.operations||null,priorities:form.priorities||null,exclusions:form.exclusions||null},
    interiors:{designLanguage:form.designLanguage||null,emotionalAttributes:form.emotionalAttributes||null,materials:form.materials||null,excludedMaterials:form.excludedMaterials||null,colourDirection:form.colourDirection||null,lightingDirection:form.lightingDirection||null,budgetBand:form.budgetBand||null}
  };

  const { data,error }=await supabase.rpc("submit_project_intake",{input_payload:inputPayload,scope_modules:scope});
  if(error){
    console.error("[projects.intake] persistence failed",{code:error.code,details:error.details,hint:error.hint});
    return NextResponse.json({error:"intake_persistence_failed",detail:"The governed project could not be created. Your intake remains on this page; please retry."},{status:500});
  }
  return NextResponse.json({ok:true,...(data as Record<string,unknown>)});
}
