"use client";

import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

export default function ProjectStartupClient({projectId,autoStart}:{projectId:string;autoStart:boolean}){
  const router=useRouter();
  const started=useRef(false);
  const [message,setMessage]=useState(autoStart?"Preparing the governed project baseline and first compiler assessment…":"");
  const [failed,setFailed]=useState(false);
  const [running,setRunning]=useState(false);
  const [busy,startTransition]=useTransition();

  const run=useCallback(async()=>{
    setRunning(true);
    setFailed(false);
    setMessage("Preparing the governed project baseline and first compiler assessment…");
    try{
      const response=await fetch(`/api/projects/${projectId}/bootstrap`,{method:"POST",headers:{"content-type":"application/json"}});
      const data=await response.json().catch(()=>({}));
      if(!response.ok){
        setFailed(true);
        setMessage(data.detail||data.error||"Project startup could not be completed.");
        return;
      }
      const issues=Array.isArray(data.issues)?data.issues.map(String):[];
      setMessage(issues.length?`Baseline prepared. Remaining engine issue: ${issues.join(" | ")}`:"Baseline and first compiler assessment prepared.");
      startTransition(()=>router.refresh());
    }catch{
      setFailed(true);
      setMessage("Project startup could not be reached. Please retry.");
    }finally{
      setRunning(false);
    }
  },[projectId,router]);

  useEffect(()=>{
    if(!autoStart||started.current)return;
    started.current=true;
    void run();
  },[autoStart,run]);

  return <div className="note" role="status" style={{marginTop:16}}>
    <b>Project engine:</b> {message||"The startup pipeline is ready."}{busy?" Refreshing workspace…":""}
    {(!autoStart||failed)&&<button className="btn ghost" type="button" onClick={run} disabled={busy||running} style={{marginLeft:12}}>Re-run baseline assessment</button>}
  </div>;
}
