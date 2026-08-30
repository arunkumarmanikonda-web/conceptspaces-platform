"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { areaUnits, calculateCombinedArea, createParcel, dimensionUnits, formatMeasurement, type AreaUnit, type PlotParcel } from "@/lib/project-intake";

const steps=["Client","Parcels","Geometry","Regulations","Use","Requirements","Interiors","Scope","Review"];
const modules=["FEAS","ARCH","INT","STR","MEPF","BIM","BOQ","PROC","PMC","TWIN"];
const draftKey="conceptspaces.project-intake.v2";
type FormState=Record<string,string>;
type SaveState={status:"idle"|"saving"|"saved"|"error";message?:string;projectCode?:string};
type Draft={form:FormState;parcels:PlotParcel[];scope:string[];step:number};

const initial:FormState={
  clientName:"",email:"",organisation:"",phone:"",projectName:"",address:"",latitude:"",longitude:"",siteArrangement:"single",combinedAreaUnit:"sqyd",
  combinedFront:"",combinedRear:"",combinedLeft:"",combinedRight:"",combinedDimensionUnit:"ft",adjacencyNotes:"",geometrySource:"client_estimate",geometryEvidence:"",
  groundCoverage:"",far:"",heightLimit:"",frontSetback:"",rearSetback:"",authorityReference:"",typology:"",subTypology:"",developmentIntent:"",occupancyModel:"",targetFloors:"",keyCount:"",bedCount:"",
  projectBrief:"",floorRequirements:"",spaceRequirements:"",parkingRequirement:"",amenities:"",operations:"",specialRequirements:"",priorities:"",exclusions:"",timeline:"",budgetBand:"",
  designLanguage:"",emotionalAttributes:"",materials:"",excludedMaterials:"",colourDirection:"",lightingDirection:""
};
const arrangementOptions=[
  {value:"single",label:"Single plot"},
  {value:"adjacent_assembled",label:"Adjacent plots used as one site"},
  {value:"contiguous_assembly",label:"Contiguous multi-plot assembly"},
  {value:"non_contiguous",label:"Multiple non-contiguous plots"}
];

