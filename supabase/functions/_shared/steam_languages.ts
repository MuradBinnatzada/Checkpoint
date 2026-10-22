// supabase/functions/_shared/steam_languages.ts
//
// Steam's own translations of achievements: the app's language as Steam's Web
// API names it (`l=russian`), and the translated names and descriptions joined
// onto a stored achievement list. Pure functions with no I/O, so they can be
// tested.
//
// A stored list (`user_games.achievements`) stays in English, which every
// member shares; each achievement carries Steam's translations under
// `translations`, by language: { "ru": { name, description } }. The app shows
// the one for its language, else the English.

/** The app's language codes Steam has, by the name Steam's Web API takes. */
const STEAM_LANGUAGES: Record<string, string> = {
  ar: 'arabic',
  bg: 'bulgarian',
  cs: 'czech',
  da: 'danish',
  de: 'german',
  el: 'greek',
  es: 'spanish',
  fi: 'finnish',
  fr: 'french',
  hu: 'hungarian',
  id: 'indonesian',
  it: 'italian',
  ja: 'japanese',
  ko: 'koreana',
  nb: 'norwegian',
  nl: 'dutch',
  pl: 'polish',
  pt: 'brazilian',
  ro: 'romanian',
  ru: 'russian',
  sv: 'swedish',
  th: 'thai',
  tr: 'turkish',
  uk: 'ukrainian',
  vi: 'vietnamese',
  zh: 'schinese',
}

/**
 * The language the caller asked for (`lang`, like "ru") and Steam's name of it;
 * null for English, for a language Steam lacks, and for anything that is not a
 * language code.
 */
export function steamLanguage(value: unknown): { lang: string; steam: string } | null {
  if (typeof value !== 'string') return null
  const lang = value.trim().toLowerCase()
  const steam = STEAM_LANGUAGES[lang]
  return steam ? { lang, steam } : null
}

export interface AchievementText {
  name: string
  description: string
}

/** What the join needs of a stored achievement. */
export interface Translatable {
  api_name?: string
  translations?: Record<string, AchievementText>
}

/** What the join needs of Steam's schema in another language. */
export interface TranslatedSchemaEntry {
  name: string // API name
  displayName?: string
  description?: string
}

/**
 * [achievements] with Steam's text in [lang] from [schema] (GetSchemaForGame
 * with `l=`), joined on the API name, next to the translations they already
 * have. One without an API name (stored before they had one), or that Steam
 * has no name for in [lang], is left as it is.
 */
export function withTranslations<T extends Translatable>(
  achievements: T[],
  schema: TranslatedSchemaEntry[],
  lang: string,
): T[] {
  const byApiName = new Map(schema.map((s) => [s.name, s]))
  return achievements.map((a) => {
    const s = a.api_name ? byApiName.get(a.api_name) : undefined
    const name = (s?.displayName ?? '').trim()
    if (!s || !name) return a
    return {
      ...a,
      translations: { ...a.translations, [lang]: { name, description: (s.description ?? '').trim() } },
    }
  })
}

/** Whether every achievement that could have a translation into [lang] has one. */
export function hasTranslations(achievements: Translatable[], lang: string): boolean {
  return achievements.every((a) => !a.api_name || a.translations?.[lang] !== undefined)
}
