-- src/2.scoring.lua
-- Scoring Module
--#globals pieces player_manager ray_segment_intersect LASER_LEN
--#globals cos sin add ipairs del deli

function score_attackers()
  for _, attacker_obj in ipairs(pieces) do
    if attacker_obj and attacker_obj.type == "attacker" then
      local attacker_vertices = attacker_obj:get_draw_vertices()
      if not attacker_vertices or #attacker_vertices == 0 then goto next_attacker_score end
      local apex = attacker_vertices[1]
      local dir_x = cos(attacker_obj.orientation)
      local dir_y = sin(attacker_obj.orientation)
      
      for _, defender_obj in ipairs(pieces) do
        if defender_obj and defender_obj.type == "defender" then
          local defender_corners = defender_obj:get_draw_vertices()
          if not defender_corners or #defender_corners == 0 then goto next_defender_score end
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y,
                                                     defender_corners[j].x, defender_corners[j].y,
                                                     defender_corners[k].x, defender_corners[k].y)
            if t and t >= 0 and t <= LASER_LEN then
              defender_obj.hits = (defender_obj.hits or 0) + 1
              defender_obj.targeting_attackers = defender_obj.targeting_attackers or {}
              add(defender_obj.targeting_attackers, attacker_obj)
              
              local attacker_player = player_manager.get_player(attacker_obj.owner_id)
              local defender_player = player_manager.get_player(defender_obj.owner_id)

              if defender_obj.hits == 2 then
                defender_obj.state = "unsuccessful" -- Defender is hit, but not overcharged
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  attacker_player:add_score(1)
                end
              elseif defender_obj.hits >= 3 then -- Changed to >= 3
                defender_obj.state = "overcharged"
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  -- Score for the hit
                  attacker_player:add_score(1) 
                  -- If defender is overcharged by an opponent, attacker captures the defender's color
                  local captured_piece_color = defender_player:get_color()
                  attacker_player:add_captured_piece(captured_piece_color)
                  defender_obj.captured_flag = true -- Mark for removal
                end
              elseif defender_obj.hits == 1 then
                defender_obj.state = "neutral" -- Hit once, still neutral
              end
              break -- Attacker hits this defender, move to next attacker or finish
            end
          end
        end
        ::next_defender_score::
      end
    end
    ::next_attacker_score::
  end

  local remaining_pieces = {}
  for _,p_obj in ipairs(pieces) do
    if not p_obj.captured_flag then
      add(remaining_pieces, p_obj)
    else
      printh("Piece removed due to overcharge capture: P" .. p_obj.owner_id .. " " .. p_obj.type)
    end
  end
  pieces = remaining_pieces
end