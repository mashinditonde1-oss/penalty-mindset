-- Shared-code round-robin tournaments for 3–8 players.
create table public.penalty_tournaments (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^[A-HJ-NP-Z2-9]{10}$'),
  host_id uuid not null references auth.users(id) on delete cascade,
  host_name text not null check (char_length(trim(host_name)) between 1 and 24),
  status text not null default 'waiting' check (status in ('waiting', 'playing', 'completed')),
  winner_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz
);

create table public.penalty_tournament_players (
  tournament_id uuid not null references public.penalty_tournaments(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 24),
  joined_at timestamptz not null default now(),
  wins smallint not null default 0 check (wins >= 0),
  draws smallint not null default 0 check (draws >= 0),
  losses smallint not null default 0 check (losses >= 0),
  goals_for smallint not null default 0 check (goals_for >= 0),
  goals_against smallint not null default 0 check (goals_against >= 0),
  primary key (tournament_id, player_id)
);

create table public.penalty_tournament_matches (
  id uuid primary key default gen_random_uuid(),
  tournament_id uuid not null references public.penalty_tournaments(id) on delete cascade,
  player_a_id uuid not null references auth.users(id) on delete cascade,
  player_b_id uuid not null references auth.users(id) on delete cascade,
  room_id uuid unique references public.penalty_rooms(id) on delete set null,
  room_code text,
  status text not null default 'pending' check (status in ('pending', 'waiting', 'playing', 'completed')),
  winner_id uuid references auth.users(id) on delete set null,
  score_a smallint,
  score_b smallint,
  created_at timestamptz not null default now(),
  completed_at timestamptz,
  check (player_a_id <> player_b_id),
  unique (tournament_id, player_a_id, player_b_id)
);

alter table public.penalty_rooms
  add column tournament_match_id uuid references public.penalty_tournament_matches(id) on delete set null;
create index penalty_tournament_matches_tournament_idx
  on public.penalty_tournament_matches (tournament_id, status, created_at);
create index penalty_tournament_players_standings_idx
  on public.penalty_tournament_players (tournament_id, wins desc, goals_for desc);

alter table public.penalty_tournaments enable row level security;
alter table public.penalty_tournament_players enable row level security;
alter table public.penalty_tournament_matches enable row level security;
revoke all on public.penalty_tournaments, public.penalty_tournament_players, public.penalty_tournament_matches from anon, authenticated;
grant select on public.penalty_tournaments, public.penalty_tournament_players, public.penalty_tournament_matches to authenticated;

create or replace function private.is_penalty_tournament_player(p_tournament_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.penalty_tournament_players p
    where p.tournament_id = p_tournament_id and p.player_id = (select auth.uid())
  );
$$;
revoke all on function private.is_penalty_tournament_player(uuid) from public, anon, authenticated;
grant execute on function private.is_penalty_tournament_player(uuid) to authenticated;

create policy "Tournament players can read their tournaments"
  on public.penalty_tournaments for select to authenticated
  using (private.is_penalty_tournament_player(id));
create policy "Tournament players can read their standings"
  on public.penalty_tournament_players for select to authenticated
  using (private.is_penalty_tournament_player(tournament_id));
create policy "Tournament players can read their fixtures"
  on public.penalty_tournament_matches for select to authenticated
  using (private.is_penalty_tournament_player(tournament_id));

