import { redirect } from "next/navigation";
import { createServerSupabaseClient } from "@/lib/supabase-server";

export type WorkspaceMembership={organisation_id:string;organisation_name:string;role_code:string;status:string};

export async function requireWorkspaceUser(){
  const supabase = await createServerSupabaseClient();
  const { data:{ user } } = await supabase.auth.getUser();
  if(!user) redirect("/login");

  const { data, error } = await supabase.rpc("get_workspace_context");
  if(error) throw new Error(`Unable to resolve workspace membership: ${error.message}`);
  const memberships=((data as {memberships?:WorkspaceMembership[]}|null)?.memberships)||[];
  if(memberships.length===0) redirect("/access-pending");

  return { user, memberships, supabase };
}
