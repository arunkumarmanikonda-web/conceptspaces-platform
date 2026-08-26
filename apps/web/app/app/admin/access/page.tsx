import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requireWorkspaceUser } from "@/lib/auth";

export const dynamic="force-dynamic";

const roleOptions=[
  "org_admin","sales","project_manager","lead_architect","architect","interior_designer",
  "structural_engineer","mep_engineer","quantity_surveyor","contractor","finance","client","auditor","regulatory_reviewer","super_admin"
];

type Membership={id:string;organisation_id:string;role_code:string;status:string};
type Credential={id:string;credential_type:string;issuing_body:string;registration_number:string;discipline?:string|null;verification_status:string;evidence_uri?:string|null};
type Identity={user_id:string;email?:string|null;display_name?:string|null;phone?:string|null;memberships:Membership[];credentials:Credential[]};
type Invitation={id:string;email:string;role_codes:string[];status:string;expires_at:string;created_at:string};

async function inviteIdentity(formData:FormData){
  "use server";
  const {supabase,memberships}=await requireWorkspaceUser();
  const isAdministrator=memberships.some(m=>m.status==="active"&&["super_admin","org_admin"].includes(m.role_code));
  if(!isAdministrator) throw new Error("Administrator authority is required to invite identities.");
  const email=String(formData.get("email")||"").trim().toLowerCase();
  const roleCode=String(formData.get("role_code")||"").trim().toLowerCase();
  const organisationId=String(formData.get("organisation_id")||"");
  const availableRoles=memberships.some(m=>m.status==="active"&&m.role_code==="super_admin")?roleOptions:roleOptions.filter(role=>role!=="super_admin");
  if(!email||!organisationId||!availableRoles.includes(roleCode)) throw new Error("A work email, organisation and permitted initial role are required.");
  const {data,error}=await supabase.functions.invoke("invite-workspace-identity",{
    body:{action:"invite",email,role_code:roleCode,organisation_id:organisationId}
  });
  if(error){
    console.error("[auth.admin_invite] delivery failed",{message:error.message});
    throw new Error("The identity invitation could not be sent. Check Auth email delivery configuration and try again.");
  }
  const outcome=(data as {status?:string}|null)?.status;
  redirect(`/app/admin/access?invite=${outcome==="existing_identity_authorised"?"authorised":"sent"}`);
}

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

