import { revalidatePath } from "next/cache";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";
type Task={id:string;title:string;task_type:string;state:string;priority:string;assignee_user_id?:string|null;assignee_role_code?:string|null;due_at?:string|null;sla_breached:boolean;maker_user_id?:string|null;checker_user_id?:string|null;project_id?:string|null;created_at:string};
type Project={id:string;code:string;name:string};

async function createTask(formData:FormData){
  "use server";
  const {supabase,memberships}=await requireWorkspaceUser();
  const org=memberships[0]?.organisation_id;if(!org) throw new Error("Organisation required.");
  const payload={organisation_id:org,project_id:String(formData.get("project_id")||""),title:String(formData.get("title")||""),task_type:String(formData.get("task_type")||"manual"),priority:String(formData.get("priority")||"normal"),assignee_role_code:String(formData.get("assignee_role_code")||""),due_at:String(formData.get("due_at")||""),evidence_refs:[]};
  const {error}=await supabase.rpc("create_work_task",{input_payload:payload});if(error) throw new Error(error.message);revalidatePath("/app/workflows");
}
async function transitionTask(formData:FormData){
  "use server";const {supabase}=await requireWorkspaceUser();const {error}=await supabase.rpc("transition_work_task",{target_task_id:String(formData.get("task_id")||""),new_state:String(formData.get("state")||""),evidence_refs:[]});if(error) throw new Error(error.message);revalidatePath("/app/workflows");
}

export default async function WorkflowsPage(){
  const {supabase,memberships,user}=await requireWorkspaceUser();const org=memberships[0]?.organisation_id;
  const [{data:taskData,error:taskError},{data:projectData,error:projectError}]=await Promise.all([
    supabase.rpc("list_work_tasks",{target_organisation_id:org,target_project_id:null}),
    supabase.rpc("list_accessible_projects")
  ]);
  if(taskError||projectError) throw new Error(taskError?.message||projectError?.message||"Unable to load work queue.");
  const tasks=(taskData||[]) as Task[];const projects=(projectData||[]) as Project[];const projectMap=new Map(projects.map(p=>[p.id,`${p.code} · ${p.name}`]));
  const open=tasks.filter(t=>!["approved","rejected","cancelled"].includes(t.state)).length;
  const slaRisk=tasks.filter(t=>t.sla_breached||Boolean(t.due_at&&new Date(t.due_at)<new Date()&&!['approved','rejected','cancelled'].includes(t.state))).length;
  const awaitingChecker=tasks.filter(t=>t.state==="submitted").length;
  const assignedToMe=tasks.filter(t=>t.assignee_user_id===user.id).length;
  const rejected=tasks.filter(t=>t.state==="rejected").length;
  return <>
    <div className="topbar"><div><div className="demo">Live Workflow Operations / Maker-Checker</div><h1>Work Queue</h1><div className="subtle">Human, agent, system and integration work coordinated through explicit tasks, evidence, SLAs and independent checks.</div></div></div>
    <div className="kpis">{[["Open Tasks",String(open)],["SLA Risk",String(slaRisk)],["Awaiting Checker",String(awaitingChecker)],["Assigned To Me",String(assignedToMe)],["Rejected",String(rejected)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live workspace state</div></div>)}</div>
    <div className="panel-grid">
      <section className="panel"><h3>Create Work Task</h3><form action={createTask}><div className="field-grid"><div className="field"><label>Title</label><input name="title" required/></div><div className="field"><label>Project</label><select name="project_id"><option value="">Organisation-wide</option>{projects.map(p=><option value={p.id} key={p.id}>{p.code} · {p.name}</option>)}</select></div><div className="field"><label>Task Type</label><input name="task_type" defaultValue="manual"/></div><div className="field"><label>Priority</label><select name="priority" defaultValue="normal"><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select></div><div className="field"><label>Assignee Role</label><input name="assignee_role_code" placeholder="project_manager / finance / lead_architect"/></div><div className="field"><label>Due At</label><input type="datetime-local" name="due_at"/></div></div><button className="btn" style={{marginTop:16}}>Create Task</button></form></section>
      <section className="panel"><h3>Maker-Checker Boundary</h3><p className="subtle">Where independent review is required, the person preparing a controlled action cannot satisfy the checker role for the same action.</p><div className="note"><b>Database enforced.</b> A task maker is rejected if they attempt to approve or reject their own submitted task.</div></section>
    </div>
    <section className="panel" style={{marginTop:16}}><h3>Priority Queue</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Task</th><th>Project</th><th>Assignee</th><th>Priority</th><th>State</th><th>Due</th><th>Transition</th></tr></thead><tbody>{tasks.map(t=><tr key={t.id}><td><b>{t.title}</b><div className="subtle">{t.task_type} · {t.id.slice(0,8)}</div></td><td>{t.project_id?projectMap.get(t.project_id)||t.project_id.slice(0,8):"Organisation"}</td><td>{t.assignee_role_code||t.assignee_user_id?.slice(0,8)||"Unassigned"}</td><td>{t.priority}</td><td><span className="badge">{t.state}</span>{t.maker_user_id===user.id&&<div className="subtle">You are maker</div>}</td><td>{t.due_at?new Date(t.due_at).toLocaleString("en-IN"):"—"}</td><td><div style={{display:"flex",gap:5,flexWrap:"wrap"}}>{t.state==="open"&&<form action={transitionTask}><input type="hidden" name="task_id" value={t.id}/><input type="hidden" name="state" value="in_progress"/><button className="btn ghost" style={{padding:7,fontSize:9}}>Start</button></form>}{t.state==="in_progress"&&<form action={transitionTask}><input type="hidden" name="task_id" value={t.id}/><input type="hidden" name="state" value="submitted"/><button className="btn ghost" style={{padding:7,fontSize:9}}>Submit</button></form>}{t.state==="submitted"&&<><form action={transitionTask}><input type="hidden" name="task_id" value={t.id}/><input type="hidden" name="state" value="approved"/><button className="btn ghost" style={{padding:7,fontSize:9}}>Approve</button></form><form action={transitionTask}><input type="hidden" name="task_id" value={t.id}/><input type="hidden" name="state" value="rejected"/><button className="btn ghost" style={{padding:7,fontSize:9}}>Reject</button></form></>}</div></td></tr>)}{tasks.length===0&&<tr><td colSpan={7} className="subtle">No tasks yet.</td></tr>}</tbody></table></div></section>
  </>;
}
