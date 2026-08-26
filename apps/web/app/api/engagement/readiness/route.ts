import { environmentState } from "@/lib/env";

export async function GET(){
  const env=environmentState();
  return Response.json({
    service:"conceptspaces-engagement",
    ready:env.supabaseConfigured,
    mode:env.supabaseConfigured?"connected":"foundation-preview",
    intake:{guidedJourney:true,persistenceConfigured:env.supabaseConfigured},
    commercial:{proposalHistory:true,activationGates:true,paymentProviderConfigured:env.razorpayConfigured},
    clientPortal:{workspaceReady:true,authenticationConfigured:env.supabaseConfigured,accessModel:"invite-led"},
    accountRecovery:{configured:env.supabaseConfigured,customEmailProviderConfigured:env.resendConfigured},
    professionalAssignments:{workspaceReady:true,credentialAuthorityBindingRequired:true},
    timestamp:new Date().toISOString()
  });
}
