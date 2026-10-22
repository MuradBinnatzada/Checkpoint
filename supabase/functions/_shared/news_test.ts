import { assertEquals } from 'jsr:@std/assert@1'
import {
  decodeEntities,
  MAX_AGE_DAYS,
  MAX_ARTICLES,
  mergeArticles,
  type NewsArticle,
  NEWS_SOURCES,
  parseDate,
  parseFeed,
  parseNewsRequest,
  PER_SOURCE_LIMIT,
  plainText,
  safeUrl,
  shortHash,
  sourcesIn,
  steamArticles,
} from './news.ts'

const NOW = Date.UTC(2026, 9, 22, 18, 0, 0) / 1000
const IGN = NEWS_SOURCES.find((s) => s.id === 'ign')!
const STOPGAME = NEWS_SOURCES.find((s) => s.id === 'stopgame')!

const rss = (items: string) =>
  `<?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:media="http://search.yahoo.com/mrss/" ` +
  `xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/">` +
  `<channel><title>Feed</title>${items}</channel></rss>`

Deno.test('every outlet has a unique id and an https feed, in English or Russian', () => {
  const ids = NEWS_SOURCES.map((s) => s.id)
  assertEquals(new Set(ids).size, ids.length)
  for (const s of NEWS_SOURCES) assertEquals(s.url.startsWith('https://'), true, s.id)
  assertEquals(sourcesIn('en').length > 3, true)
  assertEquals(sourcesIn('ru').length > 1, true)
  assertEquals(sourcesIn('en').concat(sourcesIn('ru')).length, NEWS_SOURCES.length)
})

Deno.test('entities are written out, and unknown ones are left alone', () => {
  assertEquals(decodeEntities('Battlefield 1&#8217;s &amp; &quot;more&quot; &#x27;x&#x27;'), "Battlefield 1’s & \"more\" 'x'")
  assertEquals(decodeEntities('a&nbsp;b &hellip; &madeup; &#0; &#99999999;'), 'a b … &madeup; &#0; &#99999999;')
})

Deno.test('plain text drops markup, squeezes space and cuts at a word', () => {
  assertEquals(plainText('<p>Hello <b>big</b>\n\n   world</p><script>alert(1)</script>', 100), 'Hello big world')
  // An inline tag does not split a word from its punctuation; a block tag does split words.
  assertEquals(plainText('As <a href="x">rumored</a>, it is so.<br/>Next<p>line</p>', 100), 'As rumored, it is so. Next line')
  assertEquals(plainText('&lt;b&gt; is not markup', 100), '<b> is not markup')
  const cut = plainText('one two three four five six seven eight nine ten', 30)
  assertEquals(cut, 'one two three four five six…')
  assertEquals(cut.length <= 30, true)
  // No space to cut at: cut in the middle of the word.
  assertEquals(plainText('x'.repeat(50), 10), `${'x'.repeat(9)}…`)
  // Control and direction-override characters are gone.
  assertEquals(plainText('a\u0000b‮c', 100), 'a b c')
})

Deno.test('dates are RFC 822 or ISO, and nothing else is a date', () => {
  assertEquals(parseDate('Thu, 22 Oct 2026 14:11:15 +0000'), Date.UTC(2026, 9, 22, 14, 11, 15) / 1000)
  assertEquals(parseDate('Thu, 22 Oct 2026 17:48:20 +0300'), Date.UTC(2026, 9, 22, 14, 48, 20) / 1000)
  assertEquals(parseDate('2026-10-22T14:11:15Z'), Date.UTC(2026, 9, 22, 14, 11, 15) / 1000)
  assertEquals(parseDate('yesterday'), null)
  assertEquals(parseDate(''), null)
  assertEquals(parseDate(12), null)
})

Deno.test('only https addresses are kept, and http is upgraded', () => {
  assertEquals(safeUrl('https://www.ign.com/articles/a'), 'https://www.ign.com/articles/a')
  assertEquals(safeUrl('http://www.ign.com/a'), 'https://www.ign.com/a')
  assertEquals(safeUrl('//images.example.com/a.jpg'), 'https://images.example.com/a.jpg')
  assertEquals(safeUrl('javascript:alert(1)'), null)
  assertEquals(safeUrl('steam://openurl/https://x.com'), null)
  assertEquals(safeUrl('https://user:pass@example.com/'), null)
  assertEquals(safeUrl('not a url'), null)
  assertEquals(safeUrl(undefined), null)
  assertEquals(safeUrl(`https://example.com/${'a'.repeat(2000)}`), null)
})

