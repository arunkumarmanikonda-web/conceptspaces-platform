import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import {createClient} from "npm:@supabase/supabase-js@2.112.4";

const jsonHeaders={"Content-Type":"application/json"};
const canonicalInviteRedirect="https://www.conceptspaces.live/auth/complete";

function response(body:Record<string,unknown>,status=200){
  return new Response(JSON.stringify(body),{status,headers:jsonHeaders});
}

Deno.serve(async request=>{
  if(request.method!=="POST") return response({error:"method_not_allowed"},405);
  const authorization=request.headers.get("Authorization");
  if(!authorization) return response({error:"authentication_required"},401);

  const url=Deno.env.get("SUPABASE_URL");
  const anonKey=Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anonKey||!serviceKey) return response({error:"service_configuration_unavailable"},503);

  const userClient=createClient(url,anonKey,{global:{headers:{Authorization:authorization}},auth:{persistSession:false,autoRefreshToken:false}});
  const {data:{user},error:userError}=await userClient.auth.getUser();
  if(userError||!user) return response({error:"authentication_required"},401);

  let input:{action?:string;organisation_id?:string;email?:string;role_code?:string};
  try{input=await request.json();}catch{return response({error:"invalid_json"},400);}
  const action=String(input.action||"invite");
  const organisationId=String(input.organisation_id||"");
  const email=String(input.email||"").trim().toLowerCase();
  const roleCode=String(input.role_code||"").trim().toLowerCase();
  if(!organisationId) return response({error:"organisation_required"},400);

  const serviceClient=createClient(url,serviceKey,{auth:{persistSession:false,autoRefreshToken:false}});
  if(action==="list"){
    const {data,error}=await serviceClient.rpc("service_list_workspace_invitations",{
      actor_user_id:user.id,target_organisation_id:organisationId
    });
    if(error){
      console.error("[identity.invite] register rejected",{code:error.code});
      return response({error:"invitation_register_not_authorised"},403);
    }
    return response({invitations:data||[]});
  }
  if(action!=="invite"||!email||!roleCode) return response({error:"invitation_fields_required"},400);

  const {data:invitation,error:invitationError}=await serviceClient.rpc("service_invite_workspace_identity",{
    actor_user_id:user.id,target_organisation_id:organisationId,target_email:email,target_role_code:roleCode
  });
  if(invitationError){
    console.error("[identity.invite] authority rejected",{code:invitationError.code});
    return response({error:"invitation_not_authorised"},403);
  }

  const invitationId=String(invitation?.invitation_id||"");
  if(invitation?.identity_state==="existing_authorised"){
    return response({status:"existing_identity_authorised",invitation_id:invitationId});
  }

  const {error:deliveryError}=await serviceClient.auth.admin.inviteUserByEmail(email,{redirectTo:canonicalInviteRedirect});
  if(deliveryError){
    const {error:revokeError}=await serviceClient.rpc("service_revoke_workspace_invitation",{
      actor_user_id:user.id,target_invitation_id:invitationId,
      target_reason:"Supabase Auth invitation delivery failed"
    });
    console.error("[identity.invite] delivery failed",{
      status:deliveryError.status,code:deliveryError.code,revoke_failed:Boolean(revokeError)
    });
    return response({error:"invitation_delivery_failed"},502);
  }

  return response({status:"invitation_sent",invitation_id:invitationId});
});
