function reset_player_scores()
 if player_manager and player_manager.current_players then
  for _,p in ipairs(player_manager.current_players)do
   if p then p.score=0 end
  end
 end
end

function reset_piece_states_for_scoring()
 for _,p in ipairs(pieces)do
  if p then
   p.hits=0
   p.targeting_attackers={}
   p.dbg_target_count=nil
   if p.type=="defender"then p.state="successful"end
  end
 end
end

function _check_attacker_hit_piece(a,t,pm,rsif,cll,af)
 local av=a:get_draw_vertices()
 if not av or #av==0 then return end
 local apex=av[1]
 local dx,dy=cos(a.orientation),sin(a.orientation)

  local target_corners = t:get_draw_vertices()
  if not target_corners or #target_corners == 0 then return end

  for j = 1, #target_corners do
    local k = (j % #target_corners) + 1
    local ix, iy, hit_t = rsif(apex.x, apex.y, dx, dy,
                                                 target_corners[j].x, target_corners[j].y,
                                                 target_corners[k].x, target_corners[k].y)
    if hit_t and hit_t >= 0 and hit_t <= cll then
      t.hits = (t.hits or 0) + 1
      t.targeting_attackers = t.targeting_attackers or {}
      af(t.targeting_attackers, a)

      local attacker_player = pm.get_player(a.owner_id)
      local target_player = pm.get_player(t.owner_id)

      if attacker_player and target_player and a.owner_id ~= t.owner_id then
        attacker_player:add_score(1)
      end

      if t.type == "defender" then
        if t.hits >= 3 then
          t.state = "overcharged"
        elseif t.hits == 2 then
          t.state = "unsuccessful"
        elseif t.hits == 1 then
          t.state = "successful"
        end
      end
      return true
    end
  end
  return false
end

function _score_defender(p_obj, player_manager_param)
  if p_obj and p_obj.type == "defender" then
    local num_total_attackers_targeting = 0
    if p_obj.targeting_attackers then
      num_total_attackers_targeting = #p_obj.targeting_attackers
    end

    if num_total_attackers_targeting <= 1 then
      local defender_player = player_manager_param.get_player(p_obj.owner_id)
      if defender_player then
        defender_player:add_score(1)
      end
    end
  end
end

function score_pieces()
  -- Ensure required globals are available
  local player_manager = player_manager
  local ray_segment_intersect = ray_segment_intersect
  local LASER_LEN = LASER_LEN
  local add = add
  reset_player_scores()
  reset_piece_states_for_scoring()

  for _, attacker_obj in ipairs(pieces) do
    if attacker_obj and attacker_obj.type == "attacker" then
      local attacker_vertices = attacker_obj:get_draw_vertices()
      if attacker_vertices and #attacker_vertices > 0 then
        local apex = attacker_vertices[1]
        local dir_x = cos(attacker_obj.orientation)
        local dir_y = sin(attacker_obj.orientation)
        local closest_t = LASER_LEN
        local closest_piece = nil
        -- Check all other pieces for intersection
        for _, target_obj in ipairs(pieces) do
          if target_obj ~= attacker_obj then
            local target_corners = target_obj:get_draw_vertices()
            if target_corners and #target_corners > 0 then
              for j = 1, #target_corners do
                local k = (j % #target_corners) + 1
                local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y,
                  target_corners[j].x, target_corners[j].y,
                  target_corners[k].x, target_corners[k].y)
                if t and t >= 0 and t < closest_t then
                  closest_t = t
                  closest_piece = target_obj
                end
              end
            end
          end
        end
        if closest_piece then
          _check_attacker_hit_piece(attacker_obj, closest_piece, player_manager, ray_segment_intersect, LASER_LEN, add)
        end
      end
    end
  end

  for _, p_obj in ipairs(pieces) do
    _score_defender(p_obj, player_manager)
    if p_obj.type == "defender" then
      p_obj.dbg_target_count = nil
      -- Update defender state based on final hit count
      if p_obj.hits >= 3 then
        p_obj.state = "overcharged"
      elseif p_obj.hits == 2 then
        p_obj.state = "unsuccessful"
      elseif p_obj.hits <= 1 then
        p_obj.state = "successful"
      end
    end
  end

  local remaining_pieces = {}
  for _,p_obj in ipairs(pieces) do
    if not p_obj.captured_flag then
      add(remaining_pieces, p_obj)
    end
  end
  pieces = remaining_pieces
end