import { environmentState } from "@/lib/env";

export async function GET(){
  const env=environmentState();
  return Response.json({
    service:"conceptspaces-web",
    ready:true,
    database:{configured:env.supabaseConfigured,requiredForStaticPreview:false},
    providers:{
      email:env.resendConfigured,
      payments:env.razorpayConfigured,
      whatsapp:env.aiSensyConfigured,
      sms:env.fast2SmsConfigured
    },
    mode:env.supabaseConfigured?"connected":"foundation-preview",
    timestamp:new Date().toISOString()
  });
}
