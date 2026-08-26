import Link from "next/link";
import {requireWorkspaceUser} from "@/lib/auth";

export const dynamic="force-dynamic";

const domains=[
  ["Identity & Access","/app/admin/access","RBAC, ABAC, memberships and professional authority"],
  ["AI Control Plane","/app/admin/ai-control","Models, agents, prompts, execution gates and learning promotion"],
  ["QTO Benchmarks","/app/admin/qto-benchmarks","Golden-reference quantity engine and rule-set certification"],
  ["Engineering Engines","/app/admin/engineering-engines","Certified deterministic discipline engine registry"],
  ["Quality Gates","/app/admin/quality-gates","Evidence-based release and assurance controls"],
  ["Security & Privacy","/app/admin/security","Classification, privacy requests, audit verification and SRE evidence"],
  ["Integrations","/app/admin/integrations","Provider configuration, health and delivery observability"],
  ["API Access","/app/admin/api-access","Scoped credentials and governed data contracts"],
  ["Design System","/app/admin/design-system","Tokens, accessibility audits, localisation and human factors"],
  ["Tax Rules","/app/admin/tax-rules","Effective-dated governed tax configuration"],
  ["System Configuration","/app/admin/system-config","Platform configuration and operating controls"],
  ["Event Catalog","/app/admin/event-catalog","Governed event and audit vocabulary"]
] as const;

export default async function Admin(){
 await requireWorkspaceUser();
 return <>
  <div className="topbar"><div><div className="demo">Super Admin / Governed Control Plane</div><h1>Control Plane</h1><div className="subtle">Administrative workspaces are live operational surfaces. Each destination enforces its own server-side authority and evidence rules.</div></div></div>
  <div className="grid-3">{domains.map(([heading,href,description],index)=><Link className="card" href={href} key={heading}><div className="eyebrow">{String(index+1).padStart(2,"0")}</div><h3>{heading}</h3><p>{description}</p><span className="badge">Open governed workspace</span></Link>)}</div>
  <div className="note" style={{marginTop:18}}><b>No administrative readiness is inferred here.</b> Status, approval, health and release truth remain owned by the source domain and are evaluated inside the corresponding governed workspace.</div>
 </>;
}
