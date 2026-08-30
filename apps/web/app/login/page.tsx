import Link from "next/link";
import { Brand } from "@/components/Brand";
import { signInWithPassword, sendMagicLink } from "./actions";
import { MagicLinkSubmitButton } from "./MagicLinkSubmitButton";

export default async function LoginPage({searchParams}:{searchParams:Promise<{error?:string;sent?:string;cooldown?:string}>}){
  const params=await searchParams;
  return <main className="auth-shell">
    <section className="auth-story">
      <Brand light/>
      <div><div className="eyebrow">Secure Workspace</div><h1>Project truth.<br/>Professional authority.<br/>One controlled environment.</h1><p>Identity, project access, discipline authority and critical release permissions are independently governed. No administrative role can bypass professional eligibility.</p></div>
      <div className="auth-signature">CONCEPT SPACES / INTELLIGENCE, GIVEN FORM.</div>
    </section>
    <section className="auth-form-region">
      <div className="auth-card">
        <div className="demo">Supabase Auth / Connected</div><h2 style={{fontSize:32,fontWeight:450}}>Sign in</h2>
        <p className="subtle">Use the password for your invited account or request a secure sign-in link. Authentication verifies identity; organisation and project authority are assigned separately.</p>
        {params.error?<div className="note" style={{borderColor:'#D97B7B'}}><b>Sign-in failed.</b> {params.error}</div>:null}
        {params.sent?<div className="note"><b>{params.cooldown?"Check your email.":"Secure link sent."}</b> {params.cooldown?"A secure link was already requested. Wait one minute before requesting another.":"Check your email and open the newest link in any browser."}</div>:null}
        <form action={signInWithPassword}>
          <div className="field" style={{marginTop:26}}><label htmlFor="password-email">Email</label><input id="password-email" name="email" type="email" autoComplete="email" required placeholder="you@company.com"/></div>
          <div className="field" style={{marginTop:16}}><label htmlFor="password">Password</label><input id="password" name="password" type="password" autoComplete="current-password" required placeholder="••••••••••••"/></div>
          <button className="btn" style={{width:'100%',marginTop:24}}>Continue securely</button>
        </form>
        <div className="auth-inline-link"><Link href="/account/recover">Forgot password?</Link></div>
        <div style={{display:'flex',alignItems:'center',gap:10,margin:'20px 0',color:'#8A949F',fontSize:11}}><span style={{height:1,background:'#E1E4E8',flex:1}}/><span>OR</span><span style={{height:1,background:'#E1E4E8',flex:1}}/></div>
        <form action={sendMagicLink}>
          <div className="field"><label htmlFor="magic-email">Email for secure link</label><input id="magic-email" name="email" type="email" autoComplete="email" required placeholder="you@company.com"/></div>
          <MagicLinkSubmitButton/>
        </form>
        <div className="auth-footer-links"><Link href="/request-access">How access works</Link><Link href="/">Back to website</Link></div>
      </div>
    </section>
  </main>;
}
