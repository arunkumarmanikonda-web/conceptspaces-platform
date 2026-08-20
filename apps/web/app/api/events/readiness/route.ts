import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(){
  const providers={
    resend:Boolean(process.env.RESEND_API_KEY),
    razorpay:Boolean(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET),
    aisensy:Boolean(process.env.AISENSY_API_KEY),
    fast2sms:Boolean(process.env.FAST2SMS_API_KEY),
    godaddy:Boolean(process.env.GODADDY_API_KEY && process.env.GODADDY_API_SECRET)
  };
  return NextResponse.json({
    service:"conceptspaces-event-integration-backbone",
    ready:true,
    persistenceConfigured:Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    providers,
    webhookVerificationRequired:true,
    idempotencyRequired:true,
    criticalAutoReplayAllowed:false,
    timestamp:new Date().toISOString()
  });
}
