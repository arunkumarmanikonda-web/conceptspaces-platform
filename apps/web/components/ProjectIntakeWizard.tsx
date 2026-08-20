"use client";

import { useMemo, useState } from "react";

const steps=[
  "Client Details",
  "Site & Location",
  "Plot Geometry",
  "Regulation Inputs",
  "Intended Use",
  "Programme & Features",
  "Interior Design DNA",
  "Scope Selection",
  "Review"
];

const scopeModules=[
  ["FEAS","Feasibility + Development Economics"],
  ["ARCH","Architecture"],
  ["INT","Interior Design"],
  ["STR","Structural Engineering"],
  ["MEPF","MEPF + Fire + ELV"],
  ["BIM","BIM / CDE / Coordination"],
  ["BOQ","QTO / BOQ / Cost Intelligence"],
  ["PROC","Tender + Procurement"],
  ["PMC","PMC + Site Delivery"],
  ["TWIN","Handover + Digital Twin"]
];

type FormState={
  clientName:string; email:string; organisation:string; phone:string;
  projectName:string; address:string; latitude:string; longitude:string; facing:string; plotArea:string; plotAreaUnit:string;
  side1:string; side2:string; side3:string; side4:string; geometryEvidence:string; geometrySource:string;
  groundCoverage:string; far:string; heightLimit:string; frontSetback:string; rearSetback:string; authorityReference:string;
  typology:string; subTypology:string; keyCount:string; bedCount:string;
  programme:string; amenities:string; operations:string; priorities:string; exclusions:string;
  designLanguage:string; emotionalAttributes:string; materials:string; excludedMaterials:string; colourDirection:string; lightingDirection:string; budgetBand:string;
};

const initial:FormState={
  clientName:"",email:"",organisation:"",phone:"",projectName:"",address:"",latitude:"",longitude:"",facing:"",plotArea:"",plotAreaUnit:"sqm",
  side1:"",side2:"",side3:"",side4:"",geometryEvidence:"",geometrySource:"client_estimate",
  groundCoverage:"",far:"",heightLimit:"",frontSetback:"",rearSetback:"",authorityReference:"",
  typology:"",subTypology:"",keyCount:"",bedCount:"",programme:"",amenities:"",operations:"",priorities:"",exclusions:"",
  designLanguage:"",emotionalAttributes:"",materials:"",excludedMaterials:"",colourDirection:"",lightingDirection:"",budgetBand:""
};

