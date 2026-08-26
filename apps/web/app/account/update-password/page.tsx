import Link from "next/link";
import { Brand } from "@/components/Brand";
import { requireAuthenticatedUser } from "@/lib/auth";
import { updatePassword } from "./actions";

export default async function UpdatePasswordPage({searchParams}:{searchParams:Promise<{error?:string}>}){
  await requireAuthenticatedUser();
  const params=await searchParams;
  return <main className="auth-shell auth-shell-single">
    <section className="auth-card">
      <Brand/>
      <div className="demo auth-kicker">Verified recovery session</div>
      <h1>Choose a new password.</h1>
      <p className="subtle auth-lede">Use at least 12 characters. A successful update returns you to your authorised workspace or the access-pending screen.</p>
      {params.error?<div className="note auth-error"><b>Password not updated.</b> {params.error}</div>:null}
      <form action={updatePassword}>
        <div className="field"><label htmlFor="new-password">New password</label><input id="new-password" name="password" type="password" minLength={12} autoComplete="new-password" required/></div>
        <div className="field" style={{marginTop:16}}><label htmlFor="password-confirmation">Confirm new password</label><input id="password-confirmation" name="password_confirmation" type="password" minLength={12} autoComplete="new-password" required/></div>
        <button className="btn" style={{width:"100%",marginTop:20}}>Update password</button>
      </form>
      <div className="auth-footer-links"><Link href="/login">Cancel and sign in</Link></div>
    </section>
  </main>;
}
