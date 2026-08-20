export type CoordinationProject={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};
export type CoordinationResource={id:string;project_id:string;label:string;hash?:string|null;discipline?:string|null;status?:string|null;criticality?:string|null;confidence?:string|null;schema_version?:string|null;coordinate_system?:string|null;state?:string|null};
export type CoordinationMember={project_id:string;user_id:string;role_code:string;discipline?:string|null;status:string};
export type CoordinationItem={
 id:string;project_id:string;project_code:string;project_name:string;issue_id:string;issue_number:string;issue_status:string;priority:string;
 source_discipline:string;target_discipline:string;subject:string;requirement_ref?:string|null;state:string;criticality:string;owner_user_id?:string|null;
 source_resource?:{type:string;id:string;label:string;hash:string}|null;target_resource?:{type:string;id:string;label:string;hash:string}|null;
 coordination_hash:string;resolution_note?:string|null;resolution_evidence_refs:string[];accepted_deviation_approval_id?:string|null;created_by?:string|null;resolved_by?:string|null;resolved_at?:string|null;created_at:string;updated_at:string;
};
export type CoordinationEvent={id:string;coordination_item_id:string;project_id:string;actor_id:string;event_type:string;reason:string;evidence_refs:string[];snapshot:Record<string,unknown>;created_at:string};
export type CoordinationApproval={id:string;project_id:string;resource_type:string;resource_id:string;requested_from?:string|null;role_required?:string|null;criticality:string;decision:string;comments?:string|null;requested_by?:string|null;requested_at:string;decided_at?:string|null;decision_evidence_hash?:string|null;decided_by?:string|null};
export type CoordinationWorkspaceState={items:CoordinationItem[];events:CoordinationEvent[];approvals:CoordinationApproval[];documents:CoordinationResource[];models:CoordinationResource[];requirements:CoordinationResource[];truth_records:CoordinationResource[];releases:CoordinationResource[];members:CoordinationMember[]};
export const emptyCoordinationWorkspace:CoordinationWorkspaceState={items:[],events:[],approvals:[],documents:[],models:[],requirements:[],truth_records:[],releases:[],members:[]};
