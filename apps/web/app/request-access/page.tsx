import Link from "next/link";
import { Brand } from "@/components/Brand";

export default function RequestAccessPage(){
  return <main className="auth-shell auth-shell-single">
    <section className="auth-card auth-card-wide">
      <Brand/>
      <div className="demo auth-kicker">Organisation-managed access</div>
      <h1>Access begins with a verified invitation.</h1>
      <p className="subtle auth-lede">Concept Spaces is an enterprise workspace. An organisation administrator assigns each person to an organisation, project and role; creating an identity alone never grants access to project, commercial or professional information.</p>
      <div className="grid-3 access-steps">
        <div className="card"><div className="eyebrow">01 / Invitation</div><h3>Receive access</h3><p>Your organisation administrator invites the email address you use for work.</p></div>
        <div className="card"><div className="eyebrow">02 / Verification</div><h3>Verify identity</h3><p>Use your password or the secure email link on the sign-in page.</p></div>
        <div className="card"><div className="eyebrow">03 / Authority</div><h3>Enter your workspace</h3><p>Only active organisation and project memberships expose controlled information.</p></div>
      </div>
      <div className="note"><b>Already invited?</b> Continue to sign in. If you have not been invited, contact your organisation’s Concept Spaces administrator through your normal company channel.</div>
      <div className="hero-actions"><Link href="/login" className="btn">Continue to sign in</Link><Link href="/" className="btn ghost">Back to website</Link></div>
    </section>
  </main>;
}