export function ProjectIntakeWizardLive(){
  const [step,setStep]=useState(0);
  const [form,setForm]=useState<FormState>(initial);
  const [parcels,setParcels]=useState<PlotParcel[]>([createParcel(1)]);
  const [scope,setScope]=useState<string[]>(["FEAS","ARCH","BIM"]);
  const [state,setState]=useState<SaveState>({status:"idle"});
  const [draftReady,setDraftReady]=useState(false);

  useEffect(()=>{
    try{
      const stored=window.localStorage.getItem(draftKey);
      if(stored){
        const draft=JSON.parse(stored) as Partial<Draft>;
        if(draft.form&&typeof draft.form==="object") setForm(previous=>({...previous,...draft.form}));
        if(Array.isArray(draft.parcels)&&draft.parcels.length) setParcels(draft.parcels);
        if(Array.isArray(draft.scope)) setScope(draft.scope);
        if(Number.isInteger(draft.step)) setStep(Math.min(8,Math.max(0,Number(draft.step))));
      }
    }catch{ window.localStorage.removeItem(draftKey); }
    setDraftReady(true);
  },[]);
  useEffect(()=>{
    if(!draftReady||state.status==="saved") return;
    window.localStorage.setItem(draftKey,JSON.stringify({form,parcels,scope,step} satisfies Draft));
  },[draftReady,form,parcels,scope,state.status,step]);

  const combinedUnit=(areaUnits.includes(form.combinedAreaUnit as AreaUnit)?form.combinedAreaUnit:"sqyd") as AreaUnit;
  const combinedArea=useMemo(()=>calculateCombinedArea(parcels,combinedUnit),[combinedUnit,parcels]);
  const set=(key:string,value:string)=>setForm(previous=>({...previous,[key]:value}));
  const updateParcel=<K extends keyof PlotParcel>(id:string,key:K,value:PlotParcel[K])=>setParcels(previous=>previous.map(parcel=>parcel.id===id?{...parcel,[key]:value}:parcel));
  const addParcel=()=>setParcels(previous=>{
    const parcel=createParcel(previous.length+1);
    parcel.id=`parcel-${crypto.randomUUID()}`;
    return [...previous,parcel];
  });
  const removeParcel=(id:string)=>setParcels(previous=>previous.length===1?previous:previous.filter(parcel=>parcel.id!==id));
  const setArrangement=(value:string)=>{
    set("siteArrangement",value);
    if((value==="adjacent_assembled"||value==="contiguous_assembly")&&parcels.length===1) setParcels(previous=>[...previous,createParcel(2)]);
  };
  const toggle=(code:string)=>setScope(previous=>previous.includes(code)?previous.filter(item=>item!==code):[...previous,code]);
  const validationForStep=(target:number):string|null=>{
    if(target===0&&(!form.clientName.trim()||!form.projectName.trim())) return "Enter the client / owner name and project name.";
    if(target===1){
      if(!form.address.trim()) return "Enter the project site address.";
      if(!parcels.length||parcels.some(parcel=>!parcel.label.trim()||!Number.isFinite(Number(parcel.area))||Number(parcel.area)<=0)) return "Give every plot a label and a positive legal or declared area.";
    }
    if(target===4&&!form.typology.trim()) return "Enter the primary project typology.";
    if(target===5&&!form.projectBrief.trim()) return "Describe what you want designed or built in the project brief.";
    if(target===7&&!scope.length) return "Select at least one professional-service module.";
    return null;
  };
  const goNext=()=>{
    const message=validationForStep(step);
    if(message){ setState({status:"error",message}); return; }
    setState({status:"idle"}); setStep(current=>Math.min(8,current+1));
  };
  const submit=async()=>{
    for(const target of [0,1,4,5,7]){
      const message=validationForStep(target);
      if(message){ setStep(target); setState({status:"error",message}); return; }
    }
    setState({status:"saving"});
    const response=await fetch("/api/projects/intake",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({form,parcels,scope})});
    const data=await response.json().catch(()=>({}));
    if(!response.ok){ setState({status:"error",message:data.detail||data.error||"Unable to persist intake"}); return; }
    window.localStorage.removeItem(draftKey);
    setState({status:"saved",projectCode:String(data.project_code||"")});
  };

  return <div className="wizard">
    <aside className="steps" aria-label="Project intake steps">{steps.map((label,index)=><button type="button" key={label} onClick={()=>setStep(index)} className={`step ${index===step?"active":""}`} style={{width:"100%",textAlign:"left",background:"transparent",borderTop:0,borderRight:0,borderBottom:0,cursor:"pointer"}} aria-current={index===step?"step":undefined}>{String(index+1).padStart(2,"0")} &nbsp; {label}</button>)}</aside>
    <section className="form">
      <div className="demo">Live Project Intake / {String(step+1).padStart(2,"0")} of {String(steps.length).padStart(2,"0")}</div>
      <h1>{steps[step]}</h1>
      <p className="subtle">Capture each legal parcel, the combined development site and the client brief separately. Client-declared data remains unverified Project Truth until source evidence is accepted.</p>
      {state.status==="error"&&<div className="note intake-error" role="alert"><b>Action required.</b> {state.message}</div>}

      {step===0&&<Grid><Field label="Client / owner name" field="clientName" form={form} set={set} required/><Field label="Email" field="email" form={form} set={set} type="email"/><Field label="Organisation" field="organisation" form={form} set={set}/><Field label="Phone" field="phone" form={form} set={set} type="tel"/><Field label="Project name" field="projectName" form={form} set={set} required/></Grid>}

      {step===1&&<><Grid><Field label="Site address" field="address" form={form} set={set} required/><SelectField label="Site composition" field="siteArrangement" form={form} set={setArrangement} options={arrangementOptions}/><Field label="Latitude" field="latitude" form={form} set={set}/><Field label="Longitude" field="longitude" form={form} set={set}/></Grid>
        <div className="section-heading"><div><h2>Legal parcels</h2><p className="subtle">Add one record for every plot, title or survey parcel.</p></div><button className="btn ghost" type="button" onClick={addParcel}>Add plot</button></div>
        <div className="parcel-stack">{parcels.map((parcel,index)=><ParcelSiteCard key={parcel.id} parcel={parcel} index={index} canRemove={parcels.length>1} update={updateParcel} remove={removeParcel}/>)}</div>
        <div className="note combined-area"><span>Calculated parcel total</span><strong>{combinedArea===null?"Enter every plot area":`${formatMeasurement(combinedArea)} ${combinedUnit}`}</strong><SelectField label="Combined area unit" field="combinedAreaUnit" form={form} set={set} options={areaUnits.map(unit=>({value:unit,label:areaUnitLabel(unit)}))}/></div>
      </>}

      {step===2&&<><p className="subtle">Enter the dimensions for each legal plot first. Then enter the outside boundary of the assembled development site; do not count an internal shared edge as an outside boundary.</p>
        <div className="parcel-stack">{parcels.map((parcel,index)=><ParcelGeometryCard key={parcel.id} parcel={parcel} index={index} update={updateParcel}/>)}</div>
        <div className="panel geometry-panel"><h3>Combined assembled-site boundary</h3><Grid><Field label="Combined front / road side" field="combinedFront" form={form} set={set} type="number"/><Field label="Combined rear boundary" field="combinedRear" form={form} set={set} type="number"/><Field label="Combined left boundary" field="combinedLeft" form={form} set={set} type="number"/><Field label="Combined right boundary" field="combinedRight" form={form} set={set} type="number"/><SelectField label="Combined dimension unit" field="combinedDimensionUnit" form={form} set={set} options={dimensionUnits.map(unit=>({value:unit,label:unit}))}/><Field label="Geometry source" field="geometrySource" form={form} set={set} placeholder="Client estimate, survey, deed, cadastral map…"/></Grid><Area label="Adjacency / shared-boundary notes" field="adjacencyNotes" form={form} set={set} placeholder="Explain which plots touch, the shared edge and whether they will be legally or functionally combined."/><Area label="Survey / deed / DWG / DXF evidence reference" field="geometryEvidence" form={form} set={set} placeholder="Document name, survey date, drawing number or storage reference."/></div>
        <div className="note"><b>Geometry assurance.</b> Areas and four side lengths alone do not uniquely define an irregular parcel. They are saved as client-declared facts; survey coordinates or accepted evidence are needed before verified design release.</div>
      </>}

      {step===3&&<Grid><Field label="Ground coverage %" field="groundCoverage" form={form} set={set}/><Field label="FAR / FSI" field="far" form={form} set={set}/><Field label="Height limit" field="heightLimit" form={form} set={set}/><Field label="Front setback" field="frontSetback" form={form} set={set}/><Field label="Rear setback" field="rearSetback" form={form} set={set}/><Field label="Authority / source reference" field="authorityReference" form={form} set={set}/></Grid>}

      {step===4&&<Grid><Field label="Primary typology" field="typology" form={form} set={set} required placeholder="Residential, mixed use, hospitality…"/><Field label="Sub-typology / mix" field="subTypology" form={form} set={set}/><Area label="Development intent" field="developmentIntent" form={form} set={set} placeholder="New build, combined-plot residence, redevelopment, phased development…"/><Area label="Occupancy / operating model" field="occupancyModel" form={form} set={set}/><Field label="Target floors" field="targetFloors" form={form} set={set}/><Field label="Homes / keys / units" field="keyCount" form={form} set={set}/><Field label="Beds" field="bedCount" form={form} set={set}/></Grid>}

      {step===5&&<Grid><Area label="Project brief — what do you want designed or built?" field="projectBrief" form={form} set={set} required rows={7} placeholder="Describe the required outcome, users, spaces, quality level and how the two plots should work together."/><Area label="Floor-by-floor requirements" field="floorRequirements" form={form} set={set} rows={7} placeholder="Ground, first, second, terrace, basement…"/><Area label="Rooms / spaces / unit mix" field="spaceRequirements" form={form} set={set}/><Area label="Parking and access" field="parkingRequirement" form={form} set={set}/><Area label="Amenities" field="amenities" form={form} set={set}/><Area label="Operational requirements" field="operations" form={form} set={set}/><Area label="Special requirements" field="specialRequirements" form={form} set={set} placeholder="Accessibility, vastu, multigenerational use, rental separation, sustainability, security…"/><Area label="Top priorities" field="priorities" form={form} set={set}/><Area label="Explicit exclusions" field="exclusions" form={form} set={set}/><Field label="Target timeline" field="timeline" form={form} set={set}/><Field label="Budget band" field="budgetBand" form={form} set={set}/></Grid>}

      {step===6&&<Grid><Field label="Design language" field="designLanguage" form={form} set={set}/><Field label="Emotional attributes" field="emotionalAttributes" form={form} set={set}/><Field label="Preferred materials" field="materials" form={form} set={set}/><Field label="Excluded materials" field="excludedMaterials" form={form} set={set}/><Field label="Colour direction" field="colourDirection" form={form} set={set}/><Field label="Lighting direction" field="lightingDirection" form={form} set={set}/></Grid>}

      {step===7&&<div className="grid-3 scope-grid">{modules.map(code=><button type="button" className="card" key={code} onClick={()=>toggle(code)} aria-pressed={scope.includes(code)} style={{textAlign:"left",cursor:"pointer",outline:scope.includes(code)?"2px solid #3D6DF0":"none"}}><div className="eyebrow">{code}</div><h3>{scope.includes(code)?"Included":"Available"}</h3><p>{scope.includes(code)?"Part of this engagement scope":"Click to add to scope"}</p></button>)}</div>}

      {step===8&&<><div className="panel-grid review-grid"><div className="panel"><h3>Project and requirements</h3><ReviewRow label="Client" value={form.clientName||"Required"}/><ReviewRow label="Project" value={form.projectName||"Required"}/><ReviewRow label="Typology" value={[form.typology,form.subTypology].filter(Boolean).join(" — ")||"Required"}/><ReviewRow label="Project brief" value={form.projectBrief||"Required"}/><ReviewRow label="Priorities" value={form.priorities||"Not declared"}/><ReviewRow label="Scope" value={scope.join(" · ")||"None"}/></div><div className="panel"><h3>Site assembly</h3><ReviewRow label="Composition" value={arrangementLabel(form.siteArrangement)}/><ReviewRow label="Parcel count" value={String(parcels.length)}/>{parcels.map((parcel,index)=><ReviewRow key={parcel.id} label={parcel.label||`Plot ${index+1}`} value={`${parcel.area||"Area required"} ${parcel.areaUnit}; front ${parcel.front||"—"}, rear ${parcel.rear||"—"}, left ${parcel.left||"—"}, right ${parcel.right||"—"} ${parcel.dimensionUnit}`}/>)}<ReviewRow label="Calculated total" value={combinedArea===null?"Incomplete":`${formatMeasurement(combinedArea)} ${combinedUnit}`}/><ReviewRow label="Combined boundary" value={`front ${form.combinedFront||"—"}, rear ${form.combinedRear||"—"}, left ${form.combinedLeft||"—"}, right ${form.combinedRight||"—"} ${form.combinedDimensionUnit}`}/></div></div><div className="note"><b>Release posture.</b> Parcel areas, dimensions, FAR, setbacks and height restrictions remain unverified until their source evidence is accepted. Submission records declarations without promoting assumptions into verified facts.</div>{state.status==="saved"&&<div className="note"><b>Project created.</b> {state.projectCode||"Governed record saved"}. <Link href="/app/projects">Open portfolio</Link></div>}</>}

      <div className="wizard-actions"><button className="btn ghost" type="button" disabled={step===0||state.status==="saving"} onClick={()=>{setState({status:"idle"});setStep(current=>Math.max(0,current-1));}}>Back</button>{step<8?<button className="btn" type="button" onClick={goNext}>Continue</button>:<button className="btn" type="button" disabled={state.status==="saving"||state.status==="saved"} onClick={submit}>{state.status==="saving"?"Saving…":"Create governed project"}</button>}</div>
    </section>
  </div>;
}

