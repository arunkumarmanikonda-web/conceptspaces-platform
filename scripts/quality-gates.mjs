import { createHash } from "node:crypto";
import { readFile, readdir } from "node:fs/promises";
import { extname, join, relative } from "node:path";

const root=process.cwd();
const ignored=new Set(["node_modules",".git",".next","dist","coverage",".vercel"]);
const textExt=new Set([".ts",".tsx",".js",".mjs",".json",".yml",".yaml",".md",".sql",".css",".html"]);
const self="scripts/quality-gates.mjs";
const failures=[];

const legacyMigrationBlobs=new Map([
  ["supabase/migrations/0001_foundation.sql","704b7b461715b9457acd76d52b00ed99ce96b296"],
  ["supabase/migrations/0002_integrations.sql","a8700f923094af38224f656b2ebb5b019467fd84"],
  ["supabase/migrations/0011_feasibility_climate_economics.sql","0b46e4e7875c46f8163fd7efcb1e840acb69a41a"],
  ["supabase/migrations/0012_client_intake_engagement.sql","a1ce3986cea9ecd98bbf6025f3e9b313289f0525"],
  ["supabase/migrations/0013_enterprise_governance_ops.sql","380199401d6af6323f67f3a97ae656ed9c79b754"]
]);

function gitBlobSha(text){
  const header=`blob ${Buffer.byteLength(text,"utf8")}\0`;
  return createHash("sha1").update(header).update(text,"utf8").digest("hex");
}

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

function sqlLexicalErrors(sql){
  const errors=[];
  let state="normal";
  let dollarTag="";
  let depth=0;
  let line=1;
  let blockStart=0;
  let quoteStart=0;
  let dollarStart=0;

  for(let i=0;i<sql.length;i++){
    const ch=sql[i];
    const next=sql[i+1];
    if(ch==="\n") line++;

    if(state==="line-comment"){
      if(ch==="\n") state="normal";
      continue;
    }
    if(state==="block-comment"){
      if(ch==="*"&&next==="/"){state="normal";i++;}
      continue;
    }
    if(state==="single"){
      if(ch==="'"&&next==="'"){i++;continue;}
      if(ch==="'") state="normal";
      continue;
    }
    if(state==="double"){
      if(ch==='"'&&next==='"'){i++;continue;}
      if(ch==='"') state="normal";
      continue;
    }
    if(state==="dollar"){
      if(sql.startsWith(dollarTag,i)){
        i+=dollarTag.length-1;
        state="normal";
      }
      continue;
    }

    if(ch==="-"&&next==="-"){state="line-comment";i++;continue;}
    if(ch==="/"&&next==="*"){state="block-comment";blockStart=line;i++;continue;}
    if(ch==="'"){state="single";quoteStart=line;continue;}
    if(ch==='"'){state="double";quoteStart=line;continue;}
    if(ch==="$"){
      const match=sql.slice(i).match(/^\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/);
      if(match){dollarTag=match[0];dollarStart=line;state="dollar";i+=dollarTag.length-1;continue;}
    }
    if(ch==="(") depth++;
    if(ch===")"){
      depth--;
      if(depth<0){errors.push(`unexpected closing parenthesis near line ${line}`);depth=0;}
    }
  }

  if(depth!==0) errors.push(`unbalanced parentheses: ${depth>0?depth+" opening":"extra closing"}`);
  if(state==="block-comment") errors.push(`unterminated block comment starting near line ${blockStart}`);
  if(state==="single") errors.push(`unterminated single-quoted string starting near line ${quoteStart}`);
  if(state==="double") errors.push(`unterminated quoted identifier starting near line ${quoteStart}`);
  if(state==="dollar") errors.push(`unterminated dollar-quoted body ${dollarTag} starting near line ${dollarStart}`);
  return errors;
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
  const original=await readFile(file,"utf8");
  const text=original.toLowerCase();
  const expectedLegacyBlob=legacyMigrationBlobs.get(rel);
  const immutableLegacy=expectedLegacyBlob ? gitBlobSha(original)===expectedLegacyBlob : false;

  if(expectedLegacyBlob && !immutableLegacy){
    failures.push(`${rel}: immutable legacy migration changed; create a new forward migration instead`);
  }
  if(!immutableLegacy && (!text.includes("begin;") || !text.includes("commit;"))){
    failures.push(`${rel}: migration must be transaction wrapped`);
  }
  if(text.includes("create table") && !text.includes("enable row level security")){
    failures.push(`${rel}: table migration has no RLS enablement`);
  }
  for(const err of sqlLexicalErrors(original)) failures.push(`${rel}: ${err}`);
}

if(failures.length){
  console.error("Concept Spaces quality gates failed:\n"+failures.map(v=>` - ${v}`).join("\n"));
  process.exit(1);
}
console.log(`Concept Spaces repository quality gates passed (${files.length} files inspected).`);
