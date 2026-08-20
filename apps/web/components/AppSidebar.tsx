import Link from "next/link";
import { Brand } from "@/components/Brand";

const items=[
  ["Dashboard","/app"],
  ["CRM & Growth","/app/crm"],
  ["Projects","/app/projects"],
  ["Models","#"],
  ["Documents","#"],
  ["Issues","#"],
  ["Approvals","#"],
  ["Releases","#"],
  ["Quality","#"],
  ["Commercial","/app/commercial"],
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
    <Link href="/app/admin/integrations" className="side-item">Integrations</Link>
    <a className="side-item">Settings</a>
  </aside>;
}
