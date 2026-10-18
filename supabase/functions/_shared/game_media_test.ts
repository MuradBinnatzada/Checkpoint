import { assertEquals } from 'jsr:@std/assert@1'
import { gameMedia, MAX_IMAGES, mediaQuery } from './game_media.ts'

Deno.test('the media query names only the game id', () => {
  assertEquals(
    mediaQuery(1164),
    'fields artworks.image_id, artworks.width, artworks.height, screenshots.image_id, screenshots.width, screenshots.height; where id = 1164; limit 1;',
  )
})

Deno.test('gameMedia keeps each usable image once', () => {
  const media = gameMedia({
    id: 1164,
    artworks: [
      { image_id: 'ar1', width: 1920, height: 1080 },
      { image_id: 'ar1' }, // duplicate
      { image_id: '../evil' },
      { width: 10 },
      null,
    ],
    screenshots: [{ image_id: 'sc1', width: -5, height: 'x' }],
  })
  assertEquals(media.artworks, [{ image_id: 'ar1', width: 1920, height: 1080 }])
  assertEquals(media.screenshots, [{ image_id: 'sc1', width: null, height: null }])
})

Deno.test('gameMedia copes with a game without art', () => {
  assertEquals(gameMedia({ id: 1 }), { artworks: [], screenshots: [] })
})

Deno.test('gameMedia caps artworks and screenshots', () => {
  const many = Array.from({ length: MAX_IMAGES + 10 }, (_, i) => ({ image_id: `sc${i}` }))
  assertEquals(gameMedia({ screenshots: many }).screenshots.length, MAX_IMAGES)
})
