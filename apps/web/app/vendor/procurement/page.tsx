import Link from "next/link";
import {redirect} from "next/navigation";
import {createServerSupabaseClient} from "@/lib/supabase-server";
import VendorProcurementClient,{emptyVendorProcurementState,type VendorProcurementState} from "@/components/VendorProcurementClient";

export const dynamic="force-dynamic";

export default async function VendorProcurementPage(){
 const supabase=await createServerSupabaseClient();
 const {data:{user}}=await supabase.auth.getUser();
 if(!user)redirect("/login");
 const {data,error}=await supabase.rpc("list_vendor_procurement_workspace");
 if(error)throw new Error(error.message);
 const state=(data||emptyVendorProcurementState) as VendorProcurementState;
 return <main className="main" style={{maxWidth:1480,margin:"0 auto",padding:"28px"}}>
  <div className="topbar"><div><div className="demo">Vendor Procurement Portal</div><h1>Sealed Tender Workspace</h1><div className="subtle">Invitation acknowledgement, controlled tender scope, clarification and vendor-isolated sealed bid submission.</div></div><Link href="/" className="btn ghost">Concept Spaces</Link></div>
  <VendorProcurementClient state={state}/>
 </main>;
}
