export const DEMO_PROJECTS = [
  {
    id: "11111111-1111-1111-1111-111111111111",
    code: "CS-DEMO-001",
    name: "Hospitality Feasibility",
    typology: "Hotel",
    stage: "concept",
    criticality: "C2",
    location: "India",
    progress: 62,
    truthHealth: 92,
    openIssues: 3,
    pendingDecisions: 4
  },
  {
    id: "22222222-2222-2222-2222-222222222222",
    code: "CS-DEMO-002",
    name: "Mixed Use Study",
    typology: "Mixed Use",
    stage: "site_truth",
    criticality: "C2",
    location: "India",
    progress: 45,
    truthHealth: 78,
    openIssues: 7,
    pendingDecisions: 6
  }
] as const;

export const DEMO_TRUTH = [
  { key: "site.location", label: "Site location", value: "Illustrative India site", confidence: "B", status: "verified", source: "Client pin + system validation" },
  { key: "site.area", label: "Plot area", value: "4,860 m²", confidence: "C", status: "draft", source: "Client supplied" },
  { key: "planning.far", label: "FAR / FSI", value: "2.50", confidence: "D", status: "draft", source: "Unverified client input" },
  { key: "planning.height", label: "Height restriction", value: "Not verified", confidence: "D", status: "draft", source: "Authority source required" }
] as const;
