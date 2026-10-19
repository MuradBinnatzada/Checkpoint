import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1'
import { ADD_FIELDS, addQuery, coverUrl, igdbGameUuid, newCatalogRow } from './catalog_add.ts'

const NOW_ISO = '2026-10-19T12:00:00.000Z'

// Hades as IGDB answers for it (trimmed).
const hades = {
  id: 113112,
  name: 'Hades',
  summary: 'Defy the god of the dead.',
  cover: { url: '//images.igdb.com/igdb/image/upload/t_thumb/co39vc.jpg' },
  first_release_date: 1600300800, // 2020-09-17
  platforms: [{ id: 6 }, { id: 130 }],
  genres: [{ name: 'Role-playing (RPG)' }, { name: 'Indie' }],
  involved_companies: [
    { developer: true, publisher: true, company: { name: 'Supergiant Games' } },
  ],
}

Deno.test('the query asks for the ids and the fields of a whole row', () => {
  const query = addQuery([113112, 1942])
  assertStringIncludes(query, 'where id = (113112,1942);')
  assertStringIncludes(query, 'limit 2;')
  for (const field of ['name', 'cover.url', 'summary', 'first_release_date', 'involved_companies.company.name']) {
    assertStringIncludes(ADD_FIELDS, field)
  }
})

Deno.test('a game becomes a full catalog row, all from IGDB', () => {
  const row = newCatalogRow(113112, hades, NOW_ISO, 'u1')!
  assertEquals(row.id, '00000000-0000-4000-8000-000000113112')
  assertEquals(row.igdb_id, 113112)
  assertEquals(row.title, 'Hades')
  assertEquals(row.summary, 'Defy the god of the dead.')
  assertEquals(row.cover_url, 'https://images.igdb.com/igdb/image/upload/t_cover_big/co39vc.jpg')
  assertEquals(row.release_year, 2020)
  assertEquals(row.release_date, '2020-09-17')
  assertEquals(row.genres, ['Role-playing (RPG)', 'Indie'])
  assertEquals(row.developer, 'Supergiant Games')
  assertEquals(row.igdb_synced_at, NOW_ISO)
  assertEquals(row.created_by, 'u1')
})

Deno.test('an id IGDB has no game for makes no row', () => {
  assertEquals(newCatalogRow(5, {}, NOW_ISO, 'u1'), null)
  assertEquals(newCatalogRow(5, { name: '   ' }, NOW_ISO, 'u1'), null)
})

Deno.test('long text is cut to what the table holds, by code points', () => {
  const row = newCatalogRow(1, { name: '🎮'.repeat(400), summary: 'x'.repeat(20000) }, NOW_ISO, null)!
  assertEquals(Array.from(row.title as string).length, 300)
  assertEquals((row.summary as string).length, 10000)
  assertEquals(row.cover_url, null)
  assertEquals(row.release_year, null)
})

Deno.test('only covers on IGDB image host are kept', () => {
  assertEquals(coverUrl({ url: 'https://images.igdb.com/igdb/image/upload/t_thumb/abc.png' }),
    'https://images.igdb.com/igdb/image/upload/t_cover_big/abc.png')
  assertEquals(coverUrl({ url: '//evil.example/igdb/image/upload/t_thumb/abc.png' }), null)
  assertEquals(coverUrl({ url: 'https://images.igdb.com/x"y.png' }), null)
  assertEquals(coverUrl(null), null)
})

Deno.test('the id matches the database and the app', () => {
  assertEquals(igdbGameUuid(1942), '00000000-0000-4000-8000-000000001942')
})
