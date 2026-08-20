import Link from "next/link";
import { Brand } from "@/components/Brand";

const items=[
  ["Dashboard","/app"],
  ["Ask Your Project™","/app/ask"],
  ["CRM & Growth","/app/crm"],
  ["Client Portal","/app/client-portal"],
  ["Engagement","/app/engagement"],
  ["Scope Configurator","/app/scope"],
  ["Professionals","/app/professionals"],
  ["Projects","/app/projects"],
  ["Workflows","/app/workflows"],
  ["Risk","/app/risk"],
  ["Compliance","/app/compliance"],
  ["Audit","/app/audit"],
  ["Feasibility","/app/feasibility"],
  ["Programme","/app/programme"],
  ["Climate & Environment","/app/climate"],
  ["Development Economics","/app/economics"],
  ["Site Truth","/app/site-truth"],
  ["Design Intelligence","/app/design"],
  ["Engineering","/app/engineering"],
  ["Architecture","/app/architecture"],
  ["Interiors","/app/interiors"],
  ["Structure","/app/structure"],
  ["MEPF Systems","/app/mep"],
  ["Coordination","/app/coordination"],
  ["REGULA™","/app/regula"],
  ["Models","/app/models"],
  ["Documents","/app/documents"],
  ["Content","/app/content"],
  ["Reports","/app/reports"],
  ["Presentations","/app/presentations"],
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
  ["Events","/app/events"],
  ["Integration Monitor","/app/integration-monitor"],
  ["Analytics","/app/analytics"]
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
    <Link href="/app/admin/api-access" className="side-item">API Access</Link>
    <Link href="/app/admin/event-catalog" className="side-item">Event Catalog</Link>
    <Link href="/app/admin/workflows" className="side-item">Workflow Definitions</Link>
    <Link href="/app/admin/system-config" className="side-item">System Configuration</Link>
    <Link href="/app/admin/cms" className="side-item">CMS Governance</Link>
    <Link href="/app/admin/templates" className="side-item">Document Templates</Link>
    <Link href="/app/admin/typologies" className="side-item">Typology Packs</Link>
    <Link href="/app/admin/tax-rules" className="side-item">Tax Rule Packs</Link>
    <Link href="/app/admin/ai-control" className="side-item">AI Control Plane</Link>
    <Link href="/app/admin/engineering-engines" className="side-item">Engineering Engines</Link>
  </aside>;
}
