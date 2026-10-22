import { assertEquals } from 'jsr:@std/assert@1'
import {
  BROWSE_CANDIDATES,
  COMPANY_CANDIDATES,
  companiesQuery,
  companyConditions,
  companyGamesQuery,
  companyInfo,
  companyQuery,
  companySummary,
  hasCompanyFilters,
  isCompanySort,
  listCompanies,
  NO_COMPANY_FILTERS,
  parseCompanyFilters,
  parseCompanyRole,
  rankCompanies,
} from './companies.ts'
import { titleWords } from './game_search.ts'

const NOW = 1_700_000_000

Deno.test('a role is any, publisher or developer, any when left out', () => {
  assertEquals(parseCompanyRole(undefined), 'any')
  assertEquals(parseCompanyRole(null), 'any')
  assertEquals(parseCompanyRole('publisher'), 'publisher')
  assertEquals(parseCompanyRole('developer'), 'developer')
  assertEquals(parseCompanyRole('porter'), null)
  assertEquals(parseCompanyRole(1), null)
})

Deno.test('one company is asked for by its id', () => {
  const query = companyQuery(56)
  assertEquals(query.endsWith('where id = 56; limit 1;'), true)
  assertEquals(query.includes('logo.image_id'), true)
  assertEquals(query.includes('parent.name'), true)
})

Deno.test("a company's game lists become counts", () => {
  const info = companyInfo({
    id: 56,
    name: ' Valve ',
    description: 'Makers of Half-Life.',
    country: 840,
    start_date: 830_000_000,
    logo: { id: 1, image_id: 'cl1' },
    parent: { id: 9, name: 'Parent Co' },
    websites: [{ id: 1, url: 'https://valvesoftware.com', type: 1 }, { id: 2 }, { url: 'https://x.com/valve' }],
    developed: [1, 2, 3],
    published: [1, 2],
  })
  assertEquals(info, {
    id: 56,
    name: 'Valve',
    logo_image_id: 'cl1',
    country: 840,
    start_date: 830_000_000,
    published_count: 2,
    developed_count: 3,
    description: 'Makers of Half-Life.',
    parent: { id: 9, name: 'Parent Co' },
    websites: [
      { url: 'https://valvesoftware.com', type: 1 },
      { url: 'https://x.com/valve', type: null },
    ],
  })
})

Deno.test('a sparse company gives a sparse page, and no id or name is no company', () => {
  assertEquals(companyInfo({ id: 7, name: 'Tiny' }), {
    id: 7,
    name: 'Tiny',
    logo_image_id: null,
    country: null,
    published_count: 0,
    developed_count: 0,
    description: null,
    start_date: null,
    parent: null,
    websites: [],
  })
  assertEquals(companyInfo({ id: 7 }), null)
  assertEquals(companyInfo({ name: 'No id' }), null)
  assertEquals(companyInfo(null), null)
  assertEquals(companySummary('nope'), null)
})

Deno.test('a studio sort is popular, name, oldest or newest', () => {
  for (const sort of ['popular', 'name', 'oldest', 'newest']) assertEquals(isCompanySort(sort), true)
  assertEquals(isCompanySort('top_rated'), false)
  assertEquals(isCompanySort(undefined), false)
})

Deno.test('no studio filters is nothing picked, and so is a missing key', () => {
  assertEquals(parseCompanyFilters(undefined), NO_COMPANY_FILTERS)
  assertEquals(parseCompanyFilters(null), NO_COMPANY_FILTERS)
  assertEquals(parseCompanyFilters({}), NO_COMPANY_FILTERS)
  assertEquals(hasCompanyFilters(NO_COMPANY_FILTERS), false)
})

Deno.test('studio filters are a role, countries and a range of founding years', () => {
  const filters = parseCompanyFilters({
    role: 'developer',
    countries: [840, 392, 840],
    founded: { from: 1990, to: 1999 },
  })
  assertEquals(filters, {
    role: 'developer',
    countries: [840, 392],
    founded: { from: 1990, to: 1999 },
  })
  assertEquals(hasCompanyFilters(filters as typeof NO_COMPANY_FILTERS), true)
  // One end open.
  assertEquals(parseCompanyFilters({ founded: { from: 2010 } }), {
    ...NO_COMPANY_FILTERS,
    founded: { from: 2010, to: null },
  })
})

Deno.test('malformed studio filters are refused with what is wrong', () => {
  const refused = (value: unknown) => typeof parseCompanyFilters(value) === 'string'
  assertEquals(refused('japan'), true)
  assertEquals(refused([]), true)
  assertEquals(refused({ role: 'porter' }), true)
  assertEquals(refused({ countries: 'US' }), true)
  assertEquals(refused({ countries: [0] }), true)
  assertEquals(refused({ countries: [1000] }), true)
  assertEquals(refused({ countries: [840.5] }), true)
  assertEquals(refused({ countries: Array.from({ length: 41 }, (_, i) => i + 1) }), true)
  assertEquals(refused({ founded: 1990 }), true)
  assertEquals(refused({ founded: { from: 1969 } }), true)
  assertEquals(refused({ founded: { to: 2101 } }), true)
  assertEquals(refused({ founded: { from: 1999.5 } }), true)
  assertEquals(refused({ founded: { from: 2000, to: 1990 } }), true)
})

