// supabase/functions/_shared/news.ts
//
// What the game-news function reads and sends: the gaming outlets' public RSS
// feeds (the Latest list) and Steam's news for a game (the My games list), cleaned
// up for the app. Pure functions with no I/O, so they can be tested.
//
// An article is a headline, a short plain-text summary, a link and a picture, with
// the outlet's name: the app shows that and opens the outlet's own page for the
// rest, so nothing here republishes an article. Everything from a feed is
// untrusted text: it is stripped of markup, cut short, and only http(s) links and
// pictures are kept.

import { XMLParser } from 'npm:fast-xml-parser@4.5.0'

export type NewsLanguage = 'en' | 'ru'

/** A gaming outlet whose RSS feed the Latest list is made of. */
export type NewsSource = { id: string; name: string; lang: NewsLanguage; url: string }

/**
 * The outlets, by language. Every feed is plain RSS 2.0 and was checked to answer
 * with dated items and pictures. Left out: PC Gamer (a 5 MB feed), VG247 (its feed
 * stopped updating) and Polygon (its feed is mostly film and TV).
 */
export const NEWS_SOURCES: readonly NewsSource[] = [
  { id: 'ign', name: 'IGN', lang: 'en', url: 'https://feeds.feedburner.com/ign/games-all' },
  { id: 'eurogamer', name: 'Eurogamer', lang: 'en', url: 'https://www.eurogamer.net/feed' },
  { id: 'rps', name: 'Rock Paper Shotgun', lang: 'en', url: 'https://www.rockpapershotgun.com/feed' },
  { id: 'gamespot', name: 'GameSpot', lang: 'en', url: 'https://www.gamespot.com/feeds/news/' },
  { id: 'kotaku', name: 'Kotaku', lang: 'en', url: 'https://kotaku.com/rss' },
  { id: 'gamesradar', name: 'GamesRadar+', lang: 'en', url: 'https://www.gamesradar.com/rss/' },
  { id: 'nintendolife', name: 'Nintendo Life', lang: 'en', url: 'https://www.nintendolife.com/feeds/latest' },
  { id: 'pushsquare', name: 'Push Square', lang: 'en', url: 'https://www.pushsquare.com/feeds/latest' },
  { id: 'stopgame', name: 'StopGame', lang: 'ru', url: 'https://stopgame.ru/rss/rss_news.xml' },
  { id: 'igromania', name: 'Игромания', lang: 'ru', url: 'https://www.igromania.ru/rss/news.xml' },
  { id: 'playground', name: 'Playground.ru', lang: 'ru', url: 'https://www.playground.ru/rss/news.xml' },
  { id: '3dnews', name: '3DNews', lang: 'ru', url: 'https://3dnews.ru/games/rss/' },
]

/** The outlets in [lang]. */
export function sourcesIn(lang: NewsLanguage): NewsSource[] {
  return NEWS_SOURCES.filter((s) => s.lang === lang)
}

/** One article, as the app gets it. */
export type NewsArticle = {
  id: string
  title: string
  /** Plain text, empty when the feed gave none worth showing. */
  summary: string
  url: string
  image_url: string | null
  source_id: string
  source_name: string
  /** Unix seconds. */
  published_at: number
  /** The Steam app the article is about (Steam news only). */
  app_id?: number
}

/** Articles older than this are left out: a feed can keep old items in its list. */
export const MAX_AGE_DAYS = 30

/** Most articles kept of one feed, the newest, so a big feed can't fill the list. */
export const PER_SOURCE_LIMIT = 25

/** Most articles the Latest list has in all. */
export const MAX_ARTICLES = 100

export const MAX_TITLE_LENGTH = 200
export const MAX_SUMMARY_LENGTH = 240

const NAMED_ENTITIES: Record<string, string> = {
  amp: '&',
  lt: '<',
  gt: '>',
  quot: '"',
  apos: "'",
  nbsp: ' ',
  hellip: '…',
  ndash: '–',
  mdash: '—',
  lsquo: '‘',
  rsquo: '’',
  ldquo: '“',
  rdquo: '”',
  laquo: '«',
  raquo: '»',
  copy: '©',
  reg: '®',
  trade: '™',
}

/** [text] with its HTML entities (`&amp;`, `&#8217;`, `&#x27;`) written out; unknown ones stay as they are. */
export function decodeEntities(text: string): string {
  return text.replace(/&(#x[0-9a-f]+|#\d+|[a-z]+);/gi, (whole, body: string) => {
    if (body[0] === '#') {
      const code = body[1].toLowerCase() === 'x' ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10)
      return Number.isSafeInteger(code) && code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : whole
    }
    return NAMED_ENTITIES[body.toLowerCase()] ?? whole
  })
}

/**
 * [html] as one line of plain text: markup dropped, entities written out, white
 * space squeezed, and cut to [maxLength] characters at a word with an ellipsis.
 */
export function plainText(html: string, maxLength: number): string {
  const text = decodeEntities(
    html
      .replace(/<(script|style)[\s\S]*?<\/\1>/gi, ' ')
      // Block tags end a word; inline ones (<a>, <em>) must not split "rumored," from its comma.
      .replace(/<\/?(p|br|div|li|ul|ol|h[1-6]|tr|td|th|table|blockquote|figure|figcaption|img)\b[^>]*>/gi, ' ')
      .replace(/<[^>]*>/g, ''),
  )
    // deno-lint-ignore no-control-regex
    .replace(/[\u0000-\u001f\u007f​-‏‪-‮⁦-⁩]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
  if (text.length <= maxLength) return text
  const cut = text.slice(0, maxLength - 1)
  const space = cut.lastIndexOf(' ')
  return `${(space > maxLength * 0.6 ? cut.slice(0, space) : cut).replace(/[\s.,;:!?-]+$/, '')}…`
}

/** [value] (an RSS date) as Unix seconds, or null when it is not a date. */
export function parseDate(value: unknown): number | null {
  if (typeof value !== 'string' || value.trim() === '') return null
  const ms = Date.parse(value.trim())
  return Number.isFinite(ms) ? Math.floor(ms / 1000) : null
}

/** [value] as an https address (http is upgraded), or null for anything else. */
export function safeUrl(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const text = value.trim()
  if (text.length === 0 || text.length > 2000) return null
  try {
    const url = new URL(text.startsWith('//') ? `https:${text}` : text)
    if (url.protocol === 'http:') url.protocol = 'https:'
    if (url.protocol !== 'https:' || url.username || url.password) return null
    return url.toString()
  } catch {
    return null
  }
}

/** A short stable id of [text] (FNV-1a, 32 bits): for keying articles, not for security. */
export function shortHash(text: string): string {
  let hash = 0x811c9dc5
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i)
    hash = Math.imul(hash, 0x01000193) >>> 0
  }
  return hash.toString(16).padStart(8, '0')
}

const parser = new XMLParser({
  ignoreAttributes: false,
  attributeNamePrefix: '@_',
  textNodeName: '#text',
  parseTagValue: false,
  parseAttributeValue: false,
  trimValues: true,
  isArray: (name) => name === 'item' || name === 'media:content' || name === 'media:thumbnail' || name === 'enclosure',
})

type Node = Record<string, unknown>

/** The text of an XML node: the node itself, or its text under attributes. */
function textOf(node: unknown): string {
  if (typeof node === 'string') return node
  if (typeof node === 'number') return String(node)
  if (node && typeof node === 'object' && !Array.isArray(node)) {
    const text = (node as Node)['#text']
    return typeof text === 'string' ? text : ''
  }
  return ''
}

const IMAGE_EXTENSION = /\.(jpe?g|png|webp|gif|avif)(\?|$)/i

/** The picture of a feed item: its media thumbnail or content, an image enclosure, or the first picture in its text. */
function itemImage(item: Node): string | null {
  const candidates: string[] = []
  const thumbs = item['media:thumbnail']
  if (Array.isArray(thumbs)) for (const t of thumbs) candidates.push(textOf((t as Node)?.['@_url']))
  for (const key of ['media:content', 'enclosure']) {
    const list = item[key]
    if (!Array.isArray(list)) continue
    for (const entry of list) {
      const e = entry as Node
      const url = textOf(e?.['@_url'])
      const type = textOf(e?.['@_type']).toLowerCase()
      const medium = textOf(e?.['@_medium']).toLowerCase()
      if (type.startsWith('image/') || medium === 'image' || (type === '' && IMAGE_EXTENSION.test(url))) {
        candidates.push(url)
      }
    }
  }
  for (const key of ['description', 'content:encoded']) {
    const match = /<img\s[^>]*?src\s*=\s*["']([^"']+)["']/i.exec(textOf(item[key]))
    if (match) candidates.push(decodeEntities(match[1]))
  }
  for (const candidate of candidates) {
    const url = safeUrl(candidate)
    if (url) return url
  }
  return null
}

/**
 * The articles of [xml], the RSS 2.0 feed of [source], newest first: at most
 * [PER_SOURCE_LIMIT] of those from the last MAX_AGE_DAYS days, as of [nowSeconds].
 * An item with no title, no https link or no date is left out; a feed that is not
 * RSS gives none.
 */
export function parseFeed(xml: string, source: NewsSource, nowSeconds: number): NewsArticle[] {
  let items: unknown
  try {
    items = (parser.parse(xml) as Node)?.rss
    items = ((items as Node | undefined)?.channel as Node | undefined)?.item
  } catch {
    return []
  }
  if (!Array.isArray(items)) return []

  const oldest = nowSeconds - MAX_AGE_DAYS * 86400
  const articles: NewsArticle[] = []
  for (const raw of items) {
    const item = raw as Node
    const title = plainText(textOf(item.title), MAX_TITLE_LENGTH)
    const url = safeUrl(textOf(item.link))
    const published = parseDate(textOf(item.pubDate) || textOf(item['dc:date']))
    if (!title || !url || published === null) continue
    // A date in the future is a feed's mistake; a little slack for clocks.
    if (published < oldest || published > nowSeconds + 86400) continue

    const summaryHtml = textOf(item.description) || textOf(item['content:encoded'])
    let summary = plainText(summaryHtml, MAX_SUMMARY_LENGTH)
    // WordPress feeds end with "The post X appeared first on Y."
    summary = summary.replace(/\s*The post .{0,200} appeared first on .{0,100}\.?$/i, '').trim()
    if (summary.length < 20 || summary.toLowerCase() === title.toLowerCase()) summary = ''

    articles.push({
      id: `${source.id}:${shortHash(url)}`,
      title,
      summary,
      url,
      image_url: itemImage(item),
      source_id: source.id,
      source_name: source.name,
      published_at: published,
    })
  }
  return articles.sort((a, b) => b.published_at - a.published_at).slice(0, PER_SOURCE_LIMIT)
}

/**
 * The lists of articles of several feeds as one, newest first, without an article
 * whose link is there already, at most [limit].
 */
export function mergeArticles(lists: NewsArticle[][], limit = MAX_ARTICLES): NewsArticle[] {
  const seen = new Set<string>()
  const merged: NewsArticle[] = []
  for (const article of lists.flat().sort((a, b) => b.published_at - a.published_at || a.id.localeCompare(b.id))) {
    if (seen.has(article.url)) continue
    seen.add(article.url)
    merged.push(article)
  }
  return merged.slice(0, limit)
}

/** Steam's markup in a news text: `[b]`, `[url=...]`, `[img]...[/img]` and the like, and `{STEAM_CLAN_IMAGE}` pictures. */
function withoutSteamMarkup(contents: string): string {
  return contents
    .replace(/\[img[^\]]*\][\s\S]*?\[\/img\]/gi, ' ')
    .replace(/\[\/?[a-z0-9*]+(?:=[^\]]*)?\]/gi, ' ')
    .replace(/\{STEAM_CLAN_IMAGE\}\S*/g, ' ')
    .replace(/https?:\/\/\S+/g, ' ')
}

/**
 * The articles in Steam's `GetNewsForApp` answer [body] for [appId], newest
 * first, from the last MAX_AGE_DAYS days (as of [nowSeconds]): each by the outlet
 * Steam files it under (a developer's announcement, a press piece).
 */
export function steamArticles(appId: number, body: unknown, nowSeconds: number): NewsArticle[] {
  const list = ((body as Node | null)?.appnews as Node | undefined)?.newsitems
  if (!Array.isArray(list)) return []
  const oldest = nowSeconds - MAX_AGE_DAYS * 86400
  const articles: NewsArticle[] = []
  for (const raw of list) {
    const item = raw as Node
    const title = plainText(textOf(item.title), MAX_TITLE_LENGTH)
    const url = safeUrl(item.url)
    const published = typeof item.date === 'number' && Number.isFinite(item.date) ? Math.floor(item.date) : null
    if (!title || !url || published === null) continue
    if (published < oldest || published > nowSeconds + 86400) continue
    const label = plainText(textOf(item.feedlabel), 60)
    const summary = plainText(withoutSteamMarkup(textOf(item.contents)), MAX_SUMMARY_LENGTH)
    articles.push({
      id: `steam:${appId}:${shortHash(String(item.gid ?? url))}`,
      title,
      summary: summary.length < 20 || summary.toLowerCase() === title.toLowerCase() ? '' : summary,
      url,
      image_url: null,
      source_id: 'steam',
      source_name: label || 'Steam',
      published_at: published,
      app_id: appId,
    })
  }
  return articles.sort((a, b) => b.published_at - a.published_at)
}

// ---- Requests ----

export const DEFAULT_LIMIT = 20
export const MAX_LIMIT = 50

/** Most Steam apps one request may name. */
export const MAX_APP_IDS = 10

export type NewsRequest =
  | { mode: 'feed'; lang: NewsLanguage; source: string | null; limit: number; offset: number }
  | { mode: 'steam'; appIds: number[]; limit: number; offset: number }

function clamp(value: unknown, fallback: number, min: number, max: number): number {
  const n = Math.floor(Number(value))
  return Number.isFinite(n) ? Math.min(Math.max(n, min), max) : fallback
}

/** The request body as a [NewsRequest], or a message saying what is wrong with it. */
export function parseNewsRequest(payload: unknown): NewsRequest | string {
  const body = (payload ?? {}) as Node
  const limit = clamp(body.limit, DEFAULT_LIMIT, 1, MAX_LIMIT)
  const offset = clamp(body.offset, 0, 0, MAX_ARTICLES)

  const mode = body.mode ?? 'feed'
  if (mode === 'feed') {
    const lang = body.lang ?? 'en'
    if (lang !== 'en' && lang !== 'ru') return '`lang` must be one of: en, ru'
    const source = body.source ?? null
    if (source !== null && (typeof source !== 'string' || !sourcesIn(lang).some((s) => s.id === source))) {
      return '`source` must be the id of one of the outlets'
    }
    return { mode, lang, source, limit, offset }
  }
  if (mode === 'steam') {
    const ids = body.app_ids
    const valid = Array.isArray(ids) && ids.length >= 1 && ids.length <= MAX_APP_IDS &&
      ids.every((id) => typeof id === 'number' && Number.isSafeInteger(id) && id > 0)
    if (!valid) return `\`app_ids\` must be a list of 1 to ${MAX_APP_IDS} positive whole numbers`
    return { mode, appIds: [...new Set(ids as number[])], limit, offset }
  }
  return '`mode` must be one of: feed, steam'
}