Deno.test('a short hash is stable and tells addresses apart', () => {
  assertEquals(shortHash('https://a.com/1'), shortHash('https://a.com/1'))
  assertEquals(shortHash('https://a.com/1') === shortHash('https://a.com/2'), false)
  assertEquals(shortHash('').length, 8)
})

Deno.test("an RSS item becomes an article: title, summary, link, picture, outlet and date", () => {
  const xml = rss(`
    <item>
      <title>Skate Studio Also Hit With Cuts &amp; More</title>
      <link>https://www.ign.com/articles/skate-studio-hit-with-layoffs</link>
      <description>Following the announcement that EA is closing down BioWare, staff at the studio behind Skate have also been laid off.</description>
      <pubDate>Thu, 22 Oct 2026 14:11:15 +0000</pubDate>
      <media:content url="https://assets-prd.ignimgs.com/a.jpg" type="image/jpeg" height="900"/>
      <media:thumbnail url="https://assets-prd.ignimgs.com/thumb.jpg"/>
    </item>`)
  const [article] = parseFeed(xml, IGN, NOW)
  assertEquals(article, {
    id: `ign:${shortHash('https://www.ign.com/articles/skate-studio-hit-with-layoffs')}`,
    title: 'Skate Studio Also Hit With Cuts & More',
    summary: 'Following the announcement that EA is closing down BioWare, staff at the studio behind Skate have also been laid off.',
    url: 'https://www.ign.com/articles/skate-studio-hit-with-layoffs',
    image_url: 'https://assets-prd.ignimgs.com/thumb.jpg',
    source_id: 'ign',
    source_name: 'IGN',
    published_at: Date.UTC(2026, 9, 22, 14, 11, 15) / 1000,
  })
})

Deno.test('the picture comes from an image enclosure, an inline image, or nothing', () => {
  const xml = rss(`
    <item><title>Enclosure</title><link>https://s.ru/1</link><pubDate>Thu, 22 Oct 2026 17:48:20 +0300</pubDate>
      <description>x</description><enclosure url="https://images.stopgame.ru/a.jpg" length="1" type="image/jpg"/></item>
    <item><title>Audio</title><link>https://s.ru/2</link><pubDate>Thu, 22 Oct 2026 17:48:20 +0300</pubDate>
      <enclosure url="https://s.ru/a.mp3" length="1" type="audio/mpeg"/></item>
    <item><title>Inline</title><link>https://s.ru/3</link><pubDate>Thu, 22 Oct 2026 17:48:20 +0300</pubDate>
      <description><![CDATA[<img src="https://assetsio.gnwcdn.com/a.jpg?width=690&amp;quality=85" /><p>Text of the article goes on for a while.</p>]]></description></item>
    <item><title>Plain</title><link>https://s.ru/4</link><pubDate>Thu, 22 Oct 2026 17:48:20 +0300</pubDate></item>
    <item><title>Not https</title><link>https://s.ru/5</link><pubDate>Thu, 22 Oct 2026 17:48:20 +0300</pubDate>
      <enclosure url="javascript:alert(1)" length="1" type="image/png"/></item>`)
  const byTitle = Object.fromEntries(parseFeed(xml, STOPGAME, NOW).map((a) => [a.title, a.image_url]))
  assertEquals(byTitle, {
    Enclosure: 'https://images.stopgame.ru/a.jpg',
    Audio: null,
    Inline: 'https://assetsio.gnwcdn.com/a.jpg?width=690&quality=85',
    Plain: null,
    'Not https': null,
  })
})

