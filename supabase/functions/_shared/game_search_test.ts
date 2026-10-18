import { assertEquals } from 'jsr:@std/assert@1'
import { filteredSearchQuery, NO_FILTERS, parseGameFilters, type GameFilters } from './game_filters.ts'
import {
  joinSearchPage,
  MAX_TITLE_WORDS,
  searchPagePlan,
  TITLE_MATCHES,
  titleIds,
  titleMatchQuery,
  titleWords,
  wordStartCondition,
} from './game_search.ts'

const FIELDS = 'name, cover.url'

function filters(value: unknown): GameFilters {
  const parsed = parseGameFilters(value)
  if (typeof parsed === 'string') throw new Error(parsed)
  return parsed
}

const games = (...ids: number[]) => ids.map((id) => ({ id, name: `Game ${id}` }))
const idsOf = (page: unknown[]) => page.map((hit) => (hit as { id: number }).id)

Deno.test('the words of a search are lower case, split at punctuation, without repeats', () => {
  assertEquals(titleWords('Elden  rin'), ['elden', 'rin'])
  assertEquals(titleWords('zelda: breath'), ['zelda', 'breath'])
  assertEquals(titleWords('spider-man'), ['spider', 'man'])
  assertEquals(titleWords('the THE witcher'), ['the', 'witcher'])
  // What the handler escaped for the quoted string is no word.
  assertEquals(titleWords('say \\"hi\\"'), ['say', 'hi'])
  // An apostrophe stays inside its word, and a phone's curly one is made plain.
  assertEquals(titleWords('Marvel’s spider'), ["marvel's", 'spider'])
  assertEquals(titleWords('Pokémon 3'), ['pokémon', '3'])
  assertEquals(titleWords(' !! '), [])
})

Deno.test('a long text gets no title matches', () => {
  const words = Array.from({ length: MAX_TITLE_WORDS }, (_, i) => `w${i}`)
  assertEquals(titleWords(words.join(' ')), words)
  assertEquals(titleWords([...words, 'more'].join(' ')), [])
})

Deno.test('a word matches the start of any word of a title', () => {
  assertEquals(
    wordStartCondition('rin'),
    '(name ~ "rin"* | name ~ *" rin"* | name ~ *"-rin"* | name ~ *"/rin"*)',
  )
})

Deno.test('title matches need every word, any filters, and ratings, most rated first', () => {
  assertEquals(
    titleMatchQuery(FIELDS, ['elden', 'rin'], NO_FILTERS),
    `fields ${FIELDS}; where ${wordStartCondition('elden')} & ${wordStartCondition('rin')}` +
      ` & total_rating_count != null; sort total_rating_count desc; limit ${TITLE_MATCHES};`,
  )
  assertEquals(
    titleMatchQuery(FIELDS, ['zel'], filters({ platforms: [130] })),
    `fields ${FIELDS}; where ${wordStartCondition('zel')} & platforms = (130)` +
      ` & total_rating_count != null; sort total_rating_count desc; limit ${TITLE_MATCHES};`,
  )
})

Deno.test('the search after the title matches leaves them out', () => {
  assertEquals(
    filteredSearchQuery(FIELDS, 'elden rin', filters({ genres: [12] }), 17, 3, [5, 9, 11]),
    `search "elden rin"; fields ${FIELDS}; where genres = (12) & id != (5,9,11); limit 17; offset 3;`,
  )
})

Deno.test('a page is the title matches first, then the search', () => {
  // Three title matches ahead of a page of 5: two search hits fill it.
  assertEquals(searchPagePlan(0, 5, 3), { searchOffset: 0, searchLimit: 2 })
  // The next page is all search, from where the first one stopped.
  assertEquals(searchPagePlan(5, 5, 3), { searchOffset: 2, searchLimit: 5 })
  // More title matches than a page: they fill the first ones alone.
  assertEquals(searchPagePlan(0, 4, 10), { searchOffset: 0, searchLimit: 0 })
  assertEquals(searchPagePlan(8, 4, 10), { searchOffset: 0, searchLimit: 2 })
  assertEquals(searchPagePlan(12, 4, 10), { searchOffset: 2, searchLimit: 4 })
  // No title matches: the plain search, page for page.
  assertEquals(searchPagePlan(40, 20, 0), { searchOffset: 40, searchLimit: 20 })
})

Deno.test('joining a page drops search hits that are title matches, and stops at the limit', () => {
  const titles = games(1, 2)
  // The first page asks for the search as is: it may repeat a title match.
  assertEquals(idsOf(joinSearchPage(titles, games(2, 7, 8, 9), 0, 4)), [1, 2, 7, 8])
  // A later page asked the search without them.
  assertEquals(idsOf(joinSearchPage(titles, games(9, 10), 4, 4)), [9, 10])
  assertEquals(idsOf(joinSearchPage(titles, games(3), 1, 4)), [2, 3])
  // A hit without an id is kept: it is no title match.
  assertEquals(joinSearchPage([], [{ name: 'no id' }], 0, 4), [{ name: 'no id' }])
})

Deno.test('the paged list has every game once, whatever the page size', () => {
  const titles = games(1, 2, 3)
  // IGDB's relevance search, which finds title matches 2 and 3 too.
  const search = games(2, 10, 3, 11, 12, 13, 14)
  const searchWithout = (exclude: number[]) =>
    search.filter((hit) => !exclude.includes(hit.id))

  for (const limit of [1, 2, 3, 4, 5, 20]) {
    const seen: number[] = []
    for (let offset = 0; ; ) {
      let hits: unknown[]
      if (offset === 0) {
        hits = search.slice(0, limit)
      } else {
        const { searchOffset, searchLimit } = searchPagePlan(offset, limit, titles.length)
        hits = searchWithout(titleIds(titles)).slice(searchOffset, searchOffset + searchLimit)
      }
      const page = joinSearchPage(titles, hits, offset, limit)
      seen.push(...idsOf(page))
      offset += page.length
      if (page.length < limit) break
    }
    assertEquals(seen, [1, 2, 3, 10, 11, 12, 13, 14], `pages of ${limit}`)
  }
})
