import {readFile,readdir} from "node:fs/promises";
import {join,relative,extname} from "node:path";

const root=process.cwd();const failures=[];const ignored=new Set(["node_modules",".git",".next","dist","coverage",".vercel"]);
async function walk(dir){const out=[];for(const e of await readdir(dir,{withFileTypes:true})){if(ignored.has(e.name))continue;const p=join(dir,e.name);if(e.isDirectory())out.push(...await walk(p));else out.push(p);}return out;}
const files=await walk(join(root,"apps/web"));
const source=files.filter(f=>[".tsx",".ts",".css"].includes(extname(f)));
for(const file of source){const rel=relative(root,file).replaceAll("\\","/");const text=await readFile(file,"utf8");
 if(rel.startsWith("apps/web/app/")||rel.startsWith("apps/web/components/")){
  if(/\bIllustrative\b/.test(text))failures.push(`${rel}: production UI contains forbidden Illustrative content`);
  if(/CS-DEMO/i.test(text))failures.push(`${rel}: production UI contains forbidden CS-DEMO fixture`);
 }
 if(/outline\s*:\s*(?:none|0)(?:[;!}])/i.test(text))failures.push(`${rel}: focus outline is explicitly removed`);
 const imgs=text.match(/<img\b[^>]*>/gi)||[];for(const img of imgs){if(!/\balt\s*=/.test(img))failures.push(`${rel}: <img> missing alt attribute`);}
 const nonInteractive=text.match(/<(?:div|span)\b[^>]*\bonClick\s*=/gi)||[];if(nonInteractive.length)failures.push(`${rel}: click handler attached to non-interactive div/span; use a semantic control`);
}
const a11yCss=await readFile(join(root,"apps/web/app/accessibility.css"),"utf8");
for(const required of [":focus-visible",".skip-link","prefers-reduced-motion",".mobile-sidebar"]){if(!a11yCss.includes(required))failures.push(`apps/web/app/accessibility.css: required accessibility contract missing ${required}`);}
const appLayout=await readFile(join(root,"apps/web/app/app/layout.tsx"),"utf8");
if(!appLayout.includes('href="#main-content"')||!appLayout.includes('id="main-content"'))failures.push("apps/web/app/app/layout.tsx: skip-to-content contract missing");
if(!appLayout.includes("AccessibilityRuntime"))failures.push("apps/web/app/app/layout.tsx: label/error semantics runtime missing");
const sidebar=await readFile(join(root,"apps/web/components/AppSidebar.tsx"),"utf8");
if(!sidebar.includes("mobile-sidebar")||!sidebar.includes("aria-label=\"Primary workspace navigation\""))failures.push("AppSidebar: semantic desktop/mobile navigation contract missing");
if(failures.length){console.error("Concept Spaces accessibility gate failed:\n"+failures.map(x=>` - ${x}`).join("\n"));process.exit(1);}
console.log(`Concept Spaces accessibility source gate passed (${source.length} UI source files inspected).`);
