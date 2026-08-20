import { PDFDocument,StandardFonts,rgb } from "pdf-lib";
import { Document,Packer,Paragraph,HeadingLevel,Table,TableRow,TableCell,TextRun } from "docx";
import { strToU8,zipSync } from "fflate";

export type ReportPayload={
  schema_version:string;
  report_type:string;
  as_of:string;
  project:{id:string;code:string;name:string;typology?:string|null;stage?:string|null;criticality?:string|null;status?:string|null;jurisdiction?:{country?:string|null;state?:string|null;city?:string|null}};
  project_truth:Array<Record<string,unknown>>;
  requirements:Array<Record<string,unknown>>;
  regulatory_findings:Array<Record<string,unknown>>;
  commercial:{contracts?:Array<Record<string,unknown>>;invoices?:Array<Record<string,unknown>>};
  cde:{documents?:Array<Record<string,unknown>>;models?:Array<Record<string,unknown>>};
  snapshot_hashes:Record<string,string>;
};

const brand={midnight:"0F1D33",signal:"3D6DF0",carbon:"202428",stone:"A7ACB3",white:"F6F7F8"};
const title=(payload:ReportPayload)=>`${payload.project.code} · ${payload.project.name}`;
const text=(v:unknown)=>v===null||v===undefined?"":typeof v==="string"?v:JSON.stringify(v);
const clip=(v:unknown,n=120)=>{const s=text(v);return s.length>n?`${s.slice(0,n-1)}…`:s;};
const xml=(v:unknown)=>text(v).replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&apos;"}[m]||m));
const zipXml=(files:Record<string,string>)=>Buffer.from(zipSync(Object.fromEntries(Object.entries(files).map(([name,value])=>[name,strToU8(value)])),{level:6}));

function rows(payload:ReportPayload){
  return [
    ["Project",payload.project.name],["Project Code",payload.project.code],["Typology",payload.project.typology||""],["Stage",payload.project.stage||""],["Criticality",payload.project.criticality||""],["Status",payload.project.status||""],
    ["Project Truth Records",String(payload.project_truth.length)],["Requirements",String(payload.requirements.length)],["Regulatory Findings",String(payload.regulatory_findings.length)],["CDE Documents",String(payload.cde.documents?.length||0)],["CDE Models",String(payload.cde.models?.length||0)]
  ];
}

export async function generatePdf(payload:ReportPayload){
  const pdf=await PDFDocument.create();const font=await pdf.embedFont(StandardFonts.Helvetica);const bold=await pdf.embedFont(StandardFonts.HelveticaBold);
  let page=pdf.addPage([595.28,841.89]);let y=790;
  const add=(value:string,size=10,isBold=false)=>{if(y<55){page=pdf.addPage([595.28,841.89]);y=790;}page.drawText(value.replace(/[^\x20-\x7E]/g," ").slice(0,105),{x:48,y,size,font:isBold?bold:font,color:rgb(0.06,0.11,0.2)});y-=size+8;};
  page.drawRectangle({x:0,y:812,width:595.28,height:30,color:rgb(0.06,0.11,0.2)});page.drawText("CONCEPT SPACES",{x:48,y:822,size:10,font:bold,color:rgb(1,1,1)});
  add("INTELLIGENCE, GIVEN FORM.",8);add(title(payload),22,true);add(`${payload.report_type.replaceAll("_"," ").toUpperCase()} · Snapshot ${new Date(payload.as_of).toISOString()}`,9);
  y-=8;for(const [k,v] of rows(payload)){add(`${k}: ${v}`,10,k==="Project");}
  y-=8;add("PROJECT TRUTH",13,true);for(const r of payload.project_truth.slice(0,80))add(`${clip(r.record_key,32)} · ${clip(r.value,64)} · ${clip(r.status,16)} · confidence ${clip(r.confidence,8)}`,8);
  y-=8;add("REQUIREMENTS",13,true);for(const r of payload.requirements.slice(0,80))add(`${clip(r.code,18)} · ${clip(r.statement,80)} · ${clip(r.status,14)}`,8);
  y-=8;add("REGULATORY FINDINGS",13,true);for(const r of payload.regulatory_findings.slice(0,80))add(`${clip(r.disposition,12)} · ${clip(r.status,14)} · ${clip(r.explanation,78)}`,8);
  y-=8;add(`Source snapshot hash: ${payload.snapshot_hashes.project_truth||""}`,7);add("Generated from versioned Concept Spaces project state. This report does not replace required professional or authority approvals.",7);
  return Buffer.from(await pdf.save());
}