function ParcelSiteCard({parcel,index,canRemove,update,remove}:{parcel:PlotParcel;index:number;canRemove:boolean;update:<K extends keyof PlotParcel>(id:string,key:K,value:PlotParcel[K])=>void;remove:(id:string)=>void}){
  return <div className="panel parcel-card"><div className="section-heading compact"><h3>Plot {index+1}</h3>{canRemove&&<button className="text-button" type="button" onClick={()=>remove(parcel.id)}>Remove</button>}</div><div className="field-grid"><ParcelField parcel={parcel} field="label" label="Plot label" update={update}/><ParcelField parcel={parcel} field="surveyNumber" label="Survey / title / plot number" update={update}/><ParcelField parcel={parcel} field="area" label="Plot area" update={update} type="number"/><ParcelSelect parcel={parcel} field="areaUnit" label="Area unit" update={update} options={areaUnits.map(unit=>({value:unit,label:areaUnitLabel(unit)}))}/><ParcelField parcel={parcel} field="facing" label="Road / facing" update={update} placeholder="North, east, corner plot…"/></div></div>;
}
function ParcelGeometryCard({parcel,index,update}:{parcel:PlotParcel;index:number;update:<K extends keyof PlotParcel>(id:string,key:K,value:PlotParcel[K])=>void}){
  return <div className="panel parcel-card"><h3>{parcel.label||`Plot ${index+1}`} — individual boundary</h3><div className="field-grid"><ParcelField parcel={parcel} field="front" label="Front / road-side length" update={update} type="number"/><ParcelField parcel={parcel} field="rear" label="Rear length" update={update} type="number"/><ParcelField parcel={parcel} field="left" label="Left-side length" update={update} type="number"/><ParcelField parcel={parcel} field="right" label="Right-side length" update={update} type="number"/><ParcelSelect parcel={parcel} field="dimensionUnit" label="Dimension unit" update={update} options={dimensionUnits.map(unit=>({value:unit,label:unit}))}/><ParcelField parcel={parcel} field="sharedBoundary" label="Shared edge / adjoining plot" update={update} placeholder="e.g. right edge adjoins Plot 2"/></div></div>;
}
function Grid({children}:{children:React.ReactNode}){return <div className="field-grid">{children}</div>}
function Field({label,field,form,set,type="text",placeholder,required}:{label:string;field:string;form:FormState;set:(field:string,value:string)=>void;type?:string;placeholder?:string;required?:boolean}){return <div className="field"><label htmlFor={`intake-${field}`}>{label}{required?" *":""}</label><input id={`intake-${field}`} type={type} min={type==="number"?"0":undefined} step={type==="number"?"any":undefined} value={form[field]||""} placeholder={placeholder} required={required} onChange={event=>set(field,event.target.value)}/></div>}
function Area({label,field,form,set,placeholder,required,rows=4}:{label:string;field:string;form:FormState;set:(field:string,value:string)=>void;placeholder?:string;required?:boolean;rows?:number}){return <div className="field"><label htmlFor={`intake-${field}`}>{label}{required?" *":""}</label><textarea id={`intake-${field}`} rows={rows} value={form[field]||""} placeholder={placeholder} required={required} onChange={event=>set(field,event.target.value)}/></div>}
function SelectField({label,field,form,set,options}:{label:string;field:string;form:FormState;set:(field:string,value:string)=>void;options:{value:string;label:string}[]}){return <div className="field"><label htmlFor={`intake-${field}`}>{label}</label><select id={`intake-${field}`} value={form[field]||options[0]?.value||""} onChange={event=>set(field,event.target.value)}>{options.map(option=><option key={option.value} value={option.value}>{option.label}</option>)}</select></div>}
function ParcelField<K extends keyof PlotParcel>({parcel,field,label,update,type="text",placeholder}:{parcel:PlotParcel;field:K;label:string;update:<T extends keyof PlotParcel>(id:string,key:T,value:PlotParcel[T])=>void;type?:string;placeholder?:string}){const inputId=`${parcel.id}-${String(field)}`;return <div className="field"><label htmlFor={inputId}>{label}</label><input id={inputId} type={type} min={type==="number"?"0":undefined} step={type==="number"?"any":undefined} value={String(parcel[field]||"")} placeholder={placeholder} onChange={event=>update(parcel.id,field,event.target.value as PlotParcel[K])}/></div>}
function ParcelSelect<K extends keyof PlotParcel>({parcel,field,label,update,options}:{parcel:PlotParcel;field:K;label:string;update:<T extends keyof PlotParcel>(id:string,key:T,value:PlotParcel[T])=>void;options:{value:string;label:string}[]}){const inputId=`${parcel.id}-${String(field)}`;return <div className="field"><label htmlFor={inputId}>{label}</label><select id={inputId} value={String(parcel[field])} onChange={event=>update(parcel.id,field,event.target.value as PlotParcel[K])}>{options.map(option=><option key={option.value} value={option.value}>{option.label}</option>)}</select></div>}
function ReviewRow({label,value}:{label:string;value:string}){return <div className="review-row"><span>{label}</span><strong>{value}</strong></div>}
function areaUnitLabel(unit:string){return ({sqyd:"Square yards",sqm:"Square metres",sqft:"Square feet",acre:"Acres",hectare:"Hectares"} as Record<string,string>)[unit]||unit}
function arrangementLabel(value:string){return arrangementOptions.find(option=>option.value===value)?.label||"Single plot"}