Deno.test('a studio always has a game, and each filter picked narrows it down', () => {
  assertEquals(companyConditions(NO_COMPANY_FILTERS), ['(developed != null | published != null)'])
  assertEquals(
    companyConditions({
      role: 'publisher',
      countries: [840, 392],
      founded: { from: 1990, to: 1999 },
    }),
    [
      'published != null',
      'country = (840,392)',
      `start_date >= ${Date.UTC(1990, 0, 1) / 1000}`,
      `start_date < ${Date.UTC(2000, 0, 1) / 1000}`,
    ],
  )
  assertEquals(companyConditions({ ...NO_COMPANY_FILTERS, role: 'developer' })[0], 'developed != null')
})

Deno.test('the studio search matches the start of name words, among companies with games', () => {
  const query = companiesQuery(titleWords('ubi mont'), NO_COMPANY_FILTERS, 'popular', 20, 0)
  assertEquals(query.includes('(name ~ "ubi"* | name ~ *" ubi"*'), true)
  assertEquals(query.includes('(name ~ "mont"* | name ~ *" mont"*'), true)
  assertEquals(query.includes('(developed != null | published != null)'), true)
  assertEquals(query.endsWith(`sort id asc; limit ${COMPANY_CANDIDATES};`), true)
})

Deno.test('browsing by filters alone ranks a wide window of the earliest companies', () => {
  const query = companiesQuery([], { ...NO_COMPANY_FILTERS, countries: [392] }, 'popular', 20, 40)
  assertEquals(
    query,
    'fields name, logo.image_id, country, start_date, developed, published; ' +
      'where (developed != null | published != null) & country = (392); ' +
      `sort id asc; limit ${BROWSE_CANDIDATES};`,
  )
})

Deno.test("the other sorts are IGDB's own, paged by limit and offset", () => {
  const filters = { ...NO_COMPANY_FILTERS, countries: [752] }
  const byName = companiesQuery([], filters, 'name', 20, 40)
  assertEquals(byName.endsWith('sort name asc; limit 20; offset 40;'), true)
  assertEquals(byName.includes('start_date != null'), false)

  const oldest = companiesQuery([], filters, 'oldest', 20, 0)
  assertEquals(oldest.endsWith('sort start_date asc; limit 20; offset 0;'), true)
  assertEquals(oldest.includes('start_date != null'), true)

  const newest = companiesQuery(titleWords('studio'), filters, 'newest', 10, 10)
  assertEquals(newest.endsWith('sort start_date desc; limit 10; offset 10;'), true)
  assertEquals(newest.includes('(name ~ "studio"*'), true)
})

Deno.test('the exact name ranks first, then names starting with it, then most games', () => {
  const rows = [
    { id: 3, name: 'Studio Valve Fans', published: [1, 2, 3, 4, 5] },
    { id: 4, name: 'Valve South', developed: [1] },
    { id: 5, name: 'Valve Classics', developed: [1, 2] },
    { id: 56, name: 'Valve', published: [1], developed: [1] },
    { id: 6 }, // no name: left out
  ]
  assertEquals(rankCompanies(rows, ' valve ', 10).map((c) => c.id), [56, 5, 4, 3])
  assertEquals(rankCompanies(rows, 'valve', 2).map((c) => c.id), [56, 5])
  assertEquals(rankCompanies('nope', 'valve', 10), [])
})

Deno.test('with no name the most games come first, and a page is a slice of the ranking', () => {
  const rows = [
    { id: 1, name: 'A', developed: [1] },
    { id: 2, name: 'B', developed: [1, 2, 3] },
    { id: 3, name: 'C', published: [1, 2] },
    { id: 4, name: 'D', published: [1, 2] },
  ]
  assertEquals(rankCompanies(rows, '', 10).map((c) => c.id), [2, 3, 4, 1])
  assertEquals(rankCompanies(rows, '', 2, 0).map((c) => c.id), [2, 3])
  assertEquals(rankCompanies(rows, '', 2, 2).map((c) => c.id), [4, 1])
  assertEquals(rankCompanies(rows, '', 2, 4), [])
})

Deno.test("a list in IGDB's order drops what is no company", () => {
  assertEquals(
    listCompanies([{ id: 9, name: 'Zed', start_date: -2_840_140_800 }, { name: 'No id' }, { id: 2, name: 'Amy' }])
      .map((c) => [c.id, c.start_date]),
    [[9, -2_840_140_800], [2, null]],
  )
  assertEquals(listCompanies(undefined), [])
})

Deno.test("a company's games are its main games with a cover, in the sort's order", () => {
  assertEquals(
    companyGamesQuery('name', 56, 'any', 'popular', 30, 60, NOW),
    'fields name; where involved_companies.company = 56 & total_rating_count != null & ' +
      'cover != null & parent_game = null & version_parent = null; ' +
      'sort total_rating_count desc; limit 30; offset 60;',
  )
  const published = companyGamesQuery('name', 56, 'publisher', 'newest', 30, 0, NOW)
  assertEquals(published.includes('involved_companies.company = 56 & involved_companies.publisher = true'), true)
  assertEquals(published.includes(`first_release_date <= ${NOW}`), true)
  assertEquals(published.includes('sort first_release_date desc'), true)
  assertEquals(
    companyGamesQuery('name', 56, 'developer', 'oldest', 30, 0, NOW).includes('involved_companies.developer = true'),
    true,
  )
})
