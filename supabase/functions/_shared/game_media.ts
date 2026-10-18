// supabase/functions/_shared/game_media.ts
//
// What igdb-handler's `media` mode asks IGDB for, and what it answers: the art a
// member can pick for a game's backdrop (its artworks and screenshots, as on the
// game's IGDB page). Pure functions with no I/O, so they can be tested.
//
// Every value spliced into a query is a number, never text from the caller.

/** One game's artworks and screenshots. */
export function mediaQuery(igdbId: number): string {
  const image = (field: string) => `${field}.image_id, ${field}.width, ${field}.height`
  return `fields ${image('artworks')}, ${image('screenshots')}; where id = ${igdbId}; limit 1;`
}

/** One picture: IGDB's image id (the app builds the URL in the size it needs). */
export type MediaImage = {
  image_id: string
  width: number | null
  height: number | null
}

export type GameMedia = {
  artworks: MediaImage[]
  screenshots: MediaImage[]
}

/** Most artworks and most screenshots answered. */
export const MAX_IMAGES = 40

// IGDB image ids are short and alphanumeric ("ar5l8"). Anything else is dropped,
// so the app can splice an id into a URL as it is.
const IMAGE_ID_RE = /^[A-Za-z0-9]{1,32}$/

const dimension = (v: unknown): number | null =>
  typeof v === 'number' && Number.isFinite(v) && v > 0 ? Math.round(v) : null

/** The images of [list], once each, at most [MAX_IMAGES]. */
function images(list: unknown): MediaImage[] {
  if (!Array.isArray(list)) return []
  const out: MediaImage[] = []
  const seen = new Set<string>()
  for (const entry of list) {
    const v = entry as { image_id?: unknown; width?: unknown; height?: unknown } | null
    if (typeof v?.image_id !== 'string' || !IMAGE_ID_RE.test(v.image_id) || seen.has(v.image_id)) continue
    seen.add(v.image_id)
    out.push({ image_id: v.image_id, width: dimension(v.width), height: dimension(v.height) })
    if (out.length >= MAX_IMAGES) break
  }
  return out
}

/** The media of [game], an answer row of [mediaQuery]. */
export function gameMedia(game: Record<string, unknown>): GameMedia {
  return { artworks: images(game.artworks), screenshots: images(game.screenshots) }
}
