create index penalty_room_moves_player_idx on public.penalty_room_moves (player_id);
create index penalty_rooms_left_by_idx on public.penalty_rooms (left_by);
create index penalty_rooms_rematch_room_idx on public.penalty_rooms (rematch_room_id);