Deno.test('markup, boilerplate and echoes of the title are not a summary', () => {
  const xml = rss(`
    <item><title>Markup</title><link>https://a.com/1</link><pubDate>Thu, 22 Oct 2026 14:00:00 +0000</pubDate>
      <description><![CDATA[<p><strong>Give it a go.</strong> Regular readers will <em>know</em> I&#8217;m obsessed. <a href="x">link</a></p>]]></description></item>
    <item><title>WordPress</title><link>https://a.com/2</link><pubDate>Thu, 22 Oct 2026 14:00:00 +0000</pubDate>
      <description>A long enough summary of the story. The post WordPress appeared first on Some Site.</description></item>
    <item><title>Same as title here</title><link>https://a.com/3</link><pubDate>Thu, 22 Oct 2026 14:00:00 +0000</pubDate>
      <description>Same as title here</description></item>
    <item><title>Too short</title><link>https://a.com/4</link><pubDate>Thu, 22 Oct 2026 14:00:00 +0000</pubDate>
      <description>Short.</description></item>`)
  const byTitle = Object.fromEntries(parseFeed(xml, IGN, NOW).map((a) => [a.title, a.summary]))
  assertEquals(byTitle, {
    Markup: 'Give it a go. Regular readers will know I’m obsessed. link',
    WordPress: 'A long enough summary of the story.',
    'Same as title here': '',
    'Too short': '',
  })
})

Deno.test('items without a title, an https link or a date are left out, and so are old and future ones', () => {
  const day = 86400
  const at = (seconds: number) => new Date(seconds * 1000).toUTCString()
  const xml = rss(`
    <item><link>https://a.com/1</link><pubDate>${at(NOW)}</pubDate></item>
    <item><title>No link</title><pubDate>${at(NOW)}</pubDate></item>
    <item><title>Bad link</title><link>ftp://a.com/1</link><pubDate>${at(NOW)}</pubDate></item>
    <item><title>No date</title><link>https://a.com/2</link></item>
    <item><title>Not a date</title><link>https://a.com/3</link><pubDate>soon</pubDate></item>
    <item><title>Too old</title><link>https://a.com/4</link><pubDate>${at(NOW - (MAX_AGE_DAYS + 1) * day)}</pubDate></item>
    <item><title>From the future</title><link>https://a.com/5</link><pubDate>${at(NOW + 3 * day)}</pubDate></item>
    <item><title>Fine</title><link>https://a.com/6</link><pubDate>${at(NOW - day)}</pubDate></item>`)
  assertEquals(parseFeed(xml, IGN, NOW).map((a) => a.title), ['Fine'])
})

Deno.test('a feed gives the newest articles first, and at most the per-source limit', () => {
  const items = Array.from({ length: PER_SOURCE_LIMIT + 10 }, (_, i) =>
    `<item><title>Item ${i}</title><link>https://a.com/${i}</link>` +
    `<pubDate>${new Date((NOW - 10000 + i * 60) * 1000).toUTCString()}</pubDate></item>`).join('')
  const articles = parseFeed(rss(items), IGN, NOW)
  assertEquals(articles.length, PER_SOURCE_LIMIT)
  assertEquals(articles[0].title, `Item ${PER_SOURCE_LIMIT + 9}`)
  assertEquals(articles.every((a, i) => i === 0 || articles[i - 1].published_at >= a.published_at), true)
})

Deno.test('numbers in titles stay text, and an item is an item whether there is one or many', () => {
  const one = parseFeed(rss(`<item><title>2077</title><link>https://a.com/1</link><pubDate>${new Date(NOW * 1000).toUTCString()}</pubDate></item>`), IGN, NOW)
  assertEquals(one.map((a) => a.title), ['2077'])
})

Deno.test('what is not an RSS feed gives no articles', () => {
  assertEquals(parseFeed('', IGN, NOW), [])
  assertEquals(parseFeed('<html><body>Blocked</body></html>', IGN, NOW), [])
  assertEquals(parseFeed('<rss><channel></channel></rss>', IGN, NOW), [])
  assertEquals(parseFeed('<rss><channel><item><title>x', IGN, NOW), [])
})

const article = (id: string, url: string, published: number): NewsArticle => ({
  id, title: id, summary: '', url, image_url: null, source_id: 's', source_name: 'S', published_at: published,
})

