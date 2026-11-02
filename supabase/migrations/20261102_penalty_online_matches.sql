-- Secure, realtime head-to-head penalty shootouts for accepted friends.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table public.penalty_online_matches (
  id uuid primary key default gen_random_uuid(),
  inviter_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  invitee_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  status text not null default 'invited' check (status in ('invited', 'playing', 'completed', 'declined')),
  kick_no smallint not null default 0 check (kick_no between 0 and 50),
  score_inviter smallint not null default 0 check (score_inviter between 0 and 30),
  score_invitee smallint not null default 0 check (score_invitee between 0 and 30),
  saves_inviter smallint not null default 0 check (saves_inviter between 0 and 30),
  saves_invitee smallint not null default 0 check (saves_invitee between 0 and 30),
  pending_count smallint not null default 0 check (pending_count between 0 and 1),
  score_history jsonb not null default '[]'::jsonb check (jsonb_typeof(score_history) = 'array'),
  last_shot_direction text check (last_shot_direction in ('left', 'center', 'right')),
  last_save_direction text check (last_save_direction in ('left', 'center', 'right')),
  last_goal boolean,
  winner_id uuid references public.penalty_profiles(user_id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint penalty_online_match_not_self check (inviter_id <> invitee_id)
);

create index penalty_online_matches_inviter_status_idx
  on public.penalty_online_matches (inviter_id, status, created_at desc);
create index penalty_online_matches_invitee_status_idx
  on public.penalty_online_matches (invitee_id, status, created_at desc);

create table public.penalty_online_moves (
  match_id uuid not null references public.penalty_online_matches(id) on delete cascade,
  kick_no smallint not null check (kick_no between 0 and 49),
  player_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  role text not null check (role in ('shooter', 'keeper')),
  direction text not null check (direction in ('left', 'center', 'right')),
  created_at timestamptz not null default now(),
  primary key (match_id, kick_no, player_id)
);

create table public.penalty_online_results (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.penalty_online_matches(id) on delete cascade,
  user_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  opponent_id uuid not null references public.penalty_profiles(user_id) on delete cascade,
  won boolean not null,
  goals_for smallint not null check (goals_for between 0 and 30),
  goals_against smallint not null check (goals_against between 0 and 30),
  saves smallint not null default 0 check (saves between 0 and 30),
  kicks_faced smallint not null default 0 check (kicks_faced between 0 and 30),
  created_at timestamptz not null default now(),
  constraint penalty_online_results_match_player_unique unique (match_id, user_id),
  constraint penalty_online_results_not_self check (user_id <> opponent_id)
);
create index penalty_online_results_user_idx on public.penalty_online_results (user_id, created_at desc);

alter table public.penalty_online_matches enable row level security;
alter table public.penalty_online_moves enable row level security;
alter table public.penalty_online_results enable row level security;

grant select, insert, update on public.penalty_online_matches to authenticated;
grant select, insert on public.penalty_online_moves to authenticated;
grant select on public.penalty_online_results to authenticated;

create policy "Players can read their online shootouts"
  on public.penalty_online_matches for select to authenticated
  using ((select auth.uid()) = inviter_id or (select auth.uid()) = invitee_id);

create policy "Players can invite accepted friends"
  on public.penalty_online_matches for insert to authenticated
  with check (
    (select auth.uid()) = inviter_id
    and status = 'invited'
    and exists (
      select 1 from public.penalty_friendships f
      where f.status = 'accepted'
        and ((f.requester_id = (select auth.uid()) and f.recipient_id = invitee_id)
          or (f.recipient_id = (select auth.uid()) and f.requester_id = invitee_id))
    )
  );

create or replace function private.guard_penalty_online_match_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.inviter_id is distinct from (select auth.uid())
     or new.status <> 'invited'
     or new.kick_no <> 0
     or new.score_inviter <> 0
     or new.score_invitee <> 0
     or new.saves_inviter <> 0
     or new.saves_invitee <> 0
     or new.pending_count <> 0
     or new.score_history <> '[]'::jsonb
     or new.last_shot_direction is not null
     or new.last_save_direction is not null
     or new.last_goal is not null
     or new.winner_id is not null
  then
    raise exception 'A new online shootout must start in a clean invited state';
  end if;
  return new;
end;
$$;

create trigger penalty_online_matches_guard_insert
  before insert on public.penalty_online_matches
  for each row execute function private.guard_penalty_online_match_insert();
revoke all on function private.guard_penalty_online_match_insert() from public, anon, authenticated;

create policy "Invitees can answer an open challenge"
  on public.penalty_online_matches for update to authenticated
  using ((select auth.uid()) = invitee_id and status = 'invited')
  with check ((select auth.uid()) = invitee_id and status in ('playing', 'declined'));

create policy "Players can read only their own live choices"
  on public.penalty_online_moves for select to authenticated
  using ((select auth.uid()) = player_id);
create policy "Players can submit only their own live choice"
  on public.penalty_online_moves for insert to authenticated
  with check ((select auth.uid()) = player_id);
create policy "Signed-in players can view verified online results"
  on public.penalty_online_results for select to authenticated using (true);

create or replace function private.guard_penalty_online_match_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if current_setting('penalty.internal_match_update', true) = 'on' then
    return new;
  end if;

  if old.status <> 'invited'
     or (select auth.uid()) is distinct from old.invitee_id
     or new.status not in ('playing', 'declined')
     or new.id is distinct from old.id
     or new.inviter_id is distinct from old.inviter_id
     or new.invitee_id is distinct from old.invitee_id
     or new.kick_no is distinct from old.kick_no
     or new.score_inviter is distinct from old.score_inviter
     or new.score_invitee is distinct from old.score_invitee
     or new.saves_inviter is distinct from old.saves_inviter
     or new.saves_invitee is distinct from old.saves_invitee
     or new.pending_count is distinct from old.pending_count
     or new.score_history is distinct from old.score_history
     or new.last_shot_direction is distinct from old.last_shot_direction
     or new.last_save_direction is distinct from old.last_save_direction
     or new.last_goal is distinct from old.last_goal
     or new.winner_id is distinct from old.winner_id
     or new.created_at is distinct from old.created_at
  then
    raise exception 'Only the invited player may accept or decline this challenge';
  end if;
  return new;
end;
$$;

create trigger penalty_online_matches_guard_update
  before update on public.penalty_online_matches
  for each row execute function private.guard_penalty_online_match_update();
revoke all on function private.guard_penalty_online_match_update() from public, anon, authenticated;

create or replace function private.validate_penalty_online_move()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.penalty_online_matches%rowtype;
  expected_shooter uuid;
  expected_role text;
begin
  if new.player_id is distinct from (select auth.uid()) then
    raise exception 'A player can submit only their own choice';
  end if;

  select * into m from public.penalty_online_matches where id = new.match_id for update;
  if not found or m.status <> 'playing' then
    raise exception 'This shootout is not accepting choices';
  end if;
  if new.kick_no <> m.kick_no then
    raise exception 'This choice is for an old or future kick';
  end if;

  expected_shooter := case when mod(m.kick_no, 2) = 0 then m.inviter_id else m.invitee_id end;
  expected_role := case when new.player_id = expected_shooter then 'shooter' else 'keeper' end;
  if new.player_id not in (m.inviter_id, m.invitee_id) or new.role <> expected_role then
    raise exception 'Invalid player role for this kick';
  end if;
  return new;
end;
$$;

create trigger penalty_online_moves_validate
  before insert on public.penalty_online_moves
  for each row execute function private.validate_penalty_online_move();
revoke all on function private.validate_penalty_online_move() from public, anon, authenticated;

create or replace function private.resolve_penalty_online_move()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  m public.penalty_online_matches%rowtype;
  shooter_id uuid;
  keeper_id uuid;
  shot_dir text;
  save_dir text;
  scored boolean;
  next_kick smallint;
  new_score_inviter smallint;
  new_score_invitee smallint;
  new_saves_inviter smallint;
  new_saves_invitee smallint;
  remaining_inviter integer;
  remaining_invitee integer;
  is_complete boolean;
  won_by uuid;
  new_history jsonb;
  kicks_inviter smallint;
  kicks_invitee smallint;
begin
  select * into m from public.penalty_online_matches where id = new.match_id for update;
  select count(*)::smallint into next_kick
    from public.penalty_online_moves
    where match_id = new.match_id and kick_no = new.kick_no;

  perform set_config('penalty.internal_match_update', 'on', true);
  if next_kick < 2 then
    update public.penalty_online_matches
      set pending_count = 1, updated_at = now()
      where id = m.id;
    return new;
  end if;

  shooter_id := case when mod(new.kick_no, 2) = 0 then m.inviter_id else m.invitee_id end;
  keeper_id := case when shooter_id = m.inviter_id then m.invitee_id else m.inviter_id end;
  select direction into shot_dir from public.penalty_online_moves
    where match_id = m.id and kick_no = new.kick_no and player_id = shooter_id;
  select direction into save_dir from public.penalty_online_moves
    where match_id = m.id and kick_no = new.kick_no and player_id = keeper_id;

  scored := shot_dir <> save_dir;
  new_score_inviter := m.score_inviter + case when scored and shooter_id = m.inviter_id then 1 else 0 end;
  new_score_invitee := m.score_invitee + case when scored and shooter_id = m.invitee_id then 1 else 0 end;
  new_saves_inviter := m.saves_inviter + case when not scored and keeper_id = m.inviter_id then 1 else 0 end;
  new_saves_invitee := m.saves_invitee + case when not scored and keeper_id = m.invitee_id then 1 else 0 end;
  next_kick := m.kick_no + 1;
  new_history := m.score_history || jsonb_build_array(jsonb_build_object(
    'kick_no', m.kick_no, 'shooter_id', shooter_id, 'scored', scored,
    'shot_direction', shot_dir, 'save_direction', save_dir
  ));

  select count(*)::integer into remaining_inviter from generate_series(next_kick::integer, 9) n where mod(n, 2) = 0;
  select count(*)::integer into remaining_invitee from generate_series(next_kick::integer, 9) n where mod(n, 2) = 1;
  is_complete := next_kick >= 50
    or (next_kick = 10 and new_score_inviter <> new_score_invitee)
    or (next_kick < 10 and (new_score_inviter > new_score_invitee + remaining_invitee
      or new_score_invitee > new_score_inviter + remaining_inviter))
    or (next_kick >= 12 and mod(next_kick, 2) = 0 and new_score_inviter <> new_score_invitee);
  won_by := case when new_score_inviter > new_score_invitee then m.inviter_id
                 when new_score_invitee > new_score_inviter then m.invitee_id else null end;

  select count(*)::smallint into kicks_inviter from jsonb_array_elements(new_history) e where e->>'shooter_id' = m.inviter_id::text;
  select count(*)::smallint into kicks_invitee from jsonb_array_elements(new_history) e where e->>'shooter_id' = m.invitee_id::text;

  update public.penalty_online_matches set
    kick_no = next_kick,
    score_inviter = new_score_inviter,
    score_invitee = new_score_invitee,
    saves_inviter = new_saves_inviter,
    saves_invitee = new_saves_invitee,
    pending_count = 0,
    score_history = new_history,
    last_shot_direction = shot_dir,
    last_save_direction = save_dir,
    last_goal = scored,
    status = case when is_complete then 'completed' else 'playing' end,
    winner_id = case when is_complete then won_by else null end,
    updated_at = now()
  where id = m.id;

  if is_complete then
    insert into public.penalty_online_results
      (match_id, user_id, opponent_id, won, goals_for, goals_against, saves, kicks_faced)
    values
      (m.id, m.inviter_id, m.invitee_id, new_score_inviter > new_score_invitee,
       new_score_inviter, new_score_invitee, new_saves_inviter, kicks_invitee),
      (m.id, m.invitee_id, m.inviter_id, new_score_invitee > new_score_inviter,
       new_score_invitee, new_score_inviter, new_saves_invitee, kicks_inviter);
  end if;
  return new;
end;
$$;

create trigger penalty_online_moves_resolve
  after insert on public.penalty_online_moves
  for each row execute function private.resolve_penalty_online_move();
revoke all on function private.resolve_penalty_online_move() from public, anon, authenticated;

create or replace view public.penalty_online_leaderboard
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
left join public.penalty_online_results m on m.user_id = p.user_id
group by p.user_id, p.username, p.display_name;
grant select on public.penalty_online_leaderboard to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'penalty_online_matches'
     ) then
    alter publication supabase_realtime add table public.penalty_online_matches;
  end if;
end;
$$;

