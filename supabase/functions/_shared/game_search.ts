// supabase/functions/_shared/game_search.ts
//
// How a text search finds games whose title is still being typed. Pure functions
// with no I/O, so they can be tested.
//
// IGDB's `search` matches whole words: "elden rin" does not find Elden Ring,
// because "rin" is no word of its name. A search is typed a letter at a time, so
// its last word is usually unfinished. A page of results is therefore one list
// joined from two:
//
//   1. title matches: up to TITLE_MATCHES rated games whose name has a word
//      starting with every typed word ("elden rin": Elden Ring), most ratings
//      first, so the well-known game being typed comes first;
//   2. IGDB's relevance search for the whole text, without those games. It
//      finds what titles alone can't: alternative names and abbreviations.
//
// Paging counts positions in the joined list, so the app pages it like any
// other. Every page asks for the title matches again (they are the first
// positions, and the search leaves them out), so no page needs state.

import { filterConditions, type GameFilters } from './game_filters.ts'

/** Most title matches put ahead of IGDB's search. */
export const TITLE_MATCHES = 10

/** A text of more words than this is searched as it is, without title matches. */
export const MAX_TITLE_WORDS = 8

/**
 * The words of [term] for title matching: lower case, split at anything that is
 * not a letter, a digit or an apostrophe, without repeats. A typographic
 * apostrophe (what a phone keyboard types) becomes the plain one IGDB names use.
 * Only those characters are left, so a word needs no escaping in a quoted
 * Apicalypse string. Empty when there is nothing to match, or more than
 * MAX_TITLE_WORDS words.
 */
export function titleWords(term: string): string[] {
  const words = [
    ...new Set(
      term
        .toLowerCase()
        .replace(/’/g, "'")
        .split(/[^\p{L}\p{N}']+/u)
        .filter((w) => w.length > 0),
    ),
  ]
  return words.length > MAX_TITLE_WORDS ? [] : words
}

/**
 * The condition that a game's name has a word starting with [word]: the name
 * starts with it, or has it after a space, hyphen or slash ("man" finds
 * Spider-Man, "stay" Fate/stay night). `~` ignores case; the `*` outside the
 * quotes is IGDB's wildcard.
 */
export function wordStartCondition(word: string): string {
  return `(name ~ "${word}"* | name ~ *" ${word}"* | name ~ *"-${word}"* | name ~ *"/${word}"*)`
}

/**
 * The title matches of [words], narrowed by [filters]: rated games with a word
 * starting with each of [words], most ratings first.
 */
export function titleMatchQuery(fields: string, words: string[], filters: GameFilters): string {
  const where = [
    ...words.map(wordStartCondition),
    ...filterConditions(filters),
    'total_rating_count != null',
  ].join(' & ')
  return `fields ${fields}; where ${where}; sort total_rating_count desc; limit ${TITLE_MATCHES};`
}

/**
 * Where page [offset, offset + limit) of the joined list finds its search hits,
 * with [titleCount] title matches ahead of them: the position in the search
 * (which leaves the title matches out) and how many hits the page still needs.
 */
export function searchPagePlan(
  offset: number,
  limit: number,
  titleCount: number,
): { searchOffset: number; searchLimit: number } {
  const titlesOnPage = Math.max(0, Math.min(limit, titleCount - offset))
  return { searchOffset: Math.max(0, offset - titleCount), searchLimit: limit - titlesOnPage }
}

/** The IGDB id of [hit], or null when it has none. */
export function hitId(hit: unknown): number | null {
  const id = (hit as { id?: unknown } | null)?.id
  return typeof id === 'number' && Number.isSafeInteger(id) && id > 0 ? id : null
}

/** The ids of [titleMatches], for the search to leave out. */
export function titleIds(titleMatches: unknown[]): number[] {
  return [...new Set(titleMatches.map(hitId).filter((id): id is number => id !== null))]
}

/**
 * Page [offset, offset + limit) of the joined list: the title matches from
 * [offset] on, then [searchHits] (from the page's position in the search, see
 * [searchPagePlan]) that are not title matches, [limit] in all at most.
 */
export function joinSearchPage(
  titleMatches: unknown[],
  searchHits: unknown[],
  offset: number,
  limit: number,
): unknown[] {
  const page = titleMatches.slice(offset, offset + limit)
  const titles = new Set(titleIds(titleMatches))
  for (const hit of searchHits) {
    if (page.length >= limit) break
    const id = hitId(hit)
    if (id === null || !titles.has(id)) page.push(hit)
  }
  return page
}
