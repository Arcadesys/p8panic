-- src/2.scoring.lua
-- Scoring Module
--#globals pieces player_manager ray_segment_intersect LASER_LEN _G
--#globals cos sin add ipairs del deli

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
      -- p_obj.state = nil -- or some default state if applicable
    end
  end
end

function score_pieces()
  reset_player_scores() -- Reset scores for all players
  reset_piece_states_for_scoring() -- Reset hits and targeting attackers for all pieces

  -- Score attackers hitting defenders
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

              -- Award score to attacker if they hit an opponent's defender
              if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                attacker_player:add_score(1)
              end

              -- Update defender state based on total hits
              if defender_obj.hits == 1 then
                defender_obj.state = "successful" -- Hit once
              elseif defender_obj.hits == 2 then
                defender_obj.state = "unsuccessful" -- Defender is hit twice
              elseif defender_obj.hits >= 3 then
                defender_obj.state = "overcharged" -- Defender is hit three or more times
              end
              -- Only count one hit per attacker-defender pair, then stop checking other segments
              break
            end
          end
        end
        ::next_defender_score::
      end
    end
    ::next_attacker_score::
  end

  -- Score defenders based on incoming attackers
  for _, p_obj in ipairs(pieces) do
    if p_obj and p_obj.type == "defender" then
      local num_total_attackers_targeting = 0
      if p_obj.targeting_attackers then
        num_total_attackers_targeting = #p_obj.targeting_attackers
      end
      p_obj.dbg_target_count = num_total_attackers_targeting -- Store for on-screen debugging

      if num_total_attackers_targeting <= 1 then -- Defender scores if 0 or 1 attacker targets it
        local defender_player = player_manager.get_player(p_obj.owner_id)
        if defender_player then
          defender_player:add_score(1)
          -- Potentially update defender state here if needed, e.g., p_obj.state = "defending_well"
        end
      end
      -- If num_total_attackers_targeting is 2 or more, the defender does not score a point.
    end
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

-- Renamed from score_attackers to score_pieces to reflect broader scope
score_pieces = score_pieces