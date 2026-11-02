# Penalty Mindset

A static penalty shootout game with email accounts, accepted friends, live head-to-head matches, and a verified online leaderboard.

## Deploy to Cloudflare Pages

Connect this repository to Cloudflare Pages with:

- **Production branch:** `main`
- **Build command:** `exit 0`
- **Build output directory:** `.` (the repository root)

The app is static. `index.html` and `account.js` must be deployed together.

## Supabase setup

The game is already connected to the Penalty Mindset Supabase project using its public publishable key. Never put a Supabase service-role key in this repository or in browser code.

The required database migrations are in `supabase/migrations/`. They were applied to the connected project. For a fresh Supabase project, run these migrations in order:

1. `20261102_penalty_mindset.sql`
2. `20261102_penalty_online_matches.sql`

In Supabase **Authentication → URL Configuration**, set the Site URL to `https://penalty-mindset.pages.dev` and add `https://penalty-mindset.pages.dev/**` to Redirect URLs. Signup from a local development server redirects to the live site so the confirmation link does not point at the user's own device. Supabase requires the redirect destination to be allowlisted; its Site URL is the fallback when no valid `redirect_to` is supplied.

## How online play works

Players sign in, accept each other as friends, and send or accept a challenge from **Play online**. Both choose their shot or dive on their own device. Supabase resolves each kick, handles sudden death, and records verified match results for the online leaderboard. Players can rejoin an active match after reconnecting.

The game is just for fun; it does not use real money.
