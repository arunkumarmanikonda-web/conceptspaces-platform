import Link from "next/link";
import { Brand } from "@/components/Brand";
import { signInWithPassword, sendMagicLink } from "./actions";

export default async function LoginPage({searchParams}:{searchParams:Promise<{error?:string;sent?:string}>}){
  const params=await searchParams;
  return <main style={{minHeight:'100vh',display:'grid',gridTemplateColumns:'1fr 1fr',background:'#F6F7F8'}}>
    <section style={{background:'#0B1728',color:'#fff',padding:'56px',display:'flex',flexDirection:'column',justifyContent:'space-between'}}>
      <Brand light/>
      <div><div className="eyebrow">Secure Workspace</div><h1 style={{fontSize:54,fontWeight:400,lineHeight:1.05,margin:'20px 0'}}>Project truth.<br/>Professional authority.<br/>One controlled environment.</h1><p style={{color:'#AAB6C5',maxWidth:520,lineHeight:1.7}}>Identity, project access, discipline authority and critical release permissions are independently governed. No administrative role can bypass professional eligibility.</p></div>
      <div style={{fontSize:11,letterSpacing:'.16em',color:'#69809E'}}>CONCEPT SPACES / INTELLIGENCE, GIVEN FORM.</div>
    </section>
    <section style={{display:'flex',alignItems:'center',justifyContent:'center',padding:40}}>
      <div style={{width:'100%',maxWidth:430,background:'#fff',border:'1px solid #E1E4E8',padding:36}}>
        <div className="demo">Supabase Auth / Connected</div><h2 style={{fontSize:32,fontWeight:450}}>Sign in</h2>
        <p className="subtle">Use your password or request a secure email link. The first verified workspace user is bootstrapped as platform administrator; subsequent new users remain pending until assigned access.</p>
        {params.error?<div className="note" style={{borderColor:'#D97B7B'}}><b>Sign-in failed.</b> {params.error}</div>:null}
        {params.sent?<div className="note"><b>Secure link sent.</b> Check your email and complete sign-in in this browser.</div>:null}
        <form action={signInWithPassword}>
          <div className="field" style={{marginTop:26}}><label>Email</label><input name="email" type="email" autoComplete="email" required placeholder="you@company.com"/></div>
          <div className="field" style={{marginTop:16}}><label>Password</label><input name="password" type="password" autoComplete="current-password" required placeholder="••••••••••••"/></div>
          <button className="btn" style={{width:'100%',marginTop:24}}>Continue securely</button>
        </form>
        <div style={{display:'flex',alignItems:'center',gap:10,margin:'20px 0',color:'#8A949F',fontSize:11}}><span style={{height:1,background:'#E1E4E8',flex:1}}/><span>OR</span><span style={{height:1,background:'#E1E4E8',flex:1}}/></div>
        <form action={sendMagicLink}>
          <div className="field"><label>Email for secure link</label><input name="email" type="email" autoComplete="email" required placeholder="you@company.com"/></div>
          <button className="btn ghost" style={{width:'100%',marginTop:14}}>Email me a secure link</button>
        </form>
        <div style={{display:'flex',justifyContent:'space-between',marginTop:18,fontSize:12}}><span>Invite-led access</span><Link href="/">Back to website</Link></div>
      </div>
    </section>
  </main>;
}
