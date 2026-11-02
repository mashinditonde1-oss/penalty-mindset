# Penalty Mindset

A static penalty shootout game with guest rooms, email accounts, accepted friends, live head-to-head matches, and a verified online leaderboard.

## Deploy to Cloudflare Pages

Connect this repository to Cloudflare Pages with:

- **Production branch:** `main`
- **Build command:** `exit 0`
- **Build output directory:** `.` (the repository root)

The app is static. `index.html` and `account.js` must be deployed together.

## Supabase setup

The game is connected to the Penalty Mindset Supabase project using its public publishable key. Never put a Supabase service-role key in this repository or in browser code.

The required database migrations are in `supabase/migrations/`. They are applied to the connected project. For a fresh Supabase project, run these migrations in order:

1. `20261102_penalty_mindset.sql`
2. `20261102_penalty_online_matches.sql`
3. `20261103_penalty_rooms.sql`
4. `20261104_penalty_room_clock.sql`
5. `20261104_penalty_room_exit.sql`
6. `20261104_penalty_room_rematches.sql`
7. `20261104_penalty_room_rematch_indexes.sql`

In Supabase **Authentication → URL Configuration**, set the Site URL to `https://penalty-mindset.pages.dev` and add `https://penalty-mindset.pages.dev/**` to Redirect URLs. Signup from a local development server redirects to the live site so the confirmation link does not point at the user's own device.

Guest rooms use Supabase anonymous sign-ins so players can create and join a room without an email account. Enable **Allow anonymous sign-ins** under **Authentication → Sign In / Providers**. The guest session is temporary and is not added to the ranked leaderboard.

## How online play works

Players can create a shareable room or join one with a 10-character code. Both players choose their shot or dive on their own device; each turn has a shared 10-second clock, after which the server fills in any missing choice and advances the match. If a player exits, the opponent is told they disconnected and sent back to the main screen. After a completed room match, both players can request a rematch; the new head-to-head begins when both agree. Supabase resolves each kick and handles sudden death. Room games are friendly and not ranked. Signed-in players can also accept each other as friends, send a challenge, and submit verified results to the online leaderboard.

The game is just for fun; it does not use real money.

