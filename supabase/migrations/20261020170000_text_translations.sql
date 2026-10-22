-- Translations of IGDB's texts into the app's languages: a game's summary and
-- storyline and a company's description, translated by DeepL in igdb-handler
-- (supabase/functions/_shared/deepl.ts) when a member opens the game's or the
-- company's page in another language than English.
--
-- One row per English text and language, keyed by the SHA-256 of the text, so
-- each text is translated once and every member gets the stored copy. A text
-- IGDB rewrites has another hash, so it is translated again; the old row is
-- simply never read again.
--
-- Only the Edge Functions read and write it, with the service role: there are
-- no policies, so members can't read or write it themselves.
--
-- Deploy order: apply this migration before deploying igdb-handler. Without it
-- the function still answers, in English (it logs that it can't read or store
-- the translations).

create table if not exists public.text_translations (
  source_hash text not null check (source_hash ~ '^[0-9a-f]{64}$'),
  lang text not null check (lang ~ '^[a-z]{2}$'),
  translation text not null,
  created_at timestamptz not null default now(),
  primary key (source_hash, lang)
);

comment on table public.text_translations is
  'IGDB texts machine-translated by igdb-handler (DeepL), by the SHA-256 of the English text and the language. Service role only.';

alter table public.text_translations enable row level security;

revoke all on table public.text_translations from anon, authenticated;
