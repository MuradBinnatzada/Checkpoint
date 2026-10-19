// supabase/functions/_shared/catalog_add.ts
//
// igdb-handler's `add` mode: the shared `games` row of a game nobody has added
// yet, made from IGDB's own answer. Members can't write the catalog
// (20261019132900_security_hardening.sql), so this is how a game found by search
// gets its row: the app sends IGDB ids, never a title, a summary or a cover.
// Pure functions with no I/O, so they can be tested.

import { CATALOG_FIELDS, catalogPatch, releaseDate } from './game_details.ts'

/** What a new row needs: what the search shows, plus what the catalog keeps. */
export const ADD_FIELDS = ['name', 'cover.url', 'summary', ...CATALOG_FIELDS].join(', ')

/** The games [igdbIds] (numbers only, never caller text), in one query. */
export function addQuery(igdbIds: number[]): string {
  return `fields ${ADD_FIELDS}; where id = (${igdbIds.join(',')}); limit ${igdbIds.length};`
}

/**
 * `games.id` of an IGDB game. Must stay identical to igdb_game_uuid() in the
 * database, igdbGameUuid() in sync-steam and gameIdForIgdb() in lib/models/game.dart.
 */
export function igdbGameUuid(igdbId: number): string {
  return `00000000-0000-4000-8000-${String(igdbId).padStart(12, '0')}`
}

/**
 * IGDB's cover as the large https URL the app shows (as search results do), or
 * null when there is none or it is not on IGDB's image host (games_cover_url_igdb).
 */
export function coverUrl(cover: unknown): string | null {
  const url = (cover as { url?: unknown } | null)?.url
  if (typeof url !== 'string') return null
  const full = (url.startsWith('//') ? `https:${url}` : url).replace('t_thumb', 't_cover_big')
  return /^https:\/\/images\.igdb\.com\/[A-Za-z0-9/_.-]+$/.test(full) ? full : null
}

// The games_*_length constraints (20261014120000_harden_for_open_signups.sql).
const TITLE_MAX = 300
const SUMMARY_MAX = 10000

/** At most [max] characters, counted as Postgres does (code points). */
function clip(text: string, max: number): string {
  const chars = Array.from(text)
  return chars.length <= max ? text : chars.slice(0, max).join('')
}

/**
 * The new `games` row for [igdbId] from IGDB's [game], or null when IGDB has no
 * game by that id (no name). Filled in like `details` fills a row
 * ([catalogPatch]), so it is complete from the start.
 */
export function newCatalogRow(
  igdbId: number,
  game: Record<string, unknown>,
  nowIso: string,
  createdBy: string | null,
): Record<string, unknown> | null {
  const name = typeof game.name === 'string' ? game.name.trim() : ''
  if (!name) return null
  const released = releaseDate(game.first_release_date)
  return {
    id: igdbGameUuid(igdbId),
    igdb_id: igdbId,
    title: clip(name, TITLE_MAX),
    summary: typeof game.summary === 'string' ? clip(game.summary, SUMMARY_MAX) : '',
    cover_url: coverUrl(game.cover),
    release_year: released === null ? null : Number(released.slice(0, 4)),
    created_by: createdBy,
    ...catalogPatch(game, false, nowIso),
  }
}
