-- Durable, private idempotency ledger for the one-time owner-scoped import
-- of the supplied Full_Roadmap JSON/DOCX pair.  This records provenance only;
-- it neither resets user data nor exposes the source mapping through the API.

create table if not exists private.roadmap_import_ledger (
  user_id uuid not null references auth.users(id) on delete cascade,
  import_kind text not null,
  plan_format text not null,
  json_sha256 text not null
    check (json_sha256 ~ '^[0-9a-f]{64}$'),
  docx_sha256 text not null
    check (docx_sha256 ~ '^[0-9a-f]{64}$'),
  source_fingerprint text not null
    check (source_fingerprint ~ '^[0-9a-f]{64}$'),
  imported_at timestamptz not null default statement_timestamp(),
  result jsonb not null default '{}'::jsonb,
  primary key (user_id, source_fingerprint)
);

revoke all on table private.roadmap_import_ledger
  from public, anon, authenticated;
