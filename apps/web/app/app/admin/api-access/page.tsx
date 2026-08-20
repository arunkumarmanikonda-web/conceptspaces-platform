export default function ApiAccess(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / API Access</div><h1>API Credentials & Scopes</h1><div className="subtle">Issue scoped machine credentials with expiry, revocation, IP restrictions and immutable request audit.</div></div><button className="btn">Create Credential</button></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">Scope</div><h3>Least Privilege</h3><p>Credentials receive explicit resource/action scopes, never blanket access by default.</p></div>
      <div className="card"><div className="eyebrow">Secret</div><h3>Hash Only</h3><p>Raw API secrets are shown once and are not stored in retrievable form.</p></div>
      <div className="card"><div className="eyebrow">Audit</div><h3>Every Request</h3><p>Request ID, route, status, latency and privacy-safe client fingerprints are logged.</p></div>
    </div>
  </>;
}
