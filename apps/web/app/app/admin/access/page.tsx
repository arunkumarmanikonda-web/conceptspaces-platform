import { revalidatePath } from "next/cache";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

const roleOptions=[
  "org_admin","sales","project_manager","lead_architect","architect","interior_designer",
  "structural_engineer","mep_engineer","quantity_surveyor","contractor","finance","client","auditor","regulatory_reviewer","super_admin"
];

type Membership={id:string;organisation_id:string;role_code:string;status:string};
type Credential={id:string;credential_type:string;issuing_body:string;registration_number:string;discipline?:string|null;verification_status:string;evidence_uri?:string|null};
type Identity={user_id:string;email?:string|null;display_name?:string|null;phone?:string|null;memberships:Membership[];credentials:Credential[]};

async function assignRole(formData:FormData){
  "use server";
  const {supabase,memberships}=await requireWorkspaceUser();
  const organisationId=String(formData.get("organisation_id")||memberships[0]?.organisation_id||"");
  const targetUserId=String(formData.get("target_user_id")||"");
  const roleCode=String(formData.get("role_code")||"");
  if(!organisationId||!targetUserId||!roleCode) throw new Error("Organisation, identity and role are required.");
  const {error}=await supabase.rpc("assign_workspace_role",{
    target_user_id:targetUserId,target_organisation_id:organisationId,target_role_code:roleCode
  });
  if(error) throw new Error(error.message);
  revalidatePath("/app/admin/access");
}

async function setMembershipStatus(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const membershipId=String(formData.get("membership_id")||"");
  const status=String(formData.get("status")||"");
  if(!membershipId||!status) throw new Error("Membership and status are required.");
  const {error}=await supabase.rpc("set_workspace_membership_status",{target_membership_id:membershipId,new_status:status});
  if(error) throw new Error(error.message);
  revalidatePath("/app/admin/access");
}

async function reviewCredential(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const credentialId=String(formData.get("credential_id")||"");
  const decision=String(formData.get("decision")||"");
  if(!credentialId||!decision) throw new Error("Credential and decision are required.");
  const {error}=await supabase.rpc("review_professional_credential",{target_credential_id:credentialId,decision});
  if(error) throw new Error(error.message);
  revalidatePath("/app/admin/access");
}

async function submitOwnCredential(formData:FormData){
  "use server";
  const {supabase}=await requireWorkspaceUser();
  const payload={
    credential_type:String(formData.get("credential_type")||""),
    issuing_body:String(formData.get("issuing_body")||""),
    registration_number:String(formData.get("registration_number")||""),
    discipline:String(formData.get("discipline")||""),
    valid_from:String(formData.get("valid_from")||""),
    valid_until:String(formData.get("valid_until")||""),
    evidence_uri:String(formData.get("evidence_uri")||"")
  };
  const {error}=await supabase.rpc("submit_professional_credential",{input_payload:payload});
  if(error) throw new Error(error.message);
  revalidatePath("/app/admin/access");
}

