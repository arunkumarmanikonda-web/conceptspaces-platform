export default function ContentWorkspace(){
  const rows=[
    ['Public Homepage','public_page','Approved','v7'],
    ['Platform Overview','product_page','Review','v4'],
    ['Project Setup Guide','help_article','Draft','v2'],
    ['Privacy Notice','legal_notice','Approved','v3']
  ];
  return <>
    <div className="topbar"><div><div className="demo">Content / Governed CMS</div><h1>Content Intelligence</h1><div className="subtle">Versioned public, product, help, knowledge and legal content with approval, source and locale history.</div></div><button className="btn">New Content</button></div>
    <div className="panel"><table><thead><tr><th>Content</th><th>Type</th><th>Status</th><th>Version</th></tr></thead><tbody>{rows.map(r=><tr key={r[0]}>{r.map(c=><td key={c}>{c}</td>)}</tr>)}</tbody></table></div>
    <div className="note" style={{marginTop:18}}><b>Publishing control.</b> Content cannot publish unless the current version is explicitly approved. Legal and claims-sensitive content remains maker-checker governed.</div>
  </>;
}
