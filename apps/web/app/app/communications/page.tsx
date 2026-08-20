const queue=[
  ["EMAIL","Proposal PR-2026-002","Resend","Queued"],
  ["WHATSAPP","Approval reminder: façade option","AiSensy","Awaiting template"],
  ["SMS","Invoice CS/26-27/001 due reminder","Fast2SMS","Scheduled"],
  ["IN-APP","Drawing release ready for review","Internal","Queued"]
];

export default function CommunicationsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Illustrative Environment</div><h1>Communications</h1><div className="subtle">Consent-aware transactional email, WhatsApp, SMS and in-app delivery</div></div><button className="btn">New Message</button></div>
    <div className="kpis">{[["Queued","12"],["Sent Today","38"],["Failed","00"],["WhatsApp Templates","07"],["Provider Health","4 / 4"]].map(([l,v])=><div className="kpi" key={l}><div className="label">{l}</div><div className="value">{v}</div><div className="subtle">Illustrative</div></div>)}</div>
    <section className="panel" style={{marginTop:16}}><h3>Delivery Queue</h3><table className="table"><thead><tr><th>Channel</th><th>Intent</th><th>Provider</th><th>Status</th></tr></thead><tbody>{queue.map(row=><tr key={row[1]}><td>{row[0]}</td><td>{row[1]}</td><td>{row[2]}</td><td><span className="badge">{row[3]}</span></td></tr>)}</tbody></table></section>
    <div className="panel-grid"><section className="panel"><h3>Channel Governance</h3><p className="subtle">Transactional communications are separated from marketing communications. Consent basis is stored per intent. WhatsApp messages requiring approved templates cannot bypass template status. SMS and email retries use bounded backoff and idempotency keys.</p></section><section className="panel"><h3>Fallback Logic</h3><p className="subtle">Email: Resend<br/>WhatsApp: AiSensy<br/>SMS: Fast2SMS<br/>Payments: Razorpay when activated<br/>DNS: GoDaddy when connected</p></section></div>
  </>;
}
