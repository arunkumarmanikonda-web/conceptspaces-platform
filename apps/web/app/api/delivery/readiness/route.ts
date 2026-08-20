import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(){
  return NextResponse.json({
    service:"conceptspaces-delivery-reality-twin",
    ready:true,
    persistenceConfigured:Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    siteOfflineSync:"contract_defined",
    realityCaptureProvidersConfigured:false,
    telemetryProvidersConfigured:false,
    criticalDeviationAutoAcceptance:false,
    failedCommissioningCanHandover:false,
    timestamp:new Date().toISOString()
  });
}
