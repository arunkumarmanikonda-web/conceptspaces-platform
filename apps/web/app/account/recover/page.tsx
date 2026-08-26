import Link from "next/link";
import { Brand } from "@/components/Brand";
import { sendPasswordReset } from "./actions";

export default async function RecoverPasswordPage({searchParams}:{searchParams:Promise<{error?:string;sent?:string}>}){
  const params=await searchParams;
  return <main className="auth-shell auth-shell-single">
    <section className="auth-card">
      <Brand/>
      <div className="demo auth-kicker">Account recovery</div>
      <h1>Reset your password.</h1>
      <p className="subtle auth-lede">Enter the email address associated with your invited account. For privacy, the confirmation is the same whether or not an account exists.</p>
      {params.error?<div className="note auth-error"><b>Unable to continue.</b> {params.error}</div>:null}
      {params.sent?<div className="note"><b>Check your email.</b> If an invited account exists, a password-recovery link has been sent.</div>:null}
      <form action={sendPasswordReset}>
        <div className="field"><label htmlFor="recovery-email">Work email</label><input id="recovery-email" name="email" type="email" autoComplete="email" required placeholder="you@company.com"/></div>
        <button className="btn" style={{width:"100%",marginTop:18}}>Send recovery link</button>
      </form>
      <div className="auth-footer-links"><Link href="/login">Return to sign in</Link><Link href="/">Public website</Link></div>
    </section>
  </main>;
}
