import Link from "next/link";
import {Brand} from "@/components/Brand";

const items=[
 ["Dashboard","/app"],["Ask Your Project™","/app/ask"],["CRM & Growth","/app/crm"],["Client Portal","/app/client-portal"],["Engagement","/app/engagement"],["Scope Configurator","/app/scope"],["Professionals","/app/professionals"],["Projects","/app/projects"],["Brief & Requirements","/app/brief"],["Building Compiler™","/app/compiler"],["Project Branches","/app/branches"],["Change Impact","/app/change-impact"],["Design Linter™","/app/design-linter"],["Adversarial Review","/app/design-review"],["Design Genome™","/app/learning"],["Workflows","/app/workflows"],["Risk","/app/risk"],["Compliance","/app/compliance"],["Audit","/app/audit"],["Feasibility","/app/feasibility"],["Programme","/app/programme"],["Climate & Environment","/app/climate"],["Development Economics","/app/economics"],["Site Truth","/app/site-truth"],["Design Intelligence","/app/design"],["Engineering","/app/engineering"],["Architecture","/app/architecture"],["Interiors","/app/interiors"],["Structure","/app/structure"],["MEPF Systems","/app/mep"],["Coordination","/app/coordination"],["REGULA™","/app/regula"],["Models","/app/models"],["Documents","/app/documents"],["Content","/app/content"],["Reports","/app/reports"],["Presentations","/app/presentations"],["Issues & RFIs","/app/issues"],["Approvals","/app/approvals"],["Release Assurance","/app/releases"],["Cost & Quantity","/app/cost"],["Procurement","/app/procurement"],["Site & Delivery","/app/site"],["Site Quality","/app/site-quality"],["Reality Capture","/app/reality"],["Commissioning","/app/commissioning"],["Digital Twin","/app/twin"],["Asset Operations","/app/asset-operations"],["Commercial","/app/commercial"],["Finance ERP","/app/finance"],["Communications","/app/communications"],["Events","/app/events"],["Integration Monitor","/app/integration-monitor"],["Reliability","/app/reliability"],["Incidents","/app/incidents"],["Analytics","/app/analytics"]
] as const;
const platform=[
 ["Super Admin","/app/admin"],["Identity & Authority","/app/admin/access"],["Integrations","/app/admin/integrations"],["API Access","/app/admin/api-access"],["Event Catalog","/app/admin/event-catalog"],["Security Assurance","/app/admin/security"],["Design System & Accessibility","/app/admin/design-system"],["Quality Gates","/app/admin/quality-gates"],["Workflow Definitions","/app/admin/workflows"],["System Configuration","/app/admin/system-config"],["CMS Governance","/app/admin/cms"],["Document Templates","/app/admin/templates"],["Typology Packs","/app/admin/typologies"],["Tax Rule Packs","/app/admin/tax-rules"],["AI Control Plane","/app/admin/ai-control"],["Engineering Engines","/app/admin/engineering-engines"]
] as const;

function Links(){return <><div className="side-caption">Workspace</div>{items.map(([label,href])=><Link key={label} href={href} className="side-item">{label}</Link>)}<div className="side-caption">Platform</div>{platform.map(([label,href])=><Link key={label} href={href} className="side-item">{label}</Link>)}</>}

export function AppSidebar(){
 return <>
  <aside className="sidebar" aria-label="Primary workspace navigation"><div className="logo"><Brand light/></div><nav><Links/></nav></aside>
  <details className="mobile-sidebar"><summary>Workspace navigation</summary><nav aria-label="Mobile workspace navigation"><Links/></nav></details>
 </>;
}
