import Link from "next/link";
import { Brand } from "@/components/Brand";

export default function Home(){
  return <div className="shell">
    <header className="nav">
      <Brand/>
      <nav className="navlinks"><a href="#platform">Platform</a><a href="#intelligence">Intelligence</a><a href="#governance">Governance</a><a href="#about">About</a></nav>
      <Link href="/app" className="btn">Request Access</Link>
    </header>
    <section className="hero">
      <div className="hero-copy">
        <div className="eyebrow">Concept Spaces / Platform 01</div>
        <h1>Architecture.<br/>Engineering.<br/>Construction.<br/><span>Intelligence.</span></h1>
        <p>The intelligence layer for the built world. From verified site truth and regulatory context to architecture, engineering, delivery and the living asset — one governed digital thread.</p>
        <div className="hero-actions"><Link href="/app/projects/new" className="btn">Create a Project</Link><a href="#platform" className="btn ghost">Explore Platform</a></div>
      </div>
      <div className="hero-art"><div className="coord">28.6139° N<br/>77.2090° E</div><div className="cross"/></div>
    </section>
    <section className="pillars" id="platform">
      {[
        ['01','UNIFIED PROJECT TRUTH','One governed source for facts, assumptions, decisions, requirements and evidence.'],
        ['02','DESIGN INTELLIGENCE','Human-governed generative architecture connected to real constraints.'],
        ['03','ENGINEERING ASSURANCE','Deterministic computation, specialist review and Proof Before Publish.'],
        ['04','DELIVERY CONTINUITY','Contracts, cost, procurement, construction and asset intelligence stay connected.']
      ].map(([n,h,p])=><div className="pillar" key={n}><div className="num">{n}</div><h3>{h}</h3><p>{p}</p></div>)}
    </section>
    <section className="section" id="intelligence">
      <div className="eyebrow">One continuous building lifecycle</div>
      <h2>Intelligence, given form.</h2>
      <p>Concept Spaces is being built as an India-first, globally extensible AEC operating system where AI interprets and orchestrates, deterministic engines calculate, and qualified professionals remain accountable for critical releases.</p>
      <div className="grid-3"><div className="card"><h3>REGULA™</h3><p>Versioned jurisdictional regulatory intelligence with applicability, precedence and professionally governed publication.</p></div><div className="card"><h3>Building Compiler™</h3><p>Transforms requirements, site truth, rules and design intent into coordinated project information through explicit validation gates.</p></div><div className="card"><h3>Design Assurance Ledger™</h3><p>Every material design decision remains explainable: what, why, source, confidence, version and approval.</p></div></div>
    </section>
    <section className="section governance" id="governance"><div className="eyebrow">Proof Before Publish</div><h2>Nothing is issued because AI produced it.</h2><p>Critical deliverables move only when project truth, requirements, regulation, engineering checks, coordination and professional approvals provide release evidence.</p></section>
    <footer className="footerline">Concept Spaces &nbsp; / &nbsp; Intelligence, Given Form. &nbsp; / &nbsp; conceptspaces.live</footer>
  </div>;
}
