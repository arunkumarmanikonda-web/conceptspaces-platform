import { NextResponse } from "next/server";
import { areaUnits, calculateCombinedArea, isValidGstin, normaliseGstin, normaliseParcels, type AreaUnit } from "@/lib/project-intake";
import { createServerSupabaseClient } from "@/lib/supabase-server";

const allowedModules=new Set(["FEAS","ARCH","INT","STR","MEPF","BIM","BOQ","PROC","PMC","TWIN"]);
const allowedArrangements=new Set(["single","adjacent_assembled","contiguous_assembly","non_contiguous"]);

function cleanForm(value:unknown):Record<string,string>{
  if(!value||typeof value!=="object") return {};
  return Object.fromEntries(Object.entries(value as Record<string,unknown>).filter((entry):entry is [string,string]=>typeof entry[1]==="string").map(([key,text])=>[key,text.trim().slice(0,10000)]));
}
function present(record:Record<string,string|null>){
  return Object.fromEntries(Object.entries(record).filter(([,value])=>value!==null&&value!==""));
}

export async function POST(request:Request){
  const supabase=await createServerSupabaseClient();
  const { data:{ user } }=await supabase.auth.getUser();
  if(!user) return NextResponse.json({error:"authentication_required"},{status:401});

  let body:{form?:unknown;parcels?:unknown;scope?:unknown};
  try{ body=await request.json(); }catch{ return NextResponse.json({error:"invalid_json"},{status:400}); }
  const form=cleanForm(body.form);
  const parcels=normaliseParcels(body.parcels);
  const scope=Array.isArray(body.scope)?[...new Set(body.scope.filter((value):value is string=>typeof value==="string").map(value=>value.toUpperCase()).filter(value=>allowedModules.has(value)))]:[];
  const arrangement=allowedArrangements.has(form.siteArrangement)?form.siteArrangement:"single";
  const combinedAreaUnit=(areaUnits.includes(form.combinedAreaUnit as AreaUnit)?form.combinedAreaUnit:"sqyd") as AreaUnit;
  const combinedArea=calculateCombinedArea(parcels,combinedAreaUnit);
  const gstRegistered=form.gstRegistered==="yes";
  const gstin=normaliseGstin(form.gstin);

  if(!form.projectName||!form.clientName||!form.typology) return NextResponse.json({error:"project_name_client_and_typology_required"},{status:422});
  if(!["yes","no"].includes(form.gstRegistered)) return NextResponse.json({error:"gst_registration_status_required"},{status:422});
  if(gstRegistered&&(!form.billingLegalName||!form.billingAddress||!form.billingState)) return NextResponse.json({error:"registered_client_billing_identity_required"},{status:422});
  if(gstRegistered&&!isValidGstin(gstin)) return NextResponse.json({error:"valid_gstin_required"},{status:422});
  if(!form.address) return NextResponse.json({error:"site_address_required"},{status:422});
  if(!parcels.length||parcels.some(parcel=>!parcel.label||!Number.isFinite(Number(parcel.area))||Number(parcel.area)<=0)||combinedArea===null) return NextResponse.json({error:"valid_parcel_areas_required"},{status:422});
  if(!form.projectBrief) return NextResponse.json({error:"project_brief_required"},{status:422});
  if(!scope.length) return NextResponse.json({error:"engagement_scope_required"},{status:422});

  const parcelGeometry=parcels.map(parcel=>({id:parcel.id,label:parcel.label,front:parcel.front||null,rear:parcel.rear||null,left:parcel.left||null,right:parcel.right||null,dimensionUnit:parcel.dimensionUnit,sharedBoundary:parcel.sharedBoundary||null}));
  const inputPayload={
    project:{name:form.projectName,typology:form.typology,subTypology:form.subTypology||null},
    client:{
      ...present({name:form.clientName,email:form.email||null,organisation:form.organisation||null,phone:form.phone||null}),
      billing:{
        legalName:form.billingLegalName||form.organisation||form.clientName,
        gstRegistered,
        gstin:gstRegistered?gstin:null,
        address:form.billingAddress||null,
        state:form.billingState||null,
        verificationStatus:gstRegistered?"client_declared":"not_applicable"
      }
    },
    site:{
      ...present({address:form.address,latitude:form.latitude||null,longitude:form.longitude||null}),
      arrangement,
      parcels,
      plotArea:combinedArea.toFixed(4).replace(/\.?0+$/,""),
      plotAreaUnit:combinedAreaUnit,
      combinedArea:{value:combinedArea.toFixed(4).replace(/\.?0+$/,""),unit:combinedAreaUnit}
    },
    geometry:{
      parcels:parcelGeometry,
      combinedBoundary:present({front:form.combinedFront||null,rear:form.combinedRear||null,left:form.combinedLeft||null,right:form.combinedRight||null,dimensionUnit:form.combinedDimensionUnit||"ft"}),
      ...present({adjacencyNotes:form.adjacencyNotes||null,source:form.geometrySource||"client_estimate",evidence:form.geometryEvidence||null})
    },
    regulation:present({groundCoverage:form.groundCoverage||null,far:form.far||null,heightLimit:form.heightLimit||null,frontSetback:form.frontSetback||null,rearSetback:form.rearSetback||null,authorityReference:form.authorityReference||null}),
    programme:present({
      requirements:form.projectBrief,
      developmentIntent:form.developmentIntent||null,
      occupancyModel:form.occupancyModel||null,
      targetFloors:form.targetFloors||null,
      keyCount:form.keyCount||null,
      bedCount:form.bedCount||null,
      floorRequirements:form.floorRequirements||null,
      spaceRequirements:form.spaceRequirements||null,
      parkingRequirement:form.parkingRequirement||null,
      amenities:form.amenities||null,
      operations:form.operations||null,
      specialRequirements:form.specialRequirements||null,
      priorities:form.priorities||null,
      exclusions:form.exclusions||null,
      timeline:form.timeline||null,
      budgetBand:form.budgetBand||null
    }),
    interiors:present({designLanguage:form.designLanguage||null,emotionalAttributes:form.emotionalAttributes||null,materials:form.materials||null,excludedMaterials:form.excludedMaterials||null,colourDirection:form.colourDirection||null,lightingDirection:form.lightingDirection||null})
  };

  const { data,error }=await supabase.rpc("submit_project_intake",{input_payload:inputPayload,scope_modules:scope});
  if(error){
    const reference=crypto.randomUUID().slice(0,8).toUpperCase();
    console.error("[projects.intake] persistence failed",{reference,code:error.code,details:error.details,hint:error.hint});
    return NextResponse.json({error:"intake_persistence_failed",detail:`The governed project could not be created. Your draft is saved in this browser. Reference: ${reference}`},{status:500});
  }
  return NextResponse.json({ok:true,...(data as Record<string,unknown>)});
}
