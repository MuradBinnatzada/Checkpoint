import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { steam_id } = await req.json()
    if (!steam_id) throw new Error('Missing steam_id')

    const apiKey = Deno.env.get('STEAM_API_KEY')
    if (!apiKey) throw new Error('Server missing Steam API key')

    const steamUrl = `http://api.steampowered.com/IPlayerService/GetOwnedGames/v0001/?key=${apiKey}&steamid=${steam_id}&format=json&include_appinfo=true&include_played_free_games=true`
    
    const response = await fetch(steamUrl)
    const data = await response.json()

    const games = data.response?.games || []
    
    return new Response(JSON.stringify({ games }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    return new Response(JSON.stringify({ error: (error as Error).message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 400,
    })
  }
})