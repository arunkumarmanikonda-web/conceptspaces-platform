const providers = [
  ["DNS / Domain", "GoDaddy", "Not configured", "Domain, DNS and verification records"],
  ["Transactional Email", "Resend", "Not configured", "Client, project, approval and finance email"],
  ["Payments", "Razorpay", "Registration pending", "Invoices, payment links and reconciliation webhooks"],
  ["WhatsApp", "AiSensy", "Not configured", "Template-based client and project communication"],
  ["SMS", "Fast2SMS", "Not configured", "OTP and transactional SMS"],
  ["AI Orchestration", "Provider registry", "Not configured", "Reasoning, vision, speech, embeddings, rendering and document models"]
];

export default function IntegrationsPage(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / Integrations</div><h1>Provider Registry</h1><div className="subtle">Credentials remain server-side. The UI stores masked references, never raw secrets.</div></div><button className="btn">Add Provider</button></div>
    <div className="panel"><h3>Core Integrations</h3><table className="table"><thead><tr><th>Capability</th><th>Provider</th><th>State</th><th>Purpose</th></tr></thead><tbody>{providers.map(([capability,provider,state,purpose])=><tr key={capability}><td>{capability}</td><td>{provider}</td><td><span className="badge">{state}</span></td><td>{purpose}</td></tr>)}</tbody></table></div>
    <div className="grid-3" style={{marginTop:18}}>
      <div className="card"><div className="eyebrow">Secrets</div><h3>Vault-backed credentials</h3><p>Admin records contain secret references only. Production credentials belong in the deployment secret store and may never be returned to the browser.</p></div>
      <div className="card"><div className="eyebrow">Webhooks</div><h3>Signed + idempotent</h3><p>Inbound events are verified against provider signatures, persisted before processing, deduplicated by provider event ID and fully audited.</p></div>
      <div className="card"><div className="eyebrow">Environment</div><h3>Sandbox before production</h3><p>Providers supporting sandbox/test credentials must clear health checks and test transactions before production activation.</p></div>
    </div>
  </>;
}
