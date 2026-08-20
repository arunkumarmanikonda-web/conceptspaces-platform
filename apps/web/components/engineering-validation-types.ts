export type EngineeringProject={id:string;code:string;name:string;typology:string;stage:string;criticality:string;status:string};

export type EngineeringEngine={
 id:string;code:string;name:string;discipline:string;engine_type:string;vendor?:string|null;version:string;executable_ref?:string|null;
 supported_standards:string[];supported_units:string[];certification_status:string;maximum_criticality:string;checksum?:string|null;enabled:boolean;created_at:string;updated_at:string;
};

export type BenchmarkCase={id:string;engine_id:string;suite_code:string;name:string;standard_reference?:string|null;input_ref:string;expected_result_ref:string;tolerance:Record<string,unknown>;criticality:string;active:boolean;created_at:string};
export type BenchmarkResult={id:string;benchmark_case_id:string;engine_id:string;engine_version:string;passed:boolean;deviation:Record<string,unknown>;evidence_refs:string[];executed_at:string};
export type EngineEvent={id:string;engine_id?:string|null;actor_id:string;event_type:string;reason:string;snapshot:Record<string,unknown>;created_at:string};
export type MepSystem={id:string;project_id:string;project_code:string;project_name:string;discipline:string;system_code:string;name:string;design_criteria:Record<string,unknown>;status:string;created_at:string};
export type CalculationRun={
 id:string;project_id:string;project_code:string;project_name:string;project_criticality:string;discipline:string;calculation_type:string;engine_id:string;engine_code:string;engine_name:string;
 engine_version:string;engine_certification:string;engine_maximum_criticality:string;status:string;input_snapshot_ref:string;input_hash:string;output_ref?:string|null;output_hash?:string|null;
 standard_references:string[];unit_system:string;result_summary:Record<string,unknown>;evidence_refs:string[];created_by?:string|null;finished_at?:string|null;verification_state:string;release_state:string;
};
export type ProfessionalReview={id:string;project_id:string;resource_type:string;resource_id:string;resource_hash:string;discipline:string;reviewer_user_id:string;credential_id:string;decision:string;comments?:string|null;reviewed_at?:string|null;created_at:string};
export type ProfessionalCredential={id:string;credential_type:string;issuing_body:string;registration_number:string;discipline?:string|null;valid_from?:string|null;valid_until?:string|null;verification_status:string};

export type EngineeringWorkspaceState={
 is_platform_admin:boolean;engines:EngineeringEngine[];benchmark_cases:BenchmarkCase[];benchmark_results:BenchmarkResult[];engine_events:EngineEvent[];
 systems:MepSystem[];calculation_runs:CalculationRun[];reviews:ProfessionalReview[];credentials:ProfessionalCredential[];
};

export const emptyEngineeringState:EngineeringWorkspaceState={is_platform_admin:false,engines:[],benchmark_cases:[],benchmark_results:[],engine_events:[],systems:[],calculation_runs:[],reviews:[],credentials:[]};
