// supabase/functions/_shared/deepl.ts
//
// Machine translation of IGDB's texts (a game's summary and storyline, a
// company's description) into the app's language, with DeepL. Each text is
// translated once per language and kept in `public.text_translations`, keyed by
// the SHA-256 of the English text: every member then gets the stored copy, and
// a text IGDB rewrites is translated again.
//
// Only text the Edge Function fetched from IGDB itself is translated, never text
// the caller sent, so the DeepL quota can't be spent on arbitrary requests.
//
// Secrets: DEEPL_API_KEY. Without it nothing is translated and the app shows
// the English text. A free key (ending in ":fx") goes to DeepL's free API.

/** The app's languages DeepL can translate into, by the code the app sends. */
const DEEPL_TARGETS: Record<string, string> = {
  ar: 'AR',
  bg: 'BG',
  cs: 'CS',
  da: 'DA',
  de: 'DE',
  el: 'EL',
  es: 'ES',
  et: 'ET',
  fi: 'FI',
  fr: 'FR',
  hu: 'HU',
  id: 'ID',
  it: 'IT',
  ja: 'JA',
  ko: 'KO',
  lt: 'LT',
  lv: 'LV',
  nb: 'NB',
  nl: 'NL',
  pl: 'PL',
  pt: 'PT-BR',
  ro: 'RO',
  ru: 'RU',
  sk: 'SK',
  sl: 'SL',
  sv: 'SV',
  tr: 'TR',
  uk: 'UK',
  zh: 'ZH-HANS',
}

/** Longer texts are cut here first: a storyline can run to pages. */
export const MAX_TEXT_LENGTH = 6000

/** How long the screen waits for DeepL before it shows the English text. */
const DEEPL_TIMEOUT_MS = 5000

/**
 * The language the caller asked for (`lang`, like "ru"), when the app's texts
 * should be translated into it: null for English, for anything DeepL can't
 * translate into, and for anything that is not a language code.
 */
export function translationLanguage(value: unknown): string | null {
  if (typeof value !== 'string') return null
  const lang = value.trim().toLowerCase()
  return lang in DEEPL_TARGETS ? lang : null
}

/** DeepL's code for [lang] (one translationLanguage accepted). */
export function deeplTarget(lang: string): string {
  return DEEPL_TARGETS[lang]
}

/** The API a key belongs to: free keys end in ":fx". */
export function deeplUrl(key: string): string {
  return key.endsWith(':fx') ? 'https://api-free.deepl.com/v2/translate' : 'https://api.deepl.com/v2/translate'
}

/** The text as it is translated and stored: trimmed, at most MAX_TEXT_LENGTH. */
export function translatable(text: unknown): string | null {
  if (typeof text !== 'string') return null
  const trimmed = text.trim()
  return trimmed ? trimmed.slice(0, MAX_TEXT_LENGTH) : null
}

/** The SHA-256 of [text], hex: the key of its translations. */
export async function sourceHash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text))
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('')
}

/** The translations in DeepL's answer, in the order the texts were sent; null when it is not one. */
export function parseDeeplResponse(body: unknown, count: number): string[] | null {
  const list = (body as { translations?: unknown } | null)?.translations
  if (!Array.isArray(list) || list.length !== count) return null
  const texts = list.map((t) => (t as { text?: unknown } | null)?.text)
  return texts.every((t) => typeof t === 'string') ? (texts as string[]) : null
}

/** Where translations are kept: `text_translations`, or a stand-in in tests. */
export interface TranslationStore {
  /** The stored translations into [lang] of the texts with these hashes. */
  lookup(hashes: string[], lang: string): Promise<Map<string, string>>
  save(rows: { source_hash: string; lang: string; translation: string }[]): Promise<void>
}

/**
 * [texts] translated into [lang], by English text: the stored ones, and the rest
 * from DeepL in one request (then stored). Never throws: a text that could not be
 * translated is left out, and the app shows it in English.
 */
export async function translateTexts(
  texts: string[],
  lang: string,
  options: { key: string; store: TranslationStore; fetch?: typeof fetch },
): Promise<Map<string, string>> {
  const result = new Map<string, string>()
  const unique = [...new Set(texts)]
  if (unique.length === 0) return result
  try {
    const hashes = await Promise.all(unique.map(sourceHash))
    const stored = await options.store.lookup(hashes, lang).catch((err) => {
      console.error('stored translations unavailable:', err)
      return new Map<string, string>()
    })
    const missing: { text: string; hash: string }[] = []
    unique.forEach((text, i) => {
      const translation = stored.get(hashes[i])
      if (translation !== undefined) result.set(text, translation)
      else missing.push({ text, hash: hashes[i] })
    })
    if (missing.length === 0) return result

    const res = await (options.fetch ?? fetch)(deeplUrl(options.key), {
      method: 'POST',
      headers: { 'Authorization': `DeepL-Auth-Key ${options.key}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        text: missing.map((m) => m.text),
        source_lang: 'EN',
        target_lang: deeplTarget(lang),
        // IGDB's texts are prose with paragraphs: keep the line breaks.
        preserve_formatting: true,
      }),
      signal: AbortSignal.timeout(DEEPL_TIMEOUT_MS),
    })
    if (!res.ok) {
      // 456: the month's quota is used up. Either way the English text shows.
      console.error(`DeepL answered ${res.status}`)
      return result
    }
    const translated = parseDeeplResponse(await res.json().catch(() => null), missing.length)
    if (!translated) {
      console.error('DeepL sent an unexpected answer')
      return result
    }
    missing.forEach((m, i) => result.set(m.text, translated[i]))
    await options.store
      .save(missing.map((m, i) => ({ source_hash: m.hash, lang, translation: translated[i] })))
      .catch((err) => console.error('could not store the translations:', err))
  } catch (err) {
    console.error('translation failed:', err)
  }
  return result
}