export function ProjectIntakeWizard(){
  const [step,setStep]=useState(0);
  const [form,setForm]=useState<FormState>(initial);
  const [scope,setScope]=useState<string[]>(["FEAS","ARCH","BIM"]);
  const [submitted,setSubmitted]=useState(false);

  const set=(key:keyof FormState,value:string)=>setForm(prev=>({...prev,[key]:value}));
  const toggleScope=(code:string)=>setScope(prev=>prev.includes(code)?prev.filter(x=>x!==code):[...prev,code]);
  const fourSidesOnly=useMemo(()=>[form.side1,form.side2,form.side3,form.side4].every(Boolean) && !form.geometryEvidence, [form.side1,form.side2,form.side3,form.side4,form.geometryEvidence]);

  const next=()=>setStep(current=>Math.min(current+1,steps.length-1));
  const back=()=>setStep(current=>Math.max(current-1,0));

  return <div className="wizard">
    <aside className="steps">{steps.map((label,index)=><button type="button" key={label} onClick={()=>setStep(index)} className={`step ${index===step?"active":""}`} style={{width:"100%",textAlign:"left",background:"transparent",borderTop:0,borderRight:0,borderBottom:0,cursor:"pointer"}}>{String(index+1).padStart(2,"0")} &nbsp; {label}</button>)}</aside>
    <section className="form">
      <div className="demo">Project Setup / Step {String(step+1).padStart(2,"0")} of {String(steps.length).padStart(2,"0")}</div>
      <h1>{steps[step]}</h1>
      <p className="subtle">Guided intake builds the client, commercial and Project Truth foundation. Preview sessions are intentionally not persisted until the database is connected.</p>

      {step===0 && <div className="field-grid">
        <Field label="Client / Owner name" value={form.clientName} onChange={v=>set("clientName",v)} placeholder="Full legal or individual name"/>
        <Field label="Email" value={form.email} onChange={v=>set("email",v)} placeholder="name@example.com"/>
        <Field label="Organisation" value={form.organisation} onChange={v=>set("organisation",v)} placeholder="Company / entity (optional)"/>
        <Field label="Phone" value={form.phone} onChange={v=>set("phone",v)} placeholder="+91"/>
        <Field label="Project name" value={form.projectName} onChange={v=>set("projectName",v)} placeholder="Working project title"/>
      </div>}

      {step===1 && <div className="field-grid">
        <Field label="Site address" value={form.address} onChange={v=>set("address",v)} placeholder="Address / locality / city"/>
        <Field label="Facing" value={form.facing} onChange={v=>set("facing",v)} placeholder="North / East / road orientation"/>
        <Field label="Latitude" value={form.latitude} onChange={v=>set("latitude",v)} placeholder="e.g. 28.6139"/>
        <Field label="Longitude" value={form.longitude} onChange={v=>set("longitude",v)} placeholder="e.g. 77.2090"/>
        <Field label="Plot area" value={form.plotArea} onChange={v=>set("plotArea",v)} placeholder="Area"/>
        <Select label="Area unit" value={form.plotAreaUnit} onChange={v=>set("plotAreaUnit",v)} options={["sqm","sqft","sqyd","acre","hectare"]}/>
      </div>}

      {step===2 && <>
        <div className="field-grid">
          <Field label="Side 01" value={form.side1} onChange={v=>set("side1",v)} placeholder="Length"/>
          <Field label="Side 02" value={form.side2} onChange={v=>set("side2",v)} placeholder="Length"/>
          <Field label="Side 03" value={form.side3} onChange={v=>set("side3",v)} placeholder="Length"/>
          <Field label="Side 04" value={form.side4} onChange={v=>set("side4",v)} placeholder="Length"/>
          <Select label="Geometry source" value={form.geometrySource} onChange={v=>set("geometrySource",v)} options={["client_estimate","survey","dwg","dxf","pdf","cadastral","point_cloud","lidar"]}/>
          <Field label="Verified geometry / survey reference" value={form.geometryEvidence} onChange={v=>set("geometryEvidence",v)} placeholder="Survey/DWG/DXF/cadastral reference"/>
        </div>
        <div className="note"><b>Geometry assurance.</b> {fourSidesOnly?"Four side lengths are present, but they do not uniquely establish an arbitrary parcel. Add survey geometry, coordinates, bearings/angles, a diagonal, or a verified drawing before the parcel can become verified Project Truth.":"Concept Spaces records the source of geometry and will not silently promote client estimates into verified parcel coordinates."}</div>
      </>}

      {step===3 && <div className="field-grid">
        <Field label="Ground coverage %" value={form.groundCoverage} onChange={v=>set("groundCoverage",v)} placeholder="Client-declared or sourced"/>
        <Field label="FAR / FSI" value={form.far} onChange={v=>set("far",v)} placeholder="Permissible FAR / FSI"/>
        <Field label="Height limit (m)" value={form.heightLimit} onChange={v=>set("heightLimit",v)} placeholder="Height restriction"/>
        <Field label="Front setback (m)" value={form.frontSetback} onChange={v=>set("frontSetback",v)} placeholder="Front setback"/>
        <Field label="Rear setback (m)" value={form.rearSetback} onChange={v=>set("rearSetback",v)} placeholder="Rear setback"/>
        <Field label="Authority / source reference" value={form.authorityReference} onChange={v=>set("authorityReference",v)} placeholder="Authority letter / regulation / approval"/>
      </div>}

      {step===4 && <div className="field-grid">
        <Select label="Primary typology" value={form.typology} onChange={v=>set("typology",v)} options={["Residential","Hotel / Resort","Hospital / Clinic","Retail / Mall","Office","Mixed Use","School / University","Industrial / Warehouse","Convention / Cinema","Other"]}/>
        <Field label="Sub-typology / mix" value={form.subTypology} onChange={v=>set("subTypology",v)} placeholder="e.g. retail + hotel + office"/>
        <Field label="Keys / units" value={form.keyCount} onChange={v=>set("keyCount",v)} placeholder="Where applicable"/>
        <Field label="Beds" value={form.bedCount} onChange={v=>set("bedCount",v)} placeholder="Where applicable"/>
      </div>}

      {step===5 && <div className="field-grid">
        <TextArea label="Programme requirements" value={form.programme} onChange={v=>set("programme",v)} placeholder="Unit mix, anchors, vanilla stores, cinema, restaurants, convention spaces, clinical departments, etc."/>
        <TextArea label="Amenities" value={form.amenities} onChange={v=>set("amenities",v)} placeholder="Pool, gym, spa, kids areas, lounges, terraces, clubs, etc."/>
        <TextArea label="Operational requirements" value={form.operations} onChange={v=>set("operations",v)} placeholder="BOH, loading, service circulation, staff, storage, logistics..."/>
        <TextArea label="Top priorities" value={form.priorities} onChange={v=>set("priorities",v)} placeholder="Yield, capex, experience, sustainability, speed, prestige..."/>
        <TextArea label="Explicit exclusions" value={form.exclusions} onChange={v=>set("exclusions",v)} placeholder="What must not be included"/>
      </div>}

      {step===6 && <div className="field-grid">
        <Field label="Design language" value={form.designLanguage} onChange={v=>set("designLanguage",v)} placeholder="Colonial, Ibiza, royal, modern elite, quiet luxury..."/>
        <Field label="Emotional attributes" value={form.emotionalAttributes} onChange={v=>set("emotionalAttributes",v)} placeholder="Warm, ceremonial, calm, tactile, dramatic..."/>
        <Field label="Preferred materials" value={form.materials} onChange={v=>set("materials",v)} placeholder="Solid wood, natural stone, wallpaper..."/>
        <Field label="Excluded materials" value={form.excludedMaterials} onChange={v=>set("excludedMaterials",v)} placeholder="Materials to avoid"/>
        <Field label="Colour direction" value={form.colourDirection} onChange={v=>set("colourDirection",v)} placeholder="Palette / tonal direction"/>
        <Field label="Lighting direction" value={form.lightingDirection} onChange={v=>set("lightingDirection",v)} placeholder="Layered, warm, sculptural, daylight-led..."/>
        <Field label="Budget band" value={form.budgetBand} onChange={v=>set("budgetBand",v)} placeholder="Indicative interior capex band"/>
      </div>}

      {step===7 && <div className="grid-3">{scopeModules.map(([code,name])=><button type="button" key={code} onClick={()=>toggleScope(code)} className="card" style={{cursor:"pointer",textAlign:"left",outline:scope.includes(code)?"2px solid #3D6DF0":"none"}}><div className="eyebrow">{code}</div><h3>{name}</h3><p>{scope.includes(code)?"Included in current scope":"Excluded from current scope"}</p><span className="badge">{scope.includes(code)?"Included":"Add Module"}</span></button>)}</div>}

      {step===8 && <>
        <div className="panel-grid">
          <section className="panel"><h3>Client & Project</h3><table className="table"><tbody><tr><td>Client</td><td>{form.clientName||"Not provided"}</td></tr><tr><td>Project</td><td>{form.projectName||"Not provided"}</td></tr><tr><td>Typology</td><td>{form.typology||"Not selected"}</td></tr><tr><td>Site</td><td>{form.address||"Not provided"}</td></tr></tbody></table></section>
          <section className="panel"><h3>Selected Scope</h3><p className="subtle">{scope.length?scope.join(" · "):"No modules selected"}</p><div className="note"><b>Preview only.</b> Submission validates the journey but does not persist client data until the isolated production database is connected.</div></section>
        </div>
        {submitted?<div className="note" style={{marginTop:18}}><b>Preview intake complete.</b> The client journey is valid through review. Persistence, CRM conversion, proposal generation and professional assignment will activate when the configured data layer is available.</div>:null}
      </>}

      <div style={{display:"flex",justifyContent:"space-between",gap:10,marginTop:30}}>
        <button type="button" className="btn ghost" onClick={back} disabled={step===0}>Back</button>
        <div style={{display:"flex",gap:10}}><button type="button" className="btn ghost" onClick={()=>{setForm(initial);setScope(["FEAS","ARCH","BIM"]);setStep(0);setSubmitted(false);}}>Reset Preview</button>{step<steps.length-1?<button type="button" className="btn" onClick={next}>Continue</button>:<button type="button" className="btn" onClick={()=>setSubmitted(true)}>Submit Preview Intake</button>}</div>
      </div>
    </section>
  </div>;
}

function Field({label,value,onChange,placeholder}:{label:string;value:string;onChange:(value:string)=>void;placeholder?:string}){
  return <div className="field"><label>{label}</label><input value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder}/></div>;
}

function Select({label,value,onChange,options}:{label:string;value:string;onChange:(value:string)=>void;options:string[]}){
  return <div className="field"><label>{label}</label><select value={value} onChange={e=>onChange(e.target.value)}><option value="">Select</option>{options.map(option=><option key={option} value={option}>{option}</option>)}</select></div>;
}

function TextArea({label,value,onChange,placeholder}:{label:string;value:string;onChange:(value:string)=>void;placeholder?:string}){
  return <div className="field"><label>{label}</label><textarea value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder} rows={4}/></div>;
}