export default async function AccessPage(){
  const {memberships,supabase,user}=await requireWorkspaceUser();
  const adminMembership=memberships.find(m=>m.role_code==="super_admin")||memberships.find(m=>m.role_code==="org_admin");
  if(!adminMembership){
    return <div className="panel"><h3>Identity & Authority</h3><p className="subtle">Administrator authority is required to view this workspace.</p></div>;
  }
  const {data,error}=await supabase.rpc("list_workspace_identities",{target_organisation_id:adminMembership.organisation_id});
  if(error) throw new Error(`Unable to load identity directory: ${error.message}`);
  const identities=(data||[]) as Identity[];
  const activeUsers=identities.filter(i=>i.memberships.some(m=>m.status==="active")).length;
  const pendingCredentials=identities.flatMap(i=>i.credentials).filter(c=>c.verification_status==="pending").length;
  const verifiedCredentials=identities.flatMap(i=>i.credentials).filter(c=>c.verification_status==="verified").length;
  const privilegedRoles=identities.flatMap(i=>i.memberships).filter(m=>m.status==="active"&&["super_admin","org_admin"].includes(m.role_code)).length;

  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Live Access Control</div><h1>Identity & Authority</h1><div className="subtle">Authentication, organisational role, project authority and professional competence remain independently governed.</div></div></div>
    <div className="kpis">
      {[["Directory Identities",String(identities.length)],["Active Users",String(activeUsers)],["Pending Credentials",String(pendingCredentials)],["Verified Credentials",String(verifiedCredentials)],["Privileged Roles",String(privilegedRoles)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live database state</div></div>)}
    </div>

    <div className="panel" style={{marginTop:16}}>
      <h3>Workspace Directory</h3>
      <div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Identity</th><th>Memberships</th><th>Credentials</th><th>Grant Role</th></tr></thead><tbody>
        {identities.map(identity=><tr key={identity.user_id}>
          <td><b>{identity.display_name||identity.email||"Unnamed identity"}</b><div className="subtle">{identity.email||identity.user_id}</div>{identity.user_id===user.id&&<span className="badge">Current user</span>}</td>
          <td>{identity.memberships.length===0?<span className="subtle">No active authority</span>:identity.memberships.map(m=><div key={m.id} style={{marginBottom:8}}><span className="badge">{m.role_code} · {m.status}</span><form action={setMembershipStatus} style={{display:"inline",marginLeft:8}}><input type="hidden" name="membership_id" value={m.id}/><input type="hidden" name="status" value={m.status==="active"?"suspended":"active"}/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}} type="submit">{m.status==="active"?"Suspend":"Activate"}</button></form></div>)}</td>
          <td>{identity.credentials.length===0?<span className="subtle">None submitted</span>:identity.credentials.map(c=><div key={c.id} style={{marginBottom:12}}><b>{c.credential_type}</b><div className="subtle">{c.issuing_body} · {c.registration_number}{c.discipline?` · ${c.discipline}`:""}</div><span className="badge">{c.verification_status}</span>{c.verification_status==="pending"&&<div style={{marginTop:6,display:"flex",gap:6}}><form action={reviewCredential}><input type="hidden" name="credential_id" value={c.id}/><input type="hidden" name="decision" value="verified"/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}}>Verify</button></form><form action={reviewCredential}><input type="hidden" name="credential_id" value={c.id}/><input type="hidden" name="decision" value="rejected"/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}}>Reject</button></form></div>}</div>)}</td>
          <td><form action={assignRole}><input type="hidden" name="target_user_id" value={identity.user_id}/><input type="hidden" name="organisation_id" value={adminMembership.organisation_id}/><div className="field"><select name="role_code" defaultValue="project_manager">{roleOptions.map(r=><option value={r} key={r}>{r.replaceAll("_"," ")}</option>)}</select><button className="btn" type="submit">Assign</button></div></form></td>
        </tr>)}
        {identities.length===0&&<tr><td colSpan={4} className="subtle">No identities are visible in this organisation yet.</td></tr>}
      </tbody></table></div>
    </div>

    <div className="panel-grid">
      <section className="panel"><h3>Submit My Professional Credential</h3><form action={submitOwnCredential}><div className="field-grid">
        <div className="field"><label>Credential Type</label><input name="credential_type" placeholder="Architect registration" required/></div>
        <div className="field"><label>Issuing Body</label><input name="issuing_body" placeholder="Council / authority" required/></div>
        <div className="field"><label>Registration Number</label><input name="registration_number" required/></div>
        <div className="field"><label>Discipline</label><input name="discipline" placeholder="Architecture / Structure / MEPF"/></div>
        <div className="field"><label>Valid From</label><input type="date" name="valid_from"/></div>
        <div className="field"><label>Valid Until</label><input type="date" name="valid_until"/></div>
        <div className="field" style={{gridColumn:"1 / -1"}}><label>Evidence URI</label><input name="evidence_uri" placeholder="Private evidence reference or verified registry URL"/></div>
      </div><button className="btn" style={{marginTop:16}}>Submit for Independent Review</button></form></section>
      <section className="panel"><h3>Authority Principle</h3><p className="subtle">A workspace role never creates professional competence. Super Admin controls the platform but cannot impersonate a discipline signatory or bypass C3/C4 professional gates. Credential verification remains a separate evidence-backed decision.</p><div className="note"><b>Safety floor.</b> The database refuses suspension of the last active Super Admin.</div></section>
    </div>
  </>;
}
