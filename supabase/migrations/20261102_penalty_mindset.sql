-- Account-backed profiles, friend requests, and ranked match results for Penalty Mindset.
-- Public profile data is limited to a user-chosen handle and display name.

create table public.penalty_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text not null,
  display_name text not null,
  created_at timestamptz not null default now(),
  constraint penalty_profiles_username_format check (username ~ '^[a-z0-9_]{3,18}$'),
  constraint penalty_profiles_display_name_length check (char_length(display_name) between 1 and 24)
);

create unique index penalty_profiles_username_lower_uidx
  on public.penalty_profiles (lower(username));

create table public.penalty_friendships (
  id bigint generated always as identity primary key,
  requester_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  recipient_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint penalty_friendships_not_self check (requester_id <> recipient_id),
  constraint penalty_friendships_pair_unique unique (requester_id, recipient_id)
);

create index penalty_friendships_recipient_status_idx
  on public.penalty_friendships (recipient_id, status);
create index penalty_friendships_requester_status_idx
  on public.penalty_friendships (requester_id, status);
create unique index penalty_friendships_pair_ordered_uidx
  on public.penalty_friendships (
    least(requester_id, recipient_id),
    greatest(requester_id, recipient_id)
  );

create table public.penalty_matches (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  opponent_id uuid references public.penalty_profiles(user_id) on delete set null,
  match_mode text not null check (match_mode in ('solo', 'friend')),
  won boolean not null,
  goals_for smallint not null check (goals_for between 0 and 30),
  goals_against smallint not null check (goals_against between 0 and 30),
  saves smallint not null default 0 check (saves between 0 and 30),
  kicks_faced smallint not null default 0 check (kicks_faced between 0 and 30),
  created_at timestamptz not null default now(),
  constraint penalty_matches_friend_opponent_check
    check ((match_mode = 'solo' and opponent_id is null) or match_mode = 'friend')
);

create index penalty_matches_leaderboard_idx
  on public.penalty_matches (created_at desc, user_id);
create index penalty_matches_user_idx
  on public.penalty_matches (user_id, created_at desc);

alter table public.penalty_profiles enable row level security;
alter table public.penalty_friendships enable row level security;
alter table public.penalty_matches enable row level security;

grant select, insert, update on public.penalty_profiles to authenticated;
grant select, insert, update, delete on public.penalty_friendships to authenticated;
grant select, insert on public.penalty_matches to authenticated;
grant usage, select on sequence public.penalty_friendships_id_seq to authenticated;
grant usage, select on sequence public.penalty_matches_id_seq to authenticated;

create policy "Signed-in users can find game handles"
  on public.penalty_profiles for select to authenticated using (true);
create policy "Players can create their own game profile"
  on public.penalty_profiles for insert to authenticated
  with check ((select auth.uid()) = user_id);
create policy "Players can update their own game profile"
  on public.penalty_profiles for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Players can see their own friend links"
  on public.penalty_friendships for select to authenticated
  using ((select auth.uid()) = requester_id or (select auth.uid()) = recipient_id);
create policy "Players can send friend requests"
  on public.penalty_friendships for insert to authenticated
  with check ((select auth.uid()) = requester_id and status = 'pending');
create policy "Recipients can accept incoming friend requests"
  on public.penalty_friendships for update to authenticated
  using ((select auth.uid()) = recipient_id and status = 'pending')
  with check ((select auth.uid()) = recipient_id and status = 'accepted');

create or replace function public.prevent_penalty_friendship_identity_change()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.requester_id <> old.requester_id or new.recipient_id <> old.recipient_id then
    raise exception 'Friend request participants cannot be changed';
  end if;
  if new.status <> old.status and not (old.status = 'pending' and new.status = 'accepted') then
    raise exception 'Invalid friend request status transition';
  end if;
  return new;
end;
$$;

create trigger penalty_friendships_protect_identity
  before update on public.penalty_friendships
  for each row execute function public.prevent_penalty_friendship_identity_change();

revoke execute on function public.prevent_penalty_friendship_identity_change() from public, anon, authenticated;
create policy "Either player can remove a pending request"
  on public.penalty_friendships for delete to authenticated
  using (((select auth.uid()) = requester_id or (select auth.uid()) = recipient_id) and status = 'pending');

create policy "Signed-in players can view ranked match results"
  on public.penalty_matches for select to authenticated using (true);
create policy "Players can submit their own match results"
  on public.penalty_matches for insert to authenticated
  with check ((select auth.uid()) = user_id);

create or replace view public.penalty_leaderboard
with (security_invoker = true)
as
select
  p.user_id,
  p.username,
  p.display_name,
  count(m.id)::integer as matches_played,
  count(m.id) filter (where m.won)::integer as wins,
  coalesce(sum(m.goals_for), 0)::integer as goals_scored,
  coalesce(sum(m.saves), 0)::integer as saves,
  max(m.created_at) as last_played_at
from public.penalty_profiles p
left join public.penalty_matches m on m.user_id = p.user_id and m.match_mode = 'solo'
group by p.user_id, p.username, p.display_name;

grant select on public.penalty_leaderboard to authenticated;

