export default function IntegrationMonitor(){
  const providers=[
    ['Resend','Email','Not Configured','Signature verification required'],
    ['Razorpay','Payments','Not Configured','Webhook + idempotency required'],
    ['AiSensy','WhatsApp','Not Configured','Template + consent required'],
    ['Fast2SMS','SMS','Not Configured','Sender + consent required'],
    ['GoDaddy','DNS','Not Configured','Restricted admin operation']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Platform Operations / Integrations</div><h1>Integration Monitor</h1><div className="subtle">Provider health, delivery status, webhook verification and degradation are observable without exposing secrets.</div></div></div>
    <div className="panel"><table><thead><tr><th>Provider</th><th>Category</th><th>Status</th><th>Activation Gate</th></tr></thead><tbody>{providers.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Secrets never render here.</b> Configuration stores secret references only. Verification must succeed before a provider can become production-active.</div>
  </>;
}
