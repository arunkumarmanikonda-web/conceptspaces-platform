import test from "node:test";
import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import {compileProject} from "../supabase/functions/_shared/compiler.ts";

const read=(path)=>readFile(new URL(`../${path}`,import.meta.url),"utf8");

test("project intake startup is idempotent, governed and connected to the first run",async()=>{
  const migration=await read("supabase/migrations/0134_project_startup_orchestration.sql");
  const startup=await read("apps/web/lib/project-startup.ts");
  const route=await read("apps/web/app/api/projects/[id]/bootstrap/route.ts");
  const workspace=await read("apps/web/app/app/projects/[id]/page.tsx");
  const projects=await read("apps/web/app/app/projects/page.tsx");
  assert.match(migration,/initialise_project_intake_baseline/);
  assert.match(migration,/security invoker/i);
  assert.match(migration,/grant select on engagement\.proposal_negotiation_events to authenticated/);
  assert.match(migration,/grant usage on schema feasibility to authenticated/);
  assert.match(migration,/feasibility\.typology_packs/);
  assert.match(migration,/feasibility\.programme_briefs/);
  assert.match(migration,/aec\.design_intents/);
  assert.match(migration,/public\.interpret_project_brief/);
  assert.match(migration,/public\.create_project_requirement/);
  assert.match(migration,/public\.create_design_intent/);
  assert.doesNotMatch(migration,/security definer/i);
  assert.doesNotMatch(migration,/\bgrant all\b/i);
  assert.match(startup,/geometry-evaluate/);
  assert.match(startup,/compiler-run/);
  assert.match(route,/initialiseProjectStartup/);
  assert.match(workspace,/What happens next/);
  assert.match(workspace,/ProjectStartupClient/);
  assert.match(projects,/Open workspace/);
});

test("client-declared planning values create preliminary options without becoming verified",()=>{
  const result=compileProject({
    project:{criticality:"C1"},
    objective:"balanced",
    truth:[{record_key:"regulation.client_declared",value:{far:"1.4",groundCoverage:"100%"},status:"draft",source_reference:"intake"}],
    requirements:[{id:"requirement-1",code:"INTAKE-CORE",status:"open",criticality:"C1"}],
    geometry:{engine_valid:true,verification:"unverified",area:192,content_hash:"geometry-hash"},
    regula:null,
    engineering_engines:[],
    discipline_state:{}
  });
  const optionStage=result.stages.find(stage=>stage.stage==="option_generation");
  assert.equal(result.candidates.length,3);
  assert.equal(optionStage?.status,"awaiting_review");
  assert.equal(optionStage?.details.planning_inputs_verified,false);
  assert.equal(result.candidates.every(candidate=>candidate.compliance_state==="not_verified"),true);
  assert.equal(result.status,"blocked");
  assert.match(result.blocked_reasons.join(" "),/verification is required before design release/i);
});
