function reset_player_scores()
  if player_manager and player_manager.current_players then
    for _, player_obj in ipairs(player_manager.current_players) do
      if player_obj then
        player_obj.score = 0
      end
    end
  end
end

function reset_piece_states_for_scoring()
  for _, p_obj in ipairs(pieces) do
    if p_obj then
      p_obj.hits = 0
      p_obj.targeting_attackers = {}
      p_obj.dbg_target_count = nil
      -- do not reset p_obj.state or p_obj.overcharge_announced here!
    end
  end
end

function _check_attacker_hit_piece(attacker_obj, target_obj, player_manager_param, ray_segment_intersect_func, current_laser_len, add_func)
  local attacker_vertices = attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices == 0 then return end
  local apex = attacker_vertices[1]
  local dir_x = cos(attacker_obj.orientation)
  local dir_y = sin(attacker_obj.orientation)

  local target_corners = target_obj:get_draw_vertices()
  if not target_corners or #target_corners == 0 then return end

  for j = 1, #target_corners do
    local k = (j % #target_corners) + 1
    local ix, iy, t = ray_segment_intersect_func(apex.x, apex.y, dir_x, dir_y,
                                                 target_corners[j].x, target_corners[j].y,
                                                 target_corners[k].x, target_corners[k].y)
    if t and t >= 0 and t <= current_laser_len then
      target_obj.hits = (target_obj.hits or 0) + 1
      target_obj.targeting_attackers = target_obj.targeting_attackers or {}
      add_func(target_obj.targeting_attackers, attacker_obj)

      local attacker_player = player_manager_param.get_player(attacker_obj.owner_id)
      local target_player = player_manager_param.get_player(target_obj.owner_id)

      if attacker_player and target_player and attacker_obj.owner_id ~= target_obj.owner_id then
        attacker_player:add_score(1)
      end

      if target_obj.type == "defender" then
        if target_obj.hits >= 3 then
          target_obj.state = "overcharged"
        elseif target_obj.hits == 2 then
          target_obj.state = "unsuccessful"
        elseif target_obj.hits == 1 then
          target_obj.state = "successful"
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