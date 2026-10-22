// supabase/functions/_shared/companies.ts
//
// What igdb-handler's company modes ask IGDB for, and what they send back: one
// company's page (`company`), its games (`company_games`) and the studio search
// and browse (`companies`). IGDB keeps publishers and developers as one thing, a
// company. Pure functions with no I/O, so they can be tested.
//
// Every value spliced into a query is a number, a fixed string, or a word from
// titleWords (letters, digits and apostrophes only), never raw text from the
// caller, so none of these can run arbitrary queries against the IGDB quota.

import { DISCOVER_GAMES, type DiscoverSort, sortClause, startOfYear } from './game_filters.ts'
import { wordStartCondition } from './game_search.ts'

/** Which of a company's games a list holds: all, or those it published / developed. */
export const COMPANY_ROLES = ['any', 'publisher', 'developer'] as const
export type CompanyRole = (typeof COMPANY_ROLES)[number]

/** The role the caller sent: `any` when left out, null when it is none of them. */
export function parseCompanyRole(value: unknown): CompanyRole | null {
  if (value === undefined || value === null) return 'any'
  return typeof value === 'string' && (COMPANY_ROLES as readonly string[]).includes(value)
    ? (value as CompanyRole)
    : null
}

/** What a company's page shows. `developed` / `published` are only counted. */
const COMPANY_FIELDS = [
  'name',
  'description',
  'country',
  'start_date',
  'logo.image_id',
  'parent.name',
  'websites.url',
  'websites.type',
  'developed',
  'published',
].join(', ')

/** One company with everything its page shows. */
export function companyQuery(companyId: number): string {
  return `fields ${COMPANY_FIELDS}; where id = ${companyId}; limit 1;`
}

/** One company of the studio search, as the app gets it. */
export type CompanySummary = {
  id: number
  name: string
  logo_image_id: string | null
  country: number | null
  /** When it was founded, in Unix seconds. */
  start_date: number | null
  published_count: number
  developed_count: number
}

/** A company's page, as the app gets it. */
export type CompanyInfo = CompanySummary & {
  description: string | null
  parent: { id: number; name: string } | null
  websites: { url: string; type: number | null }[]
}

type Row = Record<string, unknown>

const text = (value: unknown): string | null =>
  typeof value === 'string' && value.trim() ? value.trim() : null

const wholeNumber = (value: unknown): number | null =>
  typeof value === 'number' && Number.isSafeInteger(value) ? value : null

const positiveId = (value: unknown): number | null => {
  const id = wholeNumber(value)
  return id !== null && id > 0 ? id : null
}

const count = (value: unknown): number => (Array.isArray(value) ? value.length : 0)

/**
 * [row] as a [CompanySummary], or null when it has no id or name. The
 * `developed` / `published` id lists become counts: a big publisher has
 * thousands, and the app only shows how many.
 */
export function companySummary(row: unknown): CompanySummary | null {
  const r = row as Row | null
  const id = positiveId(r?.id)
  const name = text(r?.name)
  if (!r || id === null || name === null) return null
  const logo = r.logo as Row | null | undefined
  return {
    id,
    name,
    logo_image_id: text(logo?.image_id),
    country: positiveId(r.country),
    start_date: wholeNumber(r.start_date),
    published_count: count(r.published),
    developed_count: count(r.developed),
  }
}

/** [row] (an answer to [companyQuery]) as a [CompanyInfo], or null when it is no company. */
export function companyInfo(row: unknown): CompanyInfo | null {
  const summary = companySummary(row)
  if (!summary) return null
  const r = row as Row
  const parent = r.parent as Row | null | undefined
  const parentId = positiveId(parent?.id)
  const parentName = text(parent?.name)
  const websites: CompanyInfo['websites'] = []
  if (Array.isArray(r.websites)) {
    for (const site of r.websites) {
      const url = text((site as Row | null)?.url)
      if (url) websites.push({ url, type: positiveId((site as Row).type) })
    }
  }
  return {
    ...summary,
    description: text(r.description),
    parent: parentId !== null && parentName !== null ? { id: parentId, name: parentName } : null,
    websites,
  }
}

/** Most companies a studio search by name ranks before it keeps the best. */
export const COMPANY_CANDIDATES = 50

/**
 * Most companies a browse by filters (no name) ranks before it keeps the best.
 * IGDB's most per request, so the well-known studios among the earliest added
 * are all in.
 */
export const BROWSE_CANDIDATES = 500

/**
 * How a studio list is ordered:
 *   popular  most games first, among the earliest-added companies (IGDB can't
 *            sort by how many games a company has, so the candidates are ranked here)
 *   name     A to Z
 *   oldest   founded longest ago first
 *   newest   founded most recently first
 */
export const COMPANY_SORTS = ['popular', 'name', 'oldest', 'newest'] as const
export type CompanySort = (typeof COMPANY_SORTS)[number]

export function isCompanySort(value: unknown): value is CompanySort {
  return typeof value === 'string' && (COMPANY_SORTS as readonly string[]).includes(value)
}

/** Most countries a studio filter may pick: more than any filter sheet offers. */
export const MAX_COMPANY_COUNTRIES = 40

/**
 * Founding years outside this range are refused. Nothing before 1970 is asked
 * for, so no Unix second is ever negative.
 */
export const MIN_FOUNDED_YEAR = 1970
export const MAX_FOUNDED_YEAR = 2100

/**
 * What a studio list is narrowed down by: the role (developer or publisher, any
 * when not narrowed), the countries (ISO 3166-1 numbers; a company needs to be in
 * any of them, none picked: anywhere) and an inclusive range of founding years
 * (null: open).
 */
export type CompanyFilters = {
  role: CompanyRole
  countries: number[]
  founded: { from: number | null; to: number | null }
}

export const NO_COMPANY_FILTERS: CompanyFilters = {
  role: 'any',
  countries: [],
  founded: { from: null, to: null },
}

/**
 * The request's `filters` object as [CompanyFilters], or a message saying what is
 * wrong with it. Missing (or null) means no filters, and so does a missing key.
 */
export function parseCompanyFilters(value: unknown): CompanyFilters | string {
  if (value === undefined || value === null) return NO_COMPANY_FILTERS
  if (typeof value !== 'object' || Array.isArray(value)) return '`filters` must be an object'
  const raw = value as Record<string, unknown>

  const role = parseCompanyRole(raw.role)
  if (role === null) return '`filters.role` must be one of: any, publisher, developer'

  const countries = new Set<number>()
  if (raw.countries !== undefined && raw.countries !== null) {
    const list = raw.countries
    const valid = Array.isArray(list) && list.length <= MAX_COMPANY_COUNTRIES &&
      list.every((c) => typeof c === 'number' && Number.isInteger(c) && c > 0 && c < 1000)
    if (!valid) {
      return `\`filters.countries\` must be a list of up to ${MAX_COMPANY_COUNTRIES} ISO 3166-1 numbers`
    }
    for (const c of list as number[]) countries.add(c)
  }

  let founded: CompanyFilters['founded'] = { from: null, to: null }
  if (raw.founded !== undefined && raw.founded !== null) {
    if (typeof raw.founded !== 'object' || Array.isArray(raw.founded)) {
      return '`filters.founded` must be an object'
    }
    const { from, to } = raw.founded as Record<string, unknown>
    const parsedFrom = parseFoundedYear(from)
    const parsedTo = parseFoundedYear(to)
    if (parsedFrom === undefined || parsedTo === undefined) {
      return `\`filters.founded\` must give whole years from ${MIN_FOUNDED_YEAR} to ${MAX_FOUNDED_YEAR}`
    }
    if (parsedFrom !== null && parsedTo !== null && parsedFrom > parsedTo) {
      return '`filters.founded.from` must not be after `filters.founded.to`'
    }
    founded = { from: parsedFrom, to: parsedTo }
  }
  return { role, countries: [...countries], founded }
}

// A year, null when not given, undefined when malformed.
function parseFoundedYear(value: unknown): number | null | undefined {
  if (value === undefined || value === null) return null
  if (typeof value !== 'number' || !Number.isInteger(value)) return undefined
  if (value < MIN_FOUNDED_YEAR || value > MAX_FOUNDED_YEAR) return undefined
  return value
}

/** Whether [filters] narrow anything down. */
export function hasCompanyFilters(filters: CompanyFilters): boolean {
  return filters.role !== 'any' || filters.countries.length > 0 ||
    filters.founded.from !== null || filters.founded.to !== null
}

/**
 * The `where` conditions of [filters]. A studio always has a game to its name
 * (developed, published, or the one the role asks for); the others only when picked.
 */
