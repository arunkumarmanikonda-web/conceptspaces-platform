import type { Project, ProjectTruthRecord, ReleaseEvidence, ReleaseGate, Requirement, UUID } from "@conceptspaces/domain";

export interface ProjectRepository {
  list(): Promise<Project[]>;
  get(projectId: UUID): Promise<Project | null>;
  create(input: Omit<Project, "id" | "createdAt" | "updatedAt">): Promise<Project>;
  updateStage(projectId: UUID, stage: Project["stage"]): Promise<Project>;
}

export interface ProjectTruthRepository {
  list(projectId: UUID): Promise<ProjectTruthRecord[]>;
  upsert(record: ProjectTruthRecord): Promise<ProjectTruthRecord>;
  verify(recordId: UUID, verifierId: UUID): Promise<ProjectTruthRecord>;
}

export interface RequirementsRepository {
  list(projectId: UUID): Promise<Requirement[]>;
  upsert(requirement: Requirement): Promise<Requirement>;
}

export interface ReleaseRepository {
  listGates(projectId: UUID): Promise<ReleaseGate[]>;
  listEvidence(gateId: UUID): Promise<ReleaseEvidence[]>;
  addEvidence(evidence: ReleaseEvidence): Promise<ReleaseEvidence>;
  transitionGate(gateId: UUID, state: ReleaseGate["state"]): Promise<ReleaseGate>;
}

export interface DataPlatform {
  projects: ProjectRepository;
  truth: ProjectTruthRepository;
  requirements: RequirementsRepository;
  releases: ReleaseRepository;
}

export type DataMode = "mock" | "supabase";

export function currentDataMode(): DataMode {
  return process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
    ? "supabase"
    : "mock";
}
