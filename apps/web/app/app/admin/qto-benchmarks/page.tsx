import {requireWorkspaceUser} from "@/lib/auth";
import QTOBenchmarkGovernanceClient,{emptyQTOBenchmarkWorkspace,type QTOBenchmarkWorkspace} from "@/components/QTOBenchmarkGovernanceClient";

export const dynamic="force-dynamic";

export default async function QTOBenchmarksPage(){
 const {supabase}=await requireWorkspaceUser();
 const {data,error}=await supabase.rpc("list_qto_benchmark_workspace");
 if(error)throw new Error(error.message);
 const workspace=(data||emptyQTOBenchmarkWorkspace) as QTOBenchmarkWorkspace;
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / F18 Quantity Assurance</div><h1>QTO Benchmark Certification</h1><div className="subtle">Independent golden-reference certification for quantity engines and measurement rule sets. Project QTO runs fail closed unless the exact engine/version and rule set have a current approved passing benchmark.</div></div></div>
  <QTOBenchmarkGovernanceClient workspace={workspace}/>
  <div className="note" style={{marginTop:16}}><b>Independent assurance.</b> The maker of a benchmark case cannot approve it, and the recorder of an engine result cannot approve that result. Failed benchmark results cannot be certified.</div>
 </>;
}
