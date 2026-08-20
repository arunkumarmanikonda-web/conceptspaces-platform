import { supabasePublicConfig } from "@/lib/public-runtime-config";

export type EnvironmentState = {
  appUrl?: string;
  supabaseConfigured: boolean;
  supabaseConfigSource: "environment" | "repository-public-default";
  resendConfigured: boolean;
  razorpayConfigured: boolean;
  aiSensyConfigured: boolean;
  fast2SmsConfigured: boolean;
};

export function environmentState(): EnvironmentState {
  return {
    appUrl: process.env.NEXT_PUBLIC_APP_URL,
    supabaseConfigured: Boolean(
      supabasePublicConfig.url && supabasePublicConfig.publishableKey
    ),
    supabaseConfigSource: supabasePublicConfig.source,
    resendConfigured: Boolean(process.env.RESEND_API_KEY),
    razorpayConfigured: Boolean(process.env.RAZORPAY_KEY_ID && process.env.RAZORPAY_KEY_SECRET),
    aiSensyConfigured: Boolean(process.env.AISENSY_API_KEY),
    fast2SmsConfigured: Boolean(process.env.FAST2SMS_API_KEY)
  };
}

export function requireServerSecret(name: string): string {
  const value = process.env[name];
  if (!value) throw new Error(`Required server secret ${name} is not configured`);
  return value;
}