Deno.test('feeds merge newest first, an address once, at most the limit', () => {
  const merged = mergeArticles([
    [article('a1', 'https://x/1', 300), article('a2', 'https://x/2', 100)],
    [article('b1', 'https://x/1', 300), article('b2', 'https://x/3', 200)],
  ])
  assertEquals(merged.map((a) => a.id), ['a1', 'b2', 'a2'])
  assertEquals(mergeArticles([[article('a', 'https://x/1', 1), article('b', 'https://x/2', 2)]], 1).map((a) => a.id), ['b'])
  assertEquals(mergeArticles([]).length, 0)
  const many = Array.from({ length: MAX_ARTICLES + 20 }, (_, i) => article(`n${i}`, `https://x/${i}`, i))
  assertEquals(mergeArticles([many]).length, MAX_ARTICLES)
})

Deno.test("Steam's news becomes articles with the markup taken out", () => {
  const body = {
    appnews: {
      appid: 1145360,
      newsitems: [
        {
          gid: '5001',
          title: 'Patch 1.2 &amp; hotfix',
          url: 'https://steamstore-a.akamaihd.net/news/externalpost/steam_community_announcements/5001',
          feedlabel: 'Community Announcements',
          date: NOW - 3600,
          contents: '{STEAM_CLAN_IMAGE}/1/a.png [h2]Patch notes[/h2] [list][*] Fixed the [b]boss[/b] bug [url=https://x.com]link[/url][/list] https://store.steampowered.com/app/1',
        },
        { gid: '5002', title: 'Old', url: 'https://a.com/old', date: NOW - 90 * 86400, contents: 'x' },
        { gid: '5003', title: 'Bad link', url: 'steam://openurl/https://x.com', date: NOW, contents: 'x' },
        { gid: '5004', title: 'Newer', url: 'https://a.com/new', feedlabel: '', date: NOW - 60, contents: '' },
      ],
    },
  }
  const articles = steamArticles(1145360, body, NOW)
  assertEquals(articles.map((a) => a.title), ['Newer', 'Patch 1.2 & hotfix'])
  const patch = articles[1]
  assertEquals(patch.summary, 'Patch notes Fixed the boss bug link')
  assertEquals(patch.source_id, 'steam')
  assertEquals(patch.source_name, 'Community Announcements')
  assertEquals(patch.app_id, 1145360)
  assertEquals(patch.image_url, null)
  assertEquals(articles[0].source_name, 'Steam')
  assertEquals(articles[0].summary, '')
  assertEquals(steamArticles(1, { appnews: 'nope' }, NOW), [])
  assertEquals(steamArticles(1, null, NOW), [])
})

Deno.test('a feed request names a language and maybe one outlet, and pages', () => {
  assertEquals(parseNewsRequest(undefined), { mode: 'feed', lang: 'en', source: null, limit: 20, offset: 0 })
  assertEquals(parseNewsRequest({ mode: 'feed', lang: 'ru', source: 'stopgame', limit: 10, offset: 20 }), {
    mode: 'feed', lang: 'ru', source: 'stopgame', limit: 10, offset: 20,
  })
  // Limit and offset are brought into range, not refused.
  assertEquals(parseNewsRequest({ limit: 9999, offset: -5 }), { mode: 'feed', lang: 'en', source: null, limit: 50, offset: 0 })
  assertEquals(parseNewsRequest({ limit: 'many', offset: 'x' }), { mode: 'feed', lang: 'en', source: null, limit: 20, offset: 0 })
})

Deno.test('a feed request with another language, or an outlet of the other language, is refused', () => {
  assertEquals(typeof parseNewsRequest({ lang: 'de' }), 'string')
  assertEquals(typeof parseNewsRequest({ lang: 'en', source: 'stopgame' }), 'string')
  assertEquals(typeof parseNewsRequest({ lang: 'en', source: 7 }), 'string')
  assertEquals(typeof parseNewsRequest({ mode: 'other' }), 'string')
})

Deno.test('a Steam request names 1 to 10 apps', () => {
  assertEquals(parseNewsRequest({ mode: 'steam', app_ids: [570, 730, 570] }), {
    mode: 'steam', appIds: [570, 730], limit: 20, offset: 0,
  })
  for (const app_ids of [[], 'x', undefined, [0], [-1], [1.5], ['570'], Array.from({ length: 11 }, (_, i) => i + 1)]) {
    assertEquals(typeof parseNewsRequest({ mode: 'steam', app_ids }), 'string', JSON.stringify(app_ids))
  }
})
