import { assertEquals } from 'jsr:@std/assert@1'
import {
  deeplTarget,
  deeplUrl,
  MAX_TEXT_LENGTH,
  parseDeeplResponse,
  sourceHash,
  translatable,
  translateTexts,
  translationLanguage,
  type TranslationStore,
} from './deepl.ts'

Deno.test('translationLanguage takes the languages DeepL has, not English', () => {
  assertEquals(translationLanguage('ru'), 'ru')
  assertEquals(translationLanguage(' RU '), 'ru')
  assertEquals(translationLanguage('en'), null)
  assertEquals(translationLanguage('xx'), null)
  assertEquals(translationLanguage("ru'; drop table"), null)
  assertEquals(translationLanguage(7), null)
  assertEquals(translationLanguage(undefined), null)
  assertEquals(deeplTarget('ru'), 'RU')
  assertEquals(deeplTarget('pt'), 'PT-BR')
})

Deno.test('a free key goes to the free API', () => {
  assertEquals(deeplUrl('abc:fx'), 'https://api-free.deepl.com/v2/translate')
  assertEquals(deeplUrl('abc'), 'https://api.deepl.com/v2/translate')
})

Deno.test('translatable trims and caps the text, and drops an empty one', () => {
  assertEquals(translatable('  A story.  '), 'A story.')
  assertEquals(translatable('   '), null)
  assertEquals(translatable(null), null)
  assertEquals(translatable('x'.repeat(MAX_TEXT_LENGTH + 5))?.length, MAX_TEXT_LENGTH)
})

Deno.test('sourceHash is the SHA-256 of the text', async () => {
  assertEquals(
    await sourceHash('abc'),
    'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
  )
})

Deno.test('parseDeeplResponse wants one translation per text', () => {
  assertEquals(parseDeeplResponse({ translations: [{ text: 'Привет' }] }, 1), ['Привет'])
  assertEquals(parseDeeplResponse({ translations: [{ text: 'a' }] }, 2), null)
  assertEquals(parseDeeplResponse({ translations: [{ text: 3 }] }, 1), null)
  assertEquals(parseDeeplResponse({ message: 'Quota exceeded' }, 1), null)
})

/** A store in memory, which says what it was asked. */
function memoryStore(initial: Record<string, string> = {}) {
  const rows = new Map(Object.entries(initial))
  const saved: unknown[] = []
  const store: TranslationStore = {
    lookup: (hashes, lang) =>
      Promise.resolve(
        new Map(hashes.flatMap((h) => (rows.has(`${h}/${lang}`) ? [[h, rows.get(`${h}/${lang}`)!]] : []))),
      ),
    save: (list) => {
      saved.push(...list)
      for (const r of list) rows.set(`${r.source_hash}/${r.lang}`, r.translation)
      return Promise.resolve()
    },
  }
  return { store, saved }
}

Deno.test('stored translations are used without asking DeepL', async () => {
  const hash = await sourceHash('A story.')
  const { store, saved } = memoryStore({ [`${hash}/ru`]: 'История.' })
  let asked = 0
  const result = await translateTexts(['A story.'], 'ru', {
    key: 'k',
    store,
    fetch: () => {
      asked++
      return Promise.reject(new Error('should not be called'))
    },
  })
  assertEquals(result.get('A story.'), 'История.')
  assertEquals(asked, 0)
  assertEquals(saved, [])
})

Deno.test('the rest is asked of DeepL in one request, then stored', async () => {
  const { store, saved } = memoryStore()
  const bodies: unknown[] = []
  const result = await translateTexts(['One.', 'Two.', 'One.'], 'ru', {
    key: 'secret:fx',
    store,
    fetch: (url, init) => {
      assertEquals(url, 'https://api-free.deepl.com/v2/translate')
      assertEquals((init?.headers as Record<string, string>).Authorization, 'DeepL-Auth-Key secret:fx')
      bodies.push(JSON.parse(String(init?.body)))
      return Promise.resolve(Response.json({ translations: [{ text: 'Один.' }, { text: 'Два.' }] }))
    },
  })
  assertEquals(bodies, [{ text: ['One.', 'Two.'], source_lang: 'EN', target_lang: 'RU', preserve_formatting: true }])
  assertEquals([...result], [['One.', 'Один.'], ['Two.', 'Два.']])
  assertEquals(saved.length, 2)
})

Deno.test('a DeepL failure leaves the texts untranslated, without throwing', async () => {
  const { store, saved } = memoryStore()
  const quota = await translateTexts(['One.'], 'ru', {
    key: 'k',
    store,
    fetch: () => Promise.resolve(new Response('Quota exceeded', { status: 456 })),
  })
  assertEquals(quota.size, 0)
  const offline = await translateTexts(['One.'], 'ru', {
    key: 'k',
    store,
    fetch: () => Promise.reject(new TypeError('network down')),
  })
  assertEquals(offline.size, 0)
  assertEquals(saved, [])
})
