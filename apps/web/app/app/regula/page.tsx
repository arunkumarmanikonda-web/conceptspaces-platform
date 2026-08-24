import Link from "next/link";
import { requireWorkspaceUser } from "@/lib/auth";
import RegulaRuntimeClient,{type RegulaState} from "@/components/RegulaRuntimeClient";
import RegulaGovernanceClient,{type RegulaGovernanceState} from "@/components/RegulaGovernanceClient";

export const dynamic="force-dynamic";
type ProjectRow={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
const emptyState:RegulaState={applicability:[],latest_run:null,latest_findings:[]};
const emptyGovernance:RegulaGovernanceState={packs:[],rules:[],impacts:[]};
export default async function RegulaPage({searchParams}:{searchParams:Promise<{project?:string}>}){
 const {supabase}=await requireWorkspaceUser();const {data:projectData,error:projectError}=await supabase.rpc("list_accessible_projects");if(projectError)throw new Error(projectError.message);const projects=(projectData||[]) as ProjectRow[];const params=await searchParams;const project=projects.find(p=>p.id===params.project)||projects[0];let state=emptyState;if(project){const {data,error}=await supabase.rpc("list_project_regula_state",{target_project_id:project.id});if(error)throw new Error(error.message);state=(data||emptyState) as RegulaState;}
 const {data:governanceData,error:governanceError}=await supabase.rpc("list_regula_governance_workspace");const governance=governanceError?null:(governanceData||emptyGovernance) as RegulaGovernanceState;
 return <>
  <div className="topbar"><div><div className="demo">REGULA™ / Jurisdiction Engine</div><h1>Regulatory Intelligence</h1><div className="subtle">Effective-date applicability, professional confirmation, deterministic Green rules and evidence-bound findings.</div></div></div>
  <section className="panel"><h3>Project</h3><div style={{display:"flex",gap:8,flexWrap:"wrap"}}>{projects.map(p=><Link key={p.id} href={`/app/regula?project=${p.id}`} className={project?.id===p.id?"btn":"btn ghost"} style={{padding:"8px 11px"}}>{p.code} · {p.name}</Link>)}</div>{projects.length===0&&<div className="note">No accessible project exists yet.</div>}</section>
  {project&&<div style={{marginTop:18}}><RegulaRuntimeClient projectId={project.id} state={state}/></div>}
  {governance&&<RegulaGovernanceClient state={governance}/>} 
  <div className="panel-grid"><section className="panel"><h3>Rule Publication Governance</h3><p className="subtle">AI may discover or compare regulatory source material, but it cannot publish a production rule. Published packs retain authority, exact source and clause references, effective dates, immutable hashes and supersession lineage through independent technical/legal review.</p></section><section className="panel"><h3>Production Boundary</h3><p className="subtle">REGULA reports what the evidence supports. It does not replace statutory authority approvals, architect/engineer responsibility or jurisdiction-specific legal interpretation.</p></section></div>
 </>;
}
