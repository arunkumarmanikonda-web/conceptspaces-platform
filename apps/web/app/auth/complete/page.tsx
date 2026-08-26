"use client";

import Link from "next/link";
import {useEffect,useState} from "react";
import {Brand} from "@/components/Brand";
import {getBrowserSupabaseClient} from "@/lib/supabase-browser";

export default function CompleteAuthenticationPage(){
  const [message,setMessage]=useState("Completing secure sign-in…");
  const [failed,setFailed]=useState(false);

  useEffect(()=>{
    let active=true;
    async function complete(){
      const hash=new URLSearchParams(window.location.hash.slice(1));
      const accessToken=hash.get("access_token");
      const refreshToken=hash.get("refresh_token");
      window.history.replaceState({},"","/auth/complete");
      if(!accessToken||!refreshToken){
        if(active){setFailed(true);setMessage("This invitation link is invalid or has expired.");}
        return;
      }
      const {error}=await getBrowserSupabaseClient().auth.setSession({
        access_token:accessToken,refresh_token:refreshToken
      });
      if(error){
        if(active){
          setFailed(true);
          setMessage("The invitation could not be verified. Request a new invitation from your administrator.");
        }
        return;
      }
      window.location.replace("/app");
    }
    void complete();
    return()=>{active=false;};
  },[]);

  return <main className="auth-shell auth-shell-single"><section className="auth-card"><Brand/><div className="demo auth-kicker">Identity verification</div><h1>{failed?"Invitation not completed.":"Opening your workspace."}</h1><p className="subtle auth-lede" aria-live="polite">{message}</p>{failed?<div className="auth-footer-links"><Link href="/login">Return to sign in</Link><Link href="/request-access">How access works</Link></div>:null}</section></main>;
}
