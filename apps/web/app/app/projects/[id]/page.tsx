import Link from "next/link";
import { notFound } from "next/navigation";
import ProjectStartupClient from "@/components/ProjectStartupClient";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string;lifecycle_state?:string};
type TruthRow={id:string;kind:string;record_key:string;status:string;criticality:string;source_type:string;source_reference?:string|null};
type GeometryRow={id:string;verification:string;engine_valid:boolean;area:number;content_hash:string};
type BriefState={briefs?:unknown[];programme_briefs?:unknown[];requirements?:unknown[]};
type Intent={id:string;status:string;optimisation_mode:string};
type DesignState={intents?:Intent[]};
type CompilerRun={id:string;status:string;blocked_reasons?:string[]};
type Candidate={id:string;objective_metrics?:Record<string,unknown>;compliance_state:string};
type CompilerState={run?:CompilerRun|null;stages?:unknown[];candidates?:Candidate[]};

function statusLabel(value:string){return value.replaceAll("_"," ").replace(/\b\w/g,char=>char.toUpperCase());}

export default async function ProjectWorkspace({params}:{params:Promise<{id:string}>}){
  const {id}=await params;
  const {supabase}=await requireWorkspaceUser();
  const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");
  if(projectError)throw new Error(projectError.message);
  const project=((projectData||[]) as ProjectRow[]).find(row=>row.id===id);
  if(!project)notFound();

  const [truthResult,geometryResult,briefResult,designResult,compilerResult]=await Promise.all([
    supabase.rpc("list_project_truth_state",{target_project_id:id}),
    supabase.rpc("list_project_site_geometry",{target_project_id:id}),
    supabase.rpc("list_brief_requirement_workspace",{target_project_id:id}),
    supabase.rpc("list_design_review_workspace",{target_project_id:id}),
    supabase.rpc("list_project_compiler_state",{target_project_id:id})
  ]);
  for(const result of [truthResult,geometryResult,briefResult,designResult,compilerResult])if(result.error)throw new Error(result.error.message);

  const truth=(truthResult.data||[]) as TruthRow[];
  const geometries=(geometryResult.data||[]) as GeometryRow[];
  const brief=(briefResult.data||{}) as BriefState;
  const design=(designResult.data||{}) as DesignState;
  const compiler=(compilerResult.data||{}) as CompilerState;
  const requirements=brief.requirements||[];
  const briefs=brief.briefs||[];
  const intents=design.intents||[];
  const candidates=compiler.candidates||[];
  const verifiedTruth=truth.filter(row=>row.status==="verified").length;
  const declaredTruth=truth.length-verifiedTruth;
  const geometry=geometries[0];
  const approvedIntent=intents.find(intent=>intent.status==="approved");
  const baselineMissing=briefs.length===0||requirements.length===0||intents.length===0;
  const autoStart=baselineMissing||(!geometry&&!compiler.run);
  const firstPending=!briefs.length?`/app/brief?project=${id}`:!approvedIntent?`/app/design-review?project=${id}`:!geometry||geometry.verification==="unverified"?`/app/site-truth?project=${id}`:`/app/compiler?project=${id}`;
  const firstPendingLabel=!briefs.length?"Review project brief":!approvedIntent?"Approve design objective":!geometry||geometry.verification==="unverified"?"Verify site and planning inputs":"Open compiler results";
  const blocked=compiler.run?.blocked_reasons||[];

  const steps=[
    ["01","Project baseline",truth.length?`${truth.length} source-linked records captured`:"Preparing intake baseline",`/app/site-truth?project=${id}`],
    ["02","Brief and requirements",briefs.length?`${briefs.length} draft brief · ${requirements.length} structured requirements`:"Preparing draft brief",`/app/brief?project=${id}`],
    ["03","Design objective",approvedIntent?"Approved for governed compilation":intents.length?"Draft ready for your approval":"Preparing draft objective",`/app/design-review?project=${id}`],
    ["04","First compiler assessment",compiler.run?`${statusLabel(compiler.run.status)} · ${candidates.length} preliminary options`:"Starting first assessment",`/app/compiler?project=${id}`],
    ["05","Professional release","Locked until evidence, checks and approvals are complete",`/app/releases?project=${id}`]
  ];

  return <>
    <div className="topbar"><div><div className="demo">Project Workspace / {project.code}</div><h1>{project.name}</h1><div className="subtle">{project.typology} · {statusLabel(project.stage)} · {statusLabel(project.lifecycle_state||project.status)}</div></div><Link className="btn" href={firstPending}>{firstPendingLabel}</Link></div>
    <ProjectStartupClient projectId={id} autoStart={autoStart}/>

    <div className="kpis" style={{marginTop:16}}>{[
      ["Captured Truth",String(truth.length)],
      ["Verified",String(verifiedTruth)],
      ["Awaiting Evidence",String(declaredTruth)],
      ["Requirements",String(requirements.length)],
      ["Initial Options",String(candidates.length)]
    ].map(([label,value])=><div className="kpi" key={label}><div className="label">{label}</div><div className="value">{value}</div><div className="subtle">Live project state</div></div>)}</div>

    <section className="panel" style={{marginTop:18}}><h3>What happens next</h3><p className="subtle">The platform has started the first governed set. Client declarations can produce preliminary feasibility envelopes, but they cannot become verified facts or construction-ready drawings without evidence and professional approval.</p><div className="grid-3" style={{marginTop:16}}>{steps.map(([number,title,description,href])=><Link href={href} className="card" key={number}><div className="eyebrow">{number}</div><h3>{title}</h3><p>{description}</p><span className="badge">Open workspace</span></Link>)}</div></section>

    <div className="panel-grid" style={{marginTop:18}}><section className="panel"><h3>Current baseline</h3><div className="metric-grid"><div><b>{geometry?.engine_valid?"Valid":"Pending"}</b><span>Deterministic geometry</span></div><div><b>{geometry?statusLabel(geometry.verification):"Pending"}</b><span>Geometry authority</span></div><div><b>{approvedIntent?"Approved":"Draft"}</b><span>Design objective</span></div></div><div className="note" style={{marginTop:14}}><b>For this project:</b> both adjacent plots and the combined outside boundary are preserved. The calculated geometry is preliminary until the survey, deed, DWG/DXF or an authorised professional verifies it.</div></section><section className="panel"><h3>Engine blockers</h3>{blocked.length?<div>{blocked.slice(0,6).map((reason,index)=><div className="note" key={index} style={{marginBottom:8}}>{reason}</div>)}</div>:<div className="subtle">The first compiler assessment is being prepared. Open the compiler workspace for its full stage ledger.</div>}</section></div>
  </>;
}
