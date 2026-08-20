import { NextResponse } from "next/server";

export const dynamic = "force-dynamic";

export async function GET(){
  return NextResponse.json({
    service:"conceptspaces-content-reporting",
    ready:true,
    mode:"governed-foundation",
    persistenceConfigured:Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
    templateLockRequired:true,
    snapshotProvenanceRequired:true,
    uncontrolledCriticalIssueAllowed:false,
    timestamp:new Date().toISOString()
  });
}
