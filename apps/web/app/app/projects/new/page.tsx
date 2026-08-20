export default function NewProject(){
  return <div className="wizard">
    <aside className="steps">{['Client Details','Site & Location','Plot Geometry','Regulation Inputs','Intended Use','Programme & Features','Interior Design DNA','Scope Selection'].map((step,index)=><div key={step} className={`step ${index===0?'active':''}`}>0{index+1} &nbsp; {step}</div>)}</aside>
    <section className="form">
      <div className="demo">Project Setup / Step 01 of 08</div>
      <h1>Client & Project Identity</h1>
      <p className="subtle">Accuracy begins with good data. This first record becomes the commercial, design and audit root of the project.</p>
      <div className="field-grid">
        <div className="field"><label>Client / Owner name</label><input placeholder="Full legal or individual name"/></div>
        <div className="field"><label>Email</label><input placeholder="name@example.com"/></div>
        <div className="field"><label>Organisation</label><input placeholder="Company / entity (optional)"/></div>
        <div className="field"><label>Phone</label><input placeholder="+91"/></div>
        <div className="field"><label>Project name</label><input placeholder="Working project title"/></div>
        <div className="field"><label>Intended use</label><select defaultValue=""><option value="" disabled>Select typology</option><option>Residential</option><option>Hotel</option><option>Hospital</option><option>Retail</option><option>Mixed Use</option><option>Commercial</option></select></div>
      </div>
      <div className="note"><b>Project Truth principle.</b> Client-entered FAR, dimensions, setbacks and height limits remain unverified facts until their source is established. Four side lengths alone will never be treated as a legally verified parcel geometry.</div>
      <div style={{display:'flex',justifyContent:'flex-end',gap:10,marginTop:30}}><button className="btn ghost">Save Draft</button><button className="btn">Continue</button></div>
    </section>
  </div>;
}
