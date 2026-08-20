// Public browser-safe runtime configuration.
//
// The Supabase project URL and publishable key are designed to be exposed to
// browser clients. Authorization is enforced by Row Level Security. Vercel
// environment variables, when present, override these defaults so keys can be
// rotated without code changes. Never place service-role or other privileged
// secrets in this module.

const repositoryDefaultSupabaseUrl = "https://jbvtgherpgrhoilrjqva.supabase.co";
const repositoryDefaultSupabasePublishableKey = "sb_publishable_vmmtUqXZXmLz3sNS940Gmg_9Ch8Z3PN";

export const supabasePublicConfig = {
  url: process.env.NEXT_PUBLIC_SUPABASE_URL ?? repositoryDefaultSupabaseUrl,
  publishableKey:
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ??
    repositoryDefaultSupabasePublishableKey,
  source:
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY
      ? "environment"
      : "repository-public-default"
} as const;
