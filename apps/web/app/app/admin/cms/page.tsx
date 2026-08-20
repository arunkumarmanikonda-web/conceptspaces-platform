export default function CmsAdmin(){
  return <>
    <div className="topbar"><div><div className="demo">Super Admin / CMS</div><h1>Content Governance</h1><div className="subtle">Configure content types, locales, approval routes, SEO fields, legal notices and publishing authority.</div></div></div>
    <div className="grid-3">
      <div className="card"><div className="eyebrow">Locales</div><h3>Market-aware Content</h3><p>Separate approved versions per locale and jurisdiction.</p></div>
      <div className="card"><div className="eyebrow">Approval</div><h3>Maker-Checker</h3><p>Claims, legal and public content can require specific reviewer roles.</p></div>
      <div className="card"><div className="eyebrow">SEO</div><h3>Structured Metadata</h3><p>Canonical, robots and structured-data policies remain governed.</p></div>
    </div>
  </>;
}
