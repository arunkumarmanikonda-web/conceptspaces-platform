import Link from "next/link";
import { Brand } from "@/components/Brand";
import { signOut } from "@/app/login/actions";

export default function AccessPending(){
  return <main style={{minHeight:'100vh',display:'grid',placeItems:'center',background:'#F6F7F8',padding:32}}>
    <section style={{width:'100%',maxWidth:680,background:'#fff',border:'1px solid #E1E4E8',padding:42}}>
      <Brand/>
      <div className="demo" style={{marginTop:32}}>Identity verified / Access pending</div>
      <h1 style={{fontSize:40,fontWeight:450}}>Your account exists, but no workspace authority has been assigned yet.</h1>
      <p className="subtle" style={{fontSize:16,lineHeight:1.7}}>Concept Spaces separates authentication from authority. A verified identity does not automatically receive access to client, project, commercial, engineering or administrative information. A workspace administrator must assign your organisation and role first.</p>
      <div className="note"><b>Security control.</b> This is intentional fail-closed behaviour, not an error.</div>
      <div style={{display:'flex',gap:10,marginTop:24}}><Link href="/" className="btn ghost">Public website</Link><form action={signOut}><button className="btn">Sign out</button></form></div>
    </section>
  </main>;
}
