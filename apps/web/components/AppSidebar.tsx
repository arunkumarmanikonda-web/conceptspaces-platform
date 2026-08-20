import Link from "next/link";
import { Brand } from "@/components/Brand";

const items=[
  ["Dashboard","/app"],
  ["CRM & Growth","/app/crm"],
  ["Projects","/app/projects"],
  ["Site Truth","/app/site-truth"],
  ["Design Intelligence","/app/design"],
  ["REGULA™","/app/regula"],
  ["Models","/app/models"],
  ["Documents","/app/documents"],
  ["Issues & RFIs","/app/issues"],
  ["Approvals","/app/approvals"],
  ["Release Assurance","/app/releases"],
  ["Cost & Quantity","/app/cost"],
  ["Procurement","/app/procurement"],
  ["Site & Delivery","/app/site"],
  ["Digital Twin","/app/twin"],
  ["Commercial","/app/commercial"],
  ["Finance ERP","/app/finance"],
  ["Communications","/app/communications"],
  ["Analytics","#"]
];

export function AppSidebar(){
  return <aside className="sidebar">
    <div className="logo"><Brand light/></div>
    <div className="side-caption">Workspace</div>
    {items.map(([label,href],index)=><Link key={label} href={href} className={`side-item ${index===0?'active':''}`}>{label}</Link>)}
    <div className="side-caption">Platform</div>
    <Link href="/app/admin" className="side-item">Super Admin</Link>
    <Link href="/app/admin/access" className="side-item">Identity & Authority</Link>
    <Link href="/app/admin/integrations" className="side-item">Integrations</Link>
    <Link href="/app/admin/tax-rules" className="side-item">Tax Rule Packs</Link>
    <a className="side-item">Settings</a>
  </aside>;
}
