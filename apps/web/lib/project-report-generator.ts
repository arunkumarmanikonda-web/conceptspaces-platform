import { PDFDocument,StandardFonts,rgb } from "pdf-lib";
import { Document,Packer,Paragraph,HeadingLevel,Table,TableRow,TableCell,TextRun } from "docx";
import ExcelJS from "exceljs";
import PptxGenJS from "pptxgenjs";

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

const brand={midnight:"0F1D33",signal:"3D6DF0",carbon:"202428",stone:"A7ACB3"};
const title=(payload:ReportPayload)=>`${payload.project.code} · ${payload.project.name}`;
const text=(v:unknown)=>v===null||v===undefined?"":typeof v==="string"?v:JSON.stringify(v);
const clip=(v:unknown,n=120)=>{const s=text(v);return s.length>n?`${s.slice(0,n-1)}…`:s;};

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

export async function generateXlsx(payload:ReportPayload){
  const workbook=new ExcelJS.Workbook();workbook.creator="Concept Spaces";workbook.subject=payload.report_type;
  const summary=workbook.addWorksheet("Summary");summary.addRow(["CONCEPT SPACES","INTELLIGENCE, GIVEN FORM."]);summary.addRow(["Snapshot",payload.as_of]);rows(payload).forEach(r=>summary.addRow(r));summary.columns=[{width:28},{width:72}];
  const truth=workbook.addWorksheet("Project Truth");truth.addRow(["Key","Kind","Value","Unit","Source","Confidence","Status","Criticality"]);payload.project_truth.forEach(r=>truth.addRow([r.record_key,r.kind,text(r.value),r.unit,r.source_reference,r.confidence,r.status,r.criticality]));truth.columns=[{width:30},{width:16},{width:60},{width:12},{width:35},{width:12},{width:15},{width:12}];
  const req=workbook.addWorksheet("Requirements");req.addRow(["Code","Statement","Category","Status","Criticality","Acceptance Criteria"]);payload.requirements.forEach(r=>req.addRow([r.code,r.statement,r.category,r.status,r.criticality,text(r.acceptance_criteria)]));req.columns=[{width:18},{width:70},{width:24},{width:15},{width:12},{width:50}];
  const reg=workbook.addWorksheet("REGULA");reg.addRow(["Disposition","Status","Observed","Required","Explanation","Checked At"]);payload.regulatory_findings.forEach(r=>reg.addRow([r.disposition,r.status,text(r.observed_value),text(r.required_value),r.explanation,r.checked_at]));reg.columns=[{width:16},{width:15},{width:35},{width:35},{width:70},{width:24}];
  return Buffer.from(await workbook.xlsx.writeBuffer());
}

export async function generatePptx(payload:ReportPayload){
  const pptx=new PptxGenJS();pptx.layout="LAYOUT_WIDE";pptx.author="Concept Spaces";pptx.subject=payload.report_type;pptx.title=title(payload);pptx.company="Concept Spaces";
  const slide=pptx.addSlide();slide.background={color:"F6F7F8"};slide.addShape(pptx.ShapeType.rect,{x:0,y:0,w:13.333,h:.35,fill:{color:brand.midnight},line:{color:brand.midnight}});slide.addText("CONCEPT SPACES",{x:.7,y:.65,w:4.5,h:.35,fontFace:"Arial",fontSize:18,bold:true,color:brand.midnight,charSpacing:2});slide.addText("INTELLIGENCE, GIVEN FORM.",{x:.7,y:1.05,w:4.5,h:.25,fontFace:"Arial",fontSize:7,color:brand.stone,charSpacing:2});slide.addText(payload.project.name,{x:.7,y:2.05,w:11.8,h:.7,fontFace:"Arial",fontSize:30,bold:false,color:brand.midnight});slide.addText(`${payload.project.code} · ${payload.report_type.replaceAll("_"," ").toUpperCase()}`,{x:.7,y:2.85,w:11,h:.35,fontFace:"Arial",fontSize:11,color:brand.signal});slide.addText(`Snapshot ${new Date(payload.as_of).toISOString()}`,{x:.7,y:6.75,w:6,h:.25,fontSize:8,color:brand.stone});
  const overview=pptx.addSlide();overview.addText("Project Snapshot",{x:.7,y:.6,w:5,h:.5,fontSize:24,color:brand.midnight});overview.addTable(rows(payload).map(([a,b])=>[a,b]),{x:.7,y:1.35,w:11.8,h:4.8,border:{type:"solid",color:"DDE2E8",pt:1},fontFace:"Arial",fontSize:12,color:brand.carbon,fill:"FFFFFF",margin:.08});
  const truth=pptx.addSlide();truth.addText("Project Truth",{x:.7,y:.6,w:5,h:.5,fontSize:24,color:brand.midnight});truth.addText(payload.project_truth.slice(0,12).map(r=>({text:`${clip(r.record_key,28)}: ${clip(r.value,65)}`,options:{bullet:{indent:14},breakLine:true}})),{x:.8,y:1.3,w:11.6,h:5.3,fontSize:11,color:brand.carbon,breakLine:true});
  const reg=pptx.addSlide();reg.addText("REGULA Findings",{x:.7,y:.6,w:5,h:.5,fontSize:24,color:brand.midnight});reg.addText(payload.regulatory_findings.length?payload.regulatory_findings.slice(0,12).map(r=>({text:`${clip(r.disposition,12)} · ${clip(r.status,12)} · ${clip(r.explanation,70)}`,options:{bullet:{indent:14},breakLine:true}})):[{text:"No regulatory findings in this snapshot.",options:{}}],{x:.8,y:1.3,w:11.6,h:5.3,fontSize:11,color:brand.carbon});
  const output=await pptx.write({outputType:"nodebuffer"});return Buffer.isBuffer(output)?output:Buffer.from(output as ArrayBuffer);
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
