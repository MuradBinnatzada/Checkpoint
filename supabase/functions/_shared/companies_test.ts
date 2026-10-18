import { assertEquals } from 'jsr:@std/assert@1'
import {
  COMPANY_CANDIDATES,
  companyGamesQuery,
  companyInfo,
  companyQuery,
  companySearchQuery,
  companySummary,
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
    published_count: 2,
    developed_count: 3,
    description: 'Makers of Half-Life.',
    start_date: 830_000_000,
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

Deno.test('the studio search matches the start of name words, among companies with games', () => {
  const query = companySearchQuery(titleWords('ubi mont'))
  assertEquals(query.includes('(name ~ "ubi"* | name ~ *" ubi"*'), true)
  assertEquals(query.includes('(name ~ "mont"* | name ~ *" mont"*'), true)
  assertEquals(query.includes('(developed != null | published != null)'), true)
  assertEquals(query.endsWith(`sort id asc; limit ${COMPANY_CANDIDATES};`), true)
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
