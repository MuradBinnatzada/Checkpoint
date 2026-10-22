import { assertEquals } from 'jsr:@std/assert@1'
import { hasTranslations, steamLanguage, type Translatable, withTranslations } from './steam_languages.ts'

type Stored = Translatable & { name: string }

Deno.test('steamLanguage names the languages Steam has, not English', () => {
  assertEquals(steamLanguage('ru'), { lang: 'ru', steam: 'russian' })
  assertEquals(steamLanguage(' KO '), { lang: 'ko', steam: 'koreana' })
  assertEquals(steamLanguage('zh'), { lang: 'zh', steam: 'schinese' })
  assertEquals(steamLanguage('en'), null)
  assertEquals(steamLanguage('russian&key=x'), null)
  assertEquals(steamLanguage(null), null)
})

Deno.test('withTranslations joins on the API name and keeps the others', () => {
  const stored: Stored[] = [
    { api_name: 'ACH_WIN', name: 'Winner', translations: { de: { name: 'Gewinner', description: '' } } },
    { api_name: 'ACH_LOSE', name: 'Loser' },
    { name: 'Old' }, // stored before lists had API names
  ]
  const schema = [
    { name: 'ACH_WIN', displayName: ' Победитель ', description: ' Выиграйте. ' },
    { name: 'ACH_LOSE', displayName: '' }, // Steam has no Russian name for it
  ]
  assertEquals(withTranslations(stored, schema, 'ru'), [
    {
      api_name: 'ACH_WIN',
      name: 'Winner',
      translations: {
        de: { name: 'Gewinner', description: '' },
        ru: { name: 'Победитель', description: 'Выиграйте.' },
      },
    },
    { api_name: 'ACH_LOSE', name: 'Loser' },
    { name: 'Old' },
  ])
})

Deno.test('hasTranslations skips the achievements that cannot have one', () => {
  assertEquals(hasTranslations([{ name: 'Old' } as Stored], 'ru'), true)
  assertEquals(hasTranslations([{ api_name: 'A' }], 'ru'), false)
  assertEquals(hasTranslations([{ api_name: 'A', translations: { ru: { name: 'А', description: '' } } }], 'ru'), true)
})