export default async function AccessPage({searchParams}:{searchParams:Promise<{invite?:string}>}){
  const {memberships,supabase,user}=await requireWorkspaceUser();
  const params=await searchParams;
  const adminMembership=memberships.find(m=>m.role_code==="super_admin")||memberships.find(m=>m.role_code==="org_admin");
  if(!adminMembership){
    return <div className="panel"><h3>Identity & Authority</h3><p className="subtle">Administrator authority is required to view this workspace.</p></div>;
  }
  const [{data,error},{data:invitationResponse,error:invitationError}]=await Promise.all([
    supabase.rpc("list_workspace_identities",{target_organisation_id:adminMembership.organisation_id}),
    supabase.functions.invoke("invite-workspace-identity",{
      body:{action:"list",organisation_id:adminMembership.organisation_id}
    })
  ]);
  if(error) throw new Error(`Unable to load identity directory: ${error.message}`);
  if(invitationError) throw new Error(`Unable to load invitation directory: ${invitationError.message}`);
  const identities=(data||[]) as Identity[];
  const invitations=((invitationResponse as {invitations?:Invitation[]}|null)?.invitations||[]);
  const activeUsers=identities.filter(i=>i.memberships.some(m=>m.status==="active")).length;
  const pendingCredentials=identities.flatMap(i=>i.credentials).filter(c=>c.verification_status==="pending").length;
  const verifiedCredentials=identities.flatMap(i=>i.credentials).filter(c=>c.verification_status==="verified").length;
  const privilegedRoles=identities.flatMap(i=>i.memberships).filter(m=>m.status==="active"&&["super_admin","org_admin"].includes(m.role_code)).length;
  const availableRoleOptions=adminMembership.role_code==="super_admin"?roleOptions:roleOptions.filter(role=>role!=="super_admin");

  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Live Access Control</div><h1>Identity & Authority</h1><div className="subtle">Authentication, organisational role, project authority and professional competence remain independently governed.</div></div></div>
    <div className="kpis">
      {[["Directory Identities",String(identities.length)],["Active Users",String(activeUsers)],["Pending Credentials",String(pendingCredentials)],["Verified Credentials",String(verifiedCredentials)],["Privileged Roles",String(privilegedRoles)]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Live database state</div></div>)}
    </div>

    <section className="panel" style={{marginTop:16}}>
      <h3>Invite Identity</h3>
      <p className="subtle">Choose the minimum organisation role required. It becomes active only after the recipient verifies the invited email address.</p>
      {params.invite==="sent"?<div className="note"><b>Invitation requested.</b> The recipient can complete identity verification using the secure email link.</div>:null}
      {params.invite==="authorised"?<div className="note"><b>Existing identity authorised.</b> The approved role is active and the person can use their existing sign-in method.</div>:null}
      <form action={inviteIdentity} className="field-grid"><input type="hidden" name="organisation_id" value={adminMembership.organisation_id}/><div className="field"><label htmlFor="invite-email">Work email</label><input id="invite-email" name="email" type="email" autoComplete="email" required placeholder="person@company.com"/></div><div className="field"><label htmlFor="invite-role">Initial role</label><select id="invite-role" name="role_code" defaultValue="project_manager">{availableRoleOptions.map(role=><option value={role} key={role}>{role.replaceAll("_"," ")}</option>)}</select></div><div className="field" style={{justifyContent:"flex-end"}}><button className="btn">Send secure invitation</button></div></form>
    </section>

    <section className="panel" style={{marginTop:16}}><h3>Invitation Register</h3><div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Email</th><th>Approved role</th><th>Status</th><th>Expires</th></tr></thead><tbody>{invitations.map(invitation=><tr key={invitation.id}><td>{invitation.email}</td><td>{invitation.role_codes.map(role=>role.replaceAll("_"," ")).join(", ")}</td><td><span className="badge">{invitation.status}</span></td><td>{new Date(invitation.expires_at).toLocaleString("en-IN")}</td></tr>)}{invitations.length===0&&<tr><td colSpan={4} className="subtle">No identity invitations have been issued.</td></tr>}</tbody></table></div></section>

    <div className="panel" style={{marginTop:16}}>
      <h3>Workspace Directory</h3>
      <div style={{overflowX:"auto"}}><table className="table"><thead><tr><th>Identity</th><th>Memberships</th><th>Credentials</th><th>Grant Role</th></tr></thead><tbody>
        {identities.map(identity=><tr key={identity.user_id}>
          <td><b>{identity.display_name||identity.email||"Unnamed identity"}</b><div className="subtle">{identity.email||identity.user_id}</div>{identity.user_id===user.id&&<span className="badge">Current user</span>}</td>
          <td>{identity.memberships.length===0?<span className="subtle">No active authority</span>:identity.memberships.map(m=><div key={m.id} style={{marginBottom:8}}><span className="badge">{m.role_code} · {m.status}</span><form action={setMembershipStatus} style={{display:"inline",marginLeft:8}}><input type="hidden" name="membership_id" value={m.id}/><input type="hidden" name="status" value={m.status==="active"?"suspended":"active"}/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}} type="submit">{m.status==="active"?"Suspend":"Activate"}</button></form></div>)}</td>
          <td>{identity.credentials.length===0?<span className="subtle">None submitted</span>:identity.credentials.map(c=><div key={c.id} style={{marginBottom:12}}><b>{c.credential_type}</b><div className="subtle">{c.issuing_body} · {c.registration_number}{c.discipline?` · ${c.discipline}`:""}</div><span className="badge">{c.verification_status}</span>{c.verification_status==="pending"&&<div style={{marginTop:6,display:"flex",gap:6}}><form action={reviewCredential}><input type="hidden" name="credential_id" value={c.id}/><input type="hidden" name="decision" value="verified"/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}}>Verify</button></form><form action={reviewCredential}><input type="hidden" name="credential_id" value={c.id}/><input type="hidden" name="decision" value="rejected"/><button className="btn ghost" style={{padding:"6px 9px",fontSize:9}}>Reject</button></form></div>}</div>)}</td>
          <td><form action={assignRole}><input type="hidden" name="target_user_id" value={identity.user_id}/><input type="hidden" name="organisation_id" value={adminMembership.organisation_id}/><div className="field"><select name="role_code" defaultValue="project_manager">{availableRoleOptions.map(r=><option value={r} key={r}>{r.replaceAll("_"," ")}</option>)}</select><button className="btn" type="submit">Assign</button></div></form></td>
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
