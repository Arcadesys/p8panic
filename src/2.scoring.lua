--iterate through all attackers and score them

--for each attacker, check if its laser is hitting a defender.
--if it is, increment the defender's hits by 1.
--if a defender's hits reach 2, the attackers pointed at it are considered successful and each score 1 point for their owners.
--if a defender's   hits reach 3, it is considered overcharged. All pieces targeting it are still considered successful, for purposes of scoring, but it entitles the player to capture a piece attacking them.
function score_attackers()
  for _, attacker in ipairs(pieces) do
    if attacker and attacker.type == "attacker" then
      local attacker_vertices = get_piece_draw_vertices(attacker)
      if not attacker_vertices or #attacker_vertices == 0 then goto next_attacker end -- Should not happen if piece is valid
      local apex = attacker_vertices[1] -- The first vertex is the apex for attackers
      local dir_x = cos(attacker.orientation)
      local dir_y = sin(attacker.orientation)
      
      for _, defender in ipairs(pieces) do
        if defender and defender.type == "defender" then
          local defender_corners = get_piece_draw_vertices(defender)
          if not defender_corners or #defender_corners == 0 then goto next_defender end

          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local x1, y1 = defender_corners[j].x, defender_corners[j].y
            local x2, y2 = defender_corners[k].x, defender_corners[k].y
            
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, x1, y1, x2, y2)
            
            if t and t >= 0 and t <= LASER_LEN then -- Hit within laser range
              -- Ensure defender.hits and defender.targeting_attackers are initialized
              defender.hits = (defender.hits or 0)
              defender.targeting_attackers = defender.targeting_attackers or {}

              defender.hits += 1 -- Increment hits on the defender
              
              -- If hits reach 2 or more, score the attacker
              if defender.hits == 2 then
                if attacker.owner and scores[attacker.owner] then
                  scores[attacker.owner] += 1 -- Increment score for attacker owner
                end
                defender.state = "successful"
              elseif defender.hits == 3 then
                 if attacker.owner and scores[attacker.owner] then
                  scores[attacker.owner] += 1 -- Still successful but overcharged
                end
                defender.state = "overcharged"
              end

              -- Track which attackers are targeting this defender
              add(defender.targeting_attackers, attacker) -- Use PICO-8 'add'
              break -- No need to check other segments once we hit one
            end
          end
        end
        ::next_defender::
      end
    end
    ::next_attacker::
  end
end