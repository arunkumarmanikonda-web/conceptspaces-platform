import { readFile, readdir } from "node:fs/promises";
import { extname, join, relative } from "node:path";

const root=process.cwd();
const ignored=new Set(["node_modules",".git",".next","dist","coverage",".vercel"]);
const textExt=new Set([".ts",".tsx",".js",".mjs",".json",".yml",".yaml",".md",".sql",".css",".html"]);
const self="scripts/quality-gates.mjs";
const failures=[];

async function walk(dir){
  const out=[];
  for(const entry of await readdir(dir,{withFileTypes:true})){
    if(ignored.has(entry.name)) continue;
    const full=join(dir,entry.name);
    if(entry.isDirectory()) out.push(...await walk(full));
    else out.push(full);
  }
  return out;
}

const files=await walk(root);
const secretPatterns=[
  ["private_key",new RegExp(["-----BEGIN ","PRIVATE KEY-----"].join(""))],
  ["stripe_live_secret",new RegExp("sk_"+"live_[A-Za-z0-9]{16,}")],
  ["supabase_secret",new RegExp("sb_"+"secret_[A-Za-z0-9_-]{16,}")],
  ["github_pat",new RegExp("github_"+"pat_[A-Za-z0-9_]{20,}")]
];

for(const file of files){
  const rel=relative(root,file).replaceAll("\\","/");
  if(rel===self || !textExt.has(extname(file))) continue;
  const text=await readFile(file,"utf8");
  for(const [name,pattern] of secretPatterns){
    if(pattern.test(text)) failures.push(`${rel}: possible ${name}`);
  }
}

for(const file of files.filter(f=>relative(root,f).replaceAll("\\","/").startsWith("supabase/migrations/") && f.endsWith(".sql"))){
  const rel=relative(root,file).replaceAll("\\","/");
  const text=(await readFile(file,"utf8")).toLowerCase();
  if(!text.includes("begin;") || !text.includes("commit;")) failures.push(`${rel}: migration must be transaction wrapped`);
  if(text.includes("create table") && !text.includes("enable row level security")) failures.push(`${rel}: table migration has no RLS enablement`);
}

if(failures.length){
  console.error("Concept Spaces quality gates failed:\n"+failures.map(v=>` - ${v}`).join("\n"));
  process.exit(1);
}
console.log(`Concept Spaces repository quality gates passed (${files.length} files inspected).`);
