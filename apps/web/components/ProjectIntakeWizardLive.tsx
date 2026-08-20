"use client";

import { useMemo, useState } from "react";
import Link from "next/link";

const steps=["Client","Site","Geometry","Regulations","Use","Programme","Interiors","Scope","Review"];
const modules=["FEAS","ARCH","INT","STR","MEPF","BIM","BOQ","PROC","PMC","TWIN"];

type FormState=Record<string,string>;
const initial:FormState={clientName:"",email:"",organisation:"",phone:"",projectName:"",address:"",latitude:"",longitude:"",facing:"",plotArea:"",plotAreaUnit:"sqm",side1:"",side2:"",side3:"",side4:"",geometrySource:"client_estimate",geometryEvidence:"",groundCoverage:"",far:"",heightLimit:"",frontSetback:"",rearSetback:"",authorityReference:"",typology:"",subTypology:"",keyCount:"",bedCount:"",programme:"",amenities:"",operations:"",priorities:"",exclusions:"",designLanguage:"",emotionalAttributes:"",materials:"",excludedMaterials:"",colourDirection:"",lightingDirection:"",budgetBand:""};

export function ProjectIntakeWizardLive(){
  const [step,setStep]=useState(0); const [form,setForm]=useState<FormState>(initial); const [scope,setScope]=useState<string[]>(["FEAS","ARCH","BIM"]);
  const [state,setState]=useState<{status:"idle"|"saving"|"saved"|"error";message?:string;projectCode?:string}>({status:"idle"});
  const set=(key:string,value:string)=>setForm(prev=>({...prev,[key]:value}));
  const fourSidesOnly=useMemo(()=>[form.side1,form.side2,form.side3,form.side4].every(Boolean)&&!form.geometryEvidence,[form]);
  const submit=async()=>{
    setState({status:"saving"});
    const res=await fetch("/api/projects/intake",{method:"POST",headers:{"content-type":"application/json"},body:JSON.stringify({form,scope})});
    const data=await res.json().catch(()=>({}));
    if(!res.ok){setState({status:"error",message:data.detail||data.error||"Unable to persist intake"});return;}
    setState({status:"saved",projectCode:String(data.project_code||"")});
  };
  const toggle=(code:string)=>setScope(prev=>prev.includes(code)?prev.filter(x=>x!==code):[...prev,code]);

  return <div className="wizard">
    <aside className="steps">{steps.map((label,i)=><button type="button" key={label} onClick={()=>setStep(i)} className={`step ${i===step?"active":""}`} style={{width:"100%",textAlign:"left",background:"transparent",borderTop:0,borderRight:0,borderBottom:0,cursor:"pointer"}}>{String(i+1).padStart(2,"0")} &nbsp; {label}</button>)}</aside>
    <section className="form">
      <div className="demo">Live Project Intake / {String(step+1).padStart(2,"0")} of 09</div><h1>{steps[step]}</h1>
      <p className="subtle">This intake is connected to the production Supabase project. Submission creates a governed project and immutable intake record under your authorised organisation.</p>
      {step===0&&<Grid><Field l="Client / Owner name" k="clientName" f={form} s={set}/><Field l="Email" k="email" f={form} s={set}/><Field l="Organisation" k="organisation" f={form} s={set}/><Field l="Phone" k="phone" f={form} s={set}/><Field l="Project name" k="projectName" f={form} s={set}/></Grid>}
      {step===1&&<Grid><Field l="Site address" k="address" f={form} s={set}/><Field l="Latitude" k="latitude" f={form} s={set}/><Field l="Longitude" k="longitude" f={form} s={set}/><Field l="Facing" k="facing" f={form} s={set}/><Field l="Plot area" k="plotArea" f={form} s={set}/><Field l="Area unit" k="plotAreaUnit" f={form} s={set}/></Grid>}
      {step===2&&<><Grid><Field l="Side 01" k="side1" f={form} s={set}/><Field l="Side 02" k="side2" f={form} s={set}/><Field l="Side 03" k="side3" f={form} s={set}/><Field l="Side 04" k="side4" f={form} s={set}/><Field l="Geometry source" k="geometrySource" f={form} s={set}/><Field l="Survey / DWG / DXF / cadastral evidence" k="geometryEvidence" f={form} s={set}/></Grid><div className="note"><b>Geometry assurance.</b> {fourSidesOnly?"Four side lengths are not sufficient to uniquely define an arbitrary parcel. Verified geometry evidence is still required.":"Geometry source and evidence remain explicit Project Truth inputs."}</div></>}
      {step===3&&<Grid><Field l="Ground coverage %" k="groundCoverage" f={form} s={set}/><Field l="FAR / FSI" k="far" f={form} s={set}/><Field l="Height limit" k="heightLimit" f={form} s={set}/><Field l="Front setback" k="frontSetback" f={form} s={set}/><Field l="Rear setback" k="rearSetback" f={form} s={set}/><Field l="Authority / source reference" k="authorityReference" f={form} s={set}/></Grid>}
      {step===4&&<Grid><Field l="Primary typology" k="typology" f={form} s={set}/><Field l="Sub-typology / mix" k="subTypology" f={form} s={set}/><Field l="Keys / units" k="keyCount" f={form} s={set}/><Field l="Beds" k="bedCount" f={form} s={set}/></Grid>}
      {step===5&&<Grid><Area l="Programme requirements" k="programme" f={form} s={set}/><Area l="Amenities" k="amenities" f={form} s={set}/><Area l="Operational requirements" k="operations" f={form} s={set}/><Area l="Top priorities" k="priorities" f={form} s={set}/><Area l="Explicit exclusions" k="exclusions" f={form} s={set}/></Grid>}
      {step===6&&<Grid><Field l="Design language" k="designLanguage" f={form} s={set}/><Field l="Emotional attributes" k="emotionalAttributes" f={form} s={set}/><Field l="Preferred materials" k="materials" f={form} s={set}/><Field l="Excluded materials" k="excludedMaterials" f={form} s={set}/><Field l="Colour direction" k="colourDirection" f={form} s={set}/><Field l="Lighting direction" k="lightingDirection" f={form} s={set}/><Field l="Budget band" k="budgetBand" f={form} s={set}/></Grid>}
      {step===7&&<div className="grid-3">{modules.map(code=><button type="button" className="card" key={code} onClick={()=>toggle(code)} style={{textAlign:"left",cursor:"pointer",outline:scope.includes(code)?"2px solid #3D6DF0":"none"}}><div className="eyebrow">{code}</div><h3>{scope.includes(code)?"Included":"Available"}</h3><p>{scope.includes(code)?"Part of this engagement scope":"Click to add to scope"}</p></button>)}</div>}
      {step===8&&<><div className="panel-grid"><div className="panel"><h3>Project</h3><table className="table"><tbody><tr><td>Client</td><td>{form.clientName||"Required"}</td></tr><tr><td>Project</td><td>{form.projectName||"Required"}</td></tr><tr><td>Typology</td><td>{form.typology||"Required"}</td></tr><tr><td>Scope</td><td>{scope.join(" · ")||"None"}</td></tr></tbody></table></div><div className="panel"><h3>Release posture</h3><p className="subtle">Client-entered dimensions, FAR, setbacks and height restrictions remain unverified until their source evidence is established. Submission does not promote assumptions into verified facts.</p></div></div>{state.status==="error"&&<div className="note" style={{borderColor:'#D97B7B'}}><b>Persistence failed.</b> {state.message}</div>}{state.status==="saved"&&<div className="note"><b>Project created.</b> {state.projectCode||"Governed record saved"}. <Link href="/app/projects">Open portfolio</Link></div>}</>}
      <div style={{display:"flex",justifyContent:"space-between",gap:10,marginTop:30}}><button className="btn ghost" type="button" disabled={step===0} onClick={()=>setStep(Math.max(0,step-1))}>Back</button><div style={{display:"flex",gap:10}}>{step<8?<button className="btn" type="button" onClick={()=>setStep(Math.min(8,step+1))}>Continue</button>:<button className="btn" type="button" disabled={state.status==="saving"||state.status==="saved"} onClick={submit}>{state.status==="saving"?"Saving…":"Create governed project"}</button>}</div></div>
    </section>
  </div>;
}
function Grid({children}:{children:React.ReactNode}){return <div className="field-grid">{children}</div>}
function Field({l,k,f,s}:{l:string;k:string;f:FormState;s:(k:string,v:string)=>void}){return <div className="field"><label>{l}</label><input value={f[k]||""} onChange={e=>s(k,e.target.value)}/></div>}
function Area({l,k,f,s}:{l:string;k:string;f:FormState;s:(k:string,v:string)=>void}){return <div className="field"><label>{l}</label><textarea rows={4} value={f[k]||""} onChange={e=>s(k,e.target.value)}/></div>}
