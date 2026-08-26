begin;
alter function public.persist_compiler_run(uuid,uuid,text,text,text,jsonb,jsonb,jsonb,text,jsonb) security invoker;
commit;
