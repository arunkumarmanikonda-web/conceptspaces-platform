import Link from "next/link";
import { Brand } from "@/components/Brand";

export default function LoginPage(){
  return <main style={{minHeight:'100vh',display:'grid',gridTemplateColumns:'1fr 1fr',background:'#F6F7F8'}}>
    <section style={{background:'#0B1728',color:'#fff',padding:'56px',display:'flex',flexDirection:'column',justifyContent:'space-between'}}>
      <Brand light/>
      <div><div className="eyebrow">Secure Workspace</div><h1 style={{fontSize:54,fontWeight:400,lineHeight:1.05,margin:'20px 0'}}>Project truth.<br/>Professional authority.<br/>One controlled environment.</h1><p style={{color:'#AAB6C5',maxWidth:520,lineHeight:1.7}}>Identity, project access, discipline authority and critical release permissions are independently governed. No administrative role can bypass professional eligibility.</p></div>
      <div style={{fontSize:11,letterSpacing:'.16em',color:'#69809E'}}>CONCEPT SPACES / INTELLIGENCE, GIVEN FORM.</div>
    </section>
    <section style={{display:'flex',alignItems:'center',justifyContent:'center',padding:40}}><div style={{width:'100%',maxWidth:430,background:'#fff',border:'1px solid #E1E4E8',padding:36}}><div className="demo">Authentication Foundation</div><h2 style={{fontSize:32,fontWeight:450}}>Sign in</h2><p className="subtle">Supabase Auth will be activated when the isolated project is provisioned. This screen is the final UI contract.</p><div className="field" style={{marginTop:26}}><label>Email</label><input placeholder="you@company.com"/></div><div className="field" style={{marginTop:16}}><label>Password</label><input type="password" placeholder="••••••••••••"/></div><button className="btn" style={{width:'100%',marginTop:24}}>Continue</button><div style={{display:'flex',justifyContent:'space-between',marginTop:18,fontSize:12}}><a>Forgot password?</a><Link href="/">Back to website</Link></div></div></section>
  </main>;
}