create or replace function public.create_penalty_tournament(p_id uuid, p_code text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid := coalesce(p_id, gen_random_uuid());
  v_name text := left(trim(regexp_replace(coalesce(p_display_name, 'Guest'), '[<>]', '', 'g')), 24);
begin
  if v_user_id is null then raise exception 'Continue as a guest or sign in to create a tournament'; end if;
  if upper(trim(p_code)) !~ '^[A-HJ-NP-Z2-9]{10}$' then raise exception 'Tournament code must be 10 characters'; end if;
  if v_name = '' then v_name := 'Guest'; end if;
  insert into public.penalty_tournaments(id, code, host_id, host_name)
  values (v_id, upper(trim(p_code)), v_user_id, v_name);
  insert into public.penalty_tournament_players(tournament_id, player_id, display_name)
  values (v_id, v_user_id, v_name);
  return v_id;
end;
$$;
revoke all on function public.create_penalty_tournament(uuid, text, text) from public, anon;
grant execute on function public.create_penalty_tournament(uuid, text, text) to authenticated;

create or replace function public.join_penalty_tournament(p_code text, p_display_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_id uuid;
  v_name text := left(trim(regexp_replace(coalesce(p_display_name, 'Guest'), '[<>]', '', 'g')), 24);
begin
  if v_user_id is null then raise exception 'Continue as a guest or sign in to join'; end if;
  if v_name = '' then v_name := 'Guest'; end if;
  select id into v_id from public.penalty_tournaments
   where code = upper(trim(p_code)) and status = 'waiting' for update;
  if not found then raise exception 'Tournament is unavailable or has already started'; end if;
  if exists (select 1 from public.penalty_tournament_players where tournament_id = v_id and player_id = v_user_id) then
    return v_id;
  end if;
  if (select count(*) from public.penalty_tournament_players where tournament_id = v_id) >= 8 then
    raise exception 'This tournament is full (8 players maximum)';
  end if;
  insert into public.penalty_tournament_players(tournament_id, player_id, display_name)
  values (v_id, v_user_id, v_name);
  return v_id;
end;
$$;
revoke all on function public.join_penalty_tournament(text, text) from public, anon;
grant execute on function public.join_penalty_tournament(text, text) to authenticated;

create or replace function public.start_penalty_tournament(p_tournament_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  t public.penalty_tournaments%rowtype;
  ids uuid[];
  i integer;
  j integer;
begin
  select * into t from public.penalty_tournaments where id = p_tournament_id for update;
  if not found or t.host_id <> (select auth.uid()) then raise exception 'Only the tournament host can start it'; end if;
  if t.status <> 'waiting' then return false; end if;
  select array_agg(player_id order by joined_at, player_id) into ids
    from public.penalty_tournament_players where tournament_id = t.id;
  if coalesce(array_length(ids, 1), 0) < 3 then raise exception 'At least 3 players are needed to start'; end if;
  if array_length(ids, 1) > 8 then raise exception 'A tournament can have at most 8 players'; end if;
  for i in 1..array_length(ids, 1) - 1 loop
    for j in i + 1..array_length(ids, 1) loop
      insert into public.penalty_tournament_matches(tournament_id, player_a_id, player_b_id)
      values (t.id, ids[i], ids[j]);
    end loop;
  end loop;
  update public.penalty_tournaments set status = 'playing', started_at = now() where id = t.id;
  return true;
end;
$$;
revoke all on function public.start_penalty_tournament(uuid) from public, anon;
grant execute on function public.start_penalty_tournament(uuid) to authenticated;

create or replace function public.create_penalty_tournament_room(p_match_id uuid, p_room_id uuid, p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.penalty_tournament_matches%rowtype;
  t public.penalty_tournaments%rowtype;
  v_user_id uuid := (select auth.uid());
  v_name text;
  v_other_id uuid;
  v_other_name text;
begin
  select * into m from public.penalty_tournament_matches where id = p_match_id for update;
  if not found or v_user_id not in (m.player_a_id, m.player_b_id) then raise exception 'You are not a player in this fixture'; end if;
  select * into t from public.penalty_tournaments where id = m.tournament_id;
  if t.status <> 'playing' or m.status <> 'pending' or m.room_id is not null then raise exception 'This fixture already has a room'; end if;
  if upper(trim(p_code)) !~ '^[A-HJ-NP-Z2-9]{10}$' then raise exception 'Invalid room code'; end if;
  select display_name into v_name from public.penalty_tournament_players where tournament_id = m.tournament_id and player_id = v_user_id;
  v_other_id := case when v_user_id = m.player_a_id then m.player_b_id else m.player_a_id end;
  select display_name into v_other_name from public.penalty_tournament_players where tournament_id = m.tournament_id and player_id = v_other_id;
  insert into public.penalty_rooms(id, code, host_id, host_name, tournament_match_id)
  values (p_room_id, upper(trim(p_code)), v_user_id, v_name, m.id);
  update public.penalty_tournament_matches
    set room_id = p_room_id, room_code = upper(trim(p_code)), status = 'waiting'
    where id = m.id;
  return jsonb_build_object('id', p_room_id, 'code', upper(trim(p_code)), 'opponent_id', v_other_id, 'opponent_name', v_other_name);
end;
$$;
revoke all on function public.create_penalty_tournament_room(uuid, uuid, text) from public, anon;
grant execute on function public.create_penalty_tournament_room(uuid, uuid, text) to authenticated;

create or replace function private.sync_penalty_tournament_room()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.penalty_tournament_matches%rowtype;
  v_score_a smallint;
  v_score_b smallint;
begin
  if new.tournament_match_id is null or new.status = old.status then return new; end if;
  if new.status = 'playing' then
    update public.penalty_tournament_matches set status = 'playing'
      where id = new.tournament_match_id and status = 'waiting';
  elsif new.status = 'disconnected' then
    update public.penalty_tournament_matches set room_id = null, room_code = null, status = 'pending'
      where id = new.tournament_match_id and status in ('waiting', 'playing');
  elsif new.status = 'completed' then
    select * into m from public.penalty_tournament_matches where id = new.tournament_match_id for update;
    if not found or m.status = 'completed' then return new; end if;
    v_score_a := case when new.host_id = m.player_a_id then new.score_host else new.score_guest end;
    v_score_b := case when new.host_id = m.player_a_id then new.score_guest else new.score_host end;
    update public.penalty_tournament_matches set status = 'completed', winner_id = new.winner_id,
      score_a = v_score_a, score_b = v_score_b, completed_at = now() where id = m.id;
    update public.penalty_tournament_players set
      goals_for = goals_for + v_score_a, goals_against = goals_against + v_score_b,
      wins = wins + case when new.winner_id = m.player_a_id then 1 else 0 end,
      draws = draws + case when new.winner_id is null then 1 else 0 end,
      losses = losses + case when new.winner_id = m.player_b_id then 1 else 0 end
      where tournament_id = m.tournament_id and player_id = m.player_a_id;
    update public.penalty_tournament_players set
      goals_for = goals_for + v_score_b, goals_against = goals_against + v_score_a,
      wins = wins + case when new.winner_id = m.player_b_id then 1 else 0 end,
      draws = draws + case when new.winner_id is null then 1 else 0 end,
      losses = losses + case when new.winner_id = m.player_a_id then 1 else 0 end
      where tournament_id = m.tournament_id and player_id = m.player_b_id;
    if not exists (select 1 from public.penalty_tournament_matches where tournament_id = m.tournament_id and status <> 'completed') then
      update public.penalty_tournaments set status = 'completed', completed_at = now(), winner_id = (
        select player_id from public.penalty_tournament_players
         where tournament_id = m.tournament_id
         order by wins * 3 + draws desc, wins desc, goals_for - goals_against desc, joined_at asc
         limit 1
      ) where id = m.tournament_id;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function private.sync_penalty_tournament_room() from public, anon, authenticated;
create trigger penalty_rooms_sync_tournament
  after update of status on public.penalty_rooms
  for each row execute function private.sync_penalty_tournament_room();