export async function generateDocx(payload:ReportPayload){
  const summaryRows=rows(payload).map(([k,v])=>new TableRow({children:[new TableCell({children:[new Paragraph({children:[new TextRun({text:k,bold:true})]})]}),new TableCell({children:[new Paragraph(String(v))]})]}));
  const children=[
    new Paragraph({text:"CONCEPT SPACES",heading:HeadingLevel.TITLE}),new Paragraph("INTELLIGENCE, GIVEN FORM."),new Paragraph({text:title(payload),heading:HeadingLevel.HEADING_1}),new Paragraph(`${payload.report_type.replaceAll("_"," ").toUpperCase()} · ${new Date(payload.as_of).toISOString()}`),new Table({rows:summaryRows}),
    new Paragraph({text:"Project Truth",heading:HeadingLevel.HEADING_1}),...payload.project_truth.slice(0,100).map(r=>new Paragraph(`${clip(r.record_key,40)} | ${clip(r.value,110)} | ${clip(r.status,20)} | confidence ${clip(r.confidence,10)}`)),
    new Paragraph({text:"Requirements",heading:HeadingLevel.HEADING_1}),...payload.requirements.slice(0,100).map(r=>new Paragraph(`${clip(r.code,20)} | ${clip(r.statement,130)} | ${clip(r.status,20)}`)),
    new Paragraph({text:"Regulatory Findings",heading:HeadingLevel.HEADING_1}),...payload.regulatory_findings.slice(0,100).map(r=>new Paragraph(`${clip(r.disposition,18)} | ${clip(r.status,18)} | ${clip(r.explanation,130)}`)),
    new Paragraph(`Project Truth snapshot hash: ${payload.snapshot_hashes.project_truth||""}`),new Paragraph("Generated from versioned Concept Spaces project state. Professional and authority approvals remain separately governed.")
  ];
  return Packer.toBuffer(new Document({sections:[{children}]}));
}

function columnName(index:number){let n=index+1,s="";while(n){const r=(n-1)%26;s=String.fromCharCode(65+r)+s;n=Math.floor((n-1)/26);}return s;}
function worksheet(data:unknown[][]){
  const body=data.map((row,ri)=>`<row r="${ri+1}">${row.map((value,ci)=>`<c r="${columnName(ci)}${ri+1}" t="inlineStr"><is><t xml:space="preserve">${xml(value)}</t></is></c>`).join("")}</row>`).join("");
  return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>${body}</sheetData></worksheet>`;
}

export async function generateXlsx(payload:ReportPayload){
  const sheets:[string,unknown[][]][]=[
    ["Summary",[["CONCEPT SPACES","INTELLIGENCE, GIVEN FORM."],["Snapshot",payload.as_of],...rows(payload)]],
    ["Project Truth",[["Key","Kind","Value","Unit","Source","Confidence","Status","Criticality"],...payload.project_truth.map(r=>[r.record_key,r.kind,text(r.value),r.unit,r.source_reference,r.confidence,r.status,r.criticality])],
    ["Requirements",[["Code","Statement","Category","Status","Criticality","Acceptance Criteria"],...payload.requirements.map(r=>[r.code,r.statement,r.category,r.status,r.criticality,text(r.acceptance_criteria)])],
    ["REGULA",[["Disposition","Status","Observed","Required","Explanation","Checked At"],...payload.regulatory_findings.map(r=>[r.disposition,r.status,text(r.observed_value),text(r.required_value),r.explanation,r.checked_at])]
  ];
  const overrides=sheets.map((_,i)=>`<Override PartName="/xl/worksheets/sheet${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>`).join("");
  const workbookSheets=sheets.map(([name],i)=>`<sheet name="${xml(name)}" sheetId="${i+1}" r:id="rId${i+1}"/>`).join("");
  const workbookRels=sheets.map((_,i)=>`<Relationship Id="rId${i+1}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet${i+1}.xml"/>`).join("");
  const files:Record<string,string>={
    "[Content_Types].xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>${overrides}</Types>`,
    "_rels/.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>`,
    "xl/workbook.xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>${workbookSheets}</sheets></workbook>`,
    "xl/_rels/workbook.xml.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${workbookRels}</Relationships>`
  };
  sheets.forEach(([,data],i)=>{files[`xl/worksheets/sheet${i+1}.xml`]=worksheet(data);});
  return zipXml(files);
}

const EMU=914400;
function pptTextShape(id:number,name:string,lines:string[],x:number,y:number,w:number,h:number,size=18,color=brand.carbon,bold=false){
  const paras=lines.map(line=>`<a:p><a:r><a:rPr lang="en-US" sz="${size*100}"${bold?' b="1"':''}><a:solidFill><a:srgbClr val="${color}"/></a:solidFill><a:latin typeface="Arial"/></a:rPr><a:t>${xml(line)}</a:t></a:r><a:endParaRPr lang="en-US" sz="${size*100}"/></a:p>`).join("");
  return `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="${xml(name)}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${Math.round(x*EMU)}" y="${Math.round(y*EMU)}"/><a:ext cx="${Math.round(w*EMU)}" cy="${Math.round(h*EMU)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap="square"/><a:lstStyle/>${paras}</p:txBody></p:sp>`;
}
function pptSlide(shapes:string){return `<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>${shapes}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`;}

export async function generatePptx(payload:ReportPayload){
  const slide1=pptSlide([
    pptTextShape(2,"Brand",["CONCEPT SPACES"],.7,.6,5,.4,18,brand.midnight,true),
    pptTextShape(3,"Tagline",["INTELLIGENCE, GIVEN FORM."],.7,1.05,5,.3,8,brand.stone),
    pptTextShape(4,"Project",[payload.project.name],.7,2.0,11.5,.8,30,brand.midnight),
    pptTextShape(5,"Report",[`${payload.project.code} · ${payload.report_type.replaceAll("_"," ").toUpperCase()}`],.7,2.9,11,.4,11,brand.signal),
    pptTextShape(6,"Snapshot",[`Snapshot ${new Date(payload.as_of).toISOString()}`],.7,6.7,7,.25,8,brand.stone)
  ].join(""));
  const slide2=pptSlide(pptTextShape(2,"Snapshot",["PROJECT SNAPSHOT",...rows(payload).map(([a,b])=>`${a}: ${b}`)],.7,.6,11.8,5.8,16,brand.midnight));
  const truthLines=payload.project_truth.slice(0,14).map(r=>`${clip(r.record_key,30)}: ${clip(r.value,75)}`);if(!truthLines.length)truthLines.push("No Project Truth records in this snapshot.");
  const slide3=pptSlide(pptTextShape(2,"Truth",["PROJECT TRUTH",...truthLines],.7,.6,11.8,5.9,14,brand.carbon));
  const regulaLines=payload.regulatory_findings.slice(0,14).map(r=>`${clip(r.disposition,14)} · ${clip(r.status,14)} · ${clip(r.explanation,75)}`);if(!regulaLines.length)regulaLines.push("No regulatory findings in this snapshot.");
  const slide4=pptSlide(pptTextShape(2,"Regula",["REGULA FINDINGS",...regulaLines],.7,.6,11.8,5.9,14,brand.carbon));
  const slides=[slide1,slide2,slide3,slide4];
  const slideOverrides=slides.map((_,i)=>`<Override PartName="/ppt/slides/slide${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`).join("");
  const slideIds=slides.map((_,i)=>`<p:sldId id="${256+i}" r:id="rId${i+2}"/>`).join("");
  const presentationRels=[`<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>`,...slides.map((_,i)=>`<Relationship Id="rId${i+2}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide${i+1}.xml"/>`)].join("");
  const files:Record<string,string>={
    "[Content_Types].xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>${slideOverrides}</Types>`,
    "_rels/.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>`,
    "ppt/presentation.xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>${slideIds}</p:sldIdLst><p:sldSz cx="12192000" cy="6858000" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle/></p:presentation>`,
    "ppt/_rels/presentation.xml.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${presentationRels}</Relationships>`,
    "ppt/slideMasters/slideMaster1.xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld name="Concept Spaces"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/><p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>`,
    "ppt/slideMasters/_rels/slideMaster1.xml.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/></Relationships>`,
    "ppt/slideLayouts/slideLayout1.xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld name="Blank"><p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr></p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`,
    "ppt/slideLayouts/_rels/slideLayout1.xml.rels":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/></Relationships>`,
    "ppt/theme/theme1.xml":`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Concept Spaces"><a:themeElements><a:clrScheme name="Concept Spaces"><a:dk1><a:srgbClr val="202428"/></a:dk1><a:lt1><a:srgbClr val="F6F7F8"/></a:lt1><a:dk2><a:srgbClr val="0F1D33"/></a:dk2><a:lt2><a:srgbClr val="E9EDF2"/></a:lt2><a:accent1><a:srgbClr val="3D6DF0"/></a:accent1><a:accent2><a:srgbClr val="A7ACB3"/></a:accent2><a:accent3><a:srgbClr val="51627A"/></a:accent3><a:accent4><a:srgbClr val="7C8797"/></a:accent4><a:accent5><a:srgbClr val="D2D7DE"/></a:accent5><a:accent6><a:srgbClr val="6B7480"/></a:accent6><a:hlink><a:srgbClr val="3D6DF0"/></a:hlink><a:folHlink><a:srgbClr val="51627A"/></a:folHlink></a:clrScheme><a:fontScheme name="Concept Spaces"><a:majorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:majorFont><a:minorFont><a:latin typeface="Arial"/><a:ea typeface=""/><a:cs typeface=""/></a:minorFont></a:fontScheme><a:fmtScheme name="Concept Spaces"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="9525"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:prstDash val="solid"/></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>`
  };
  slides.forEach((slide,i)=>{files[`ppt/slides/slide${i+1}.xml`]=slide;files[`ppt/slides/_rels/slide${i+1}.xml.rels`]=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/></Relationships>`;});
  return zipXml(files);
}

export function generateHtml(payload:ReportPayload){
  const esc=(s:unknown)=>text(s).replace(/[&<>"']/g,m=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[m]||m));
  const table=(headers:string[],data:unknown[][])=>`<table><thead><tr>${headers.map(h=>`<th>${esc(h)}</th>`).join("")}</tr></thead><tbody>${data.map(r=>`<tr>${r.map(c=>`<td>${esc(c)}</td>`).join("")}</tr>`).join("")}</tbody></table>`;
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(title(payload))}</title><style>body{font-family:Arial,sans-serif;color:#0F1D33;margin:48px}header{border-top:10px solid #0F1D33;padding-top:24px}small{color:#6b7480}table{width:100%;border-collapse:collapse;margin:20px 0}th,td{padding:8px;border:1px solid #dde2e8;text-align:left;vertical-align:top;font-size:12px}th{background:#f6f7f8}h1,h2{font-weight:500}.tag{color:#3D6DF0;letter-spacing:.12em}</style></head><body><header><b>CONCEPT SPACES</b><div class="tag">INTELLIGENCE, GIVEN FORM.</div></header><h1>${esc(payload.project.name)}</h1><small>${esc(payload.project.code)} · ${esc(payload.report_type)} · ${esc(payload.as_of)}</small><h2>Snapshot</h2>${table(["Field","Value"],rows(payload))}<h2>Project Truth</h2>${table(["Key","Value","Confidence","Status"],payload.project_truth.map(r=>[r.record_key,text(r.value),r.confidence,r.status]))}<h2>Requirements</h2>${table(["Code","Statement","Status"],payload.requirements.map(r=>[r.code,r.statement,r.status]))}<h2>REGULA</h2>${table(["Disposition","Status","Explanation"],payload.regulatory_findings.map(r=>[r.disposition,r.status,r.explanation]))}<p><small>Project Truth snapshot hash: ${esc(payload.snapshot_hashes.project_truth||"")}<br>Generated from versioned Concept Spaces project state. Professional and authority approvals remain separately governed.</small></p></body></html>`;
}

export function generateCsv(payload:ReportPayload){
  const q=(v:unknown)=>`"${text(v).replaceAll('"','""')}"`;
  const lines=[["section","key","value","status","confidence"],...rows(payload).map(r=>["summary",r[0],r[1],"",""]),...payload.project_truth.map(r=>["project_truth",r.record_key,text(r.value),r.status,r.confidence]),...payload.requirements.map(r=>["requirement",r.code,r.statement,r.status,r.criticality]),...payload.regulatory_findings.map(r=>["regulatory",r.disposition,r.explanation,r.status,r.checked_by_type])];
  return lines.map(r=>r.map(q).join(",")).join("\r\n");
}

export async function generateProjectReport(format:string,payload:ReportPayload):Promise<{bytes:Buffer;mime:string;extension:string}>{
  switch(format){
    case "pdf":return {bytes:await generatePdf(payload),mime:"application/pdf",extension:"pdf"};
    case "docx":return {bytes:await generateDocx(payload),mime:"application/vnd.openxmlformats-officedocument.wordprocessingml.document",extension:"docx"};
    case "xlsx":return {bytes:await generateXlsx(payload),mime:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",extension:"xlsx"};
    case "pptx":return {bytes:await generatePptx(payload),mime:"application/vnd.openxmlformats-officedocument.presentationml.presentation",extension:"pptx"};
    case "html":return {bytes:Buffer.from(generateHtml(payload),"utf8"),mime:"text/html; charset=utf-8",extension:"html"};
    case "csv":return {bytes:Buffer.from(generateCsv(payload),"utf8"),mime:"text/csv; charset=utf-8",extension:"csv"};
    case "json":return {bytes:Buffer.from(JSON.stringify(payload,null,2),"utf8"),mime:"application/json",extension:"json"};
    default:throw new Error("unsupported_generation_format");
  }
}