export function companyConditions(filters: CompanyFilters): string[] {
  const conditions = [
    filters.role === 'developer'
      ? 'developed != null'
      : filters.role === 'publisher'
      ? 'published != null'
      : '(developed != null | published != null)',
  ]
  if (filters.countries.length > 0) conditions.push(`country = (${filters.countries.join(',')})`)
  const { from, to } = filters.founded
  if (from !== null) conditions.push(`start_date >= ${startOfYear(from)}`)
  // Up to the end of `to`: before 1 January of the year after.
  if (to !== null) conditions.push(`start_date < ${startOfYear(to + 1)}`)
  return conditions
}

/** What the studio lists show of each company; its games are only counted. */
const COMPANY_LIST_FIELDS = 'name, logo.image_id, country, start_date, developed, published'

/**
 * The companies with a word of their name starting with each of [words] (from
 * titleWords, none to browse by [filters] alone) and matching [filters]. IGDB's
 * `search` does not cover companies, so the name is matched the way game titles
 * are.
 *
 * `popular` asks for the earliest-added companies, in id order (IGDB added the
 * well-known studios early, so they make it into the candidates) and leaves the
 * ranking and the paging to [rankCompanies]; every other sort is IGDB's own, paged
 * with [limit] and [offset]. A founding order only lists companies that have a
 * founding date.
 */
export function companiesQuery(
  words: string[],
  filters: CompanyFilters,
  sort: CompanySort,
  limit: number,
  offset: number,
): string {
  const conditions = [...words.map(wordStartCondition), ...companyConditions(filters)]
  if (sort === 'oldest' || sort === 'newest') conditions.push('start_date != null')
  const where = conditions.join(' & ')
  if (sort === 'popular') {
    const candidates = words.length > 0 ? COMPANY_CANDIDATES : BROWSE_CANDIDATES
    return `fields ${COMPANY_LIST_FIELDS}; where ${where}; sort id asc; limit ${candidates};`
  }
  const order = sort === 'name' ? 'name asc' : sort === 'oldest' ? 'start_date asc' : 'start_date desc'
  return `fields ${COMPANY_LIST_FIELDS}; where ${where}; sort ${order}; limit ${limit}; offset ${offset};`
}

const normalized = (name: string) => name.toLowerCase().replace(/\s+/g, ' ').trim()

/** [rows] (an answer to [companiesQuery]) as summaries, in IGDB's order, without what is no company. */
export function listCompanies(rows: unknown): CompanySummary[] {
  if (!Array.isArray(rows)) return []
  return rows.map(companySummary).filter((c): c is CompanySummary => c !== null)
}

/**
 * Page [offset, offset + limit) of [rows] (an answer to [companiesQuery] for the
 * `popular` sort) as ranked for [term]: the company named exactly that first, then
 * those whose name starts with it, then the ones with the most games. With no
 * [term] it is the most games alone.
 */
export function rankCompanies(rows: unknown, term: string, limit: number, offset = 0): CompanySummary[] {
  const wanted = normalized(term)
  const closeness = (name: string) => {
    const n = normalized(name)
    return n === wanted ? 0 : n.startsWith(wanted) ? 1 : 2
  }
  const games = (c: CompanySummary) => c.published_count + c.developed_count
  return listCompanies(rows)
    .sort((a, b) => closeness(a.name) - closeness(b.name) || games(b) - games(a) || a.id - b.id)
    .slice(offset, offset + limit)
}

/**
 * The games [companyId] worked on in [role], in [sort] order, like a filtered
 * browse: main games with a cover. IGDB may match the company and the role on
 * two different involved companies of a game, so the app checks each game's
 * own entry for the company (the involved companies come with [fields]).
 */
export function companyGamesQuery(
  fields: string,
  companyId: number,
  role: CompanyRole,
  sort: DiscoverSort,
  limit: number,
  offset: number,
  nowSeconds: number,
): string {
  const [order, condition] = sortClause(sort, nowSeconds)
  const conditions = [`involved_companies.company = ${companyId}`]
  if (role !== 'any') conditions.push(`involved_companies.${role} = true`)
  conditions.push(condition, DISCOVER_GAMES)
  return `fields ${fields}; where ${conditions.join(' & ')}; sort ${order}; ` +
    `limit ${limit}; offset ${offset};`
}
