-- src/1.placement.lua
-- Placement Module
--#globals create_piece pieces ray_segment_intersect LASER_LEN player_manager score_pieces
--#globals cos sin max min sqrt abs add all ipairs
--#globals PLAYER_COUNT -- Though not directly used, it's part of the context of 0.init

-- Cached math functions (assuming they are available globally from 0.init.lua or PICO-8 defaults)
-- local cos, sin = cos, sin -- Or just use them directly
-- local max, min = max, min
-- local sqrt, abs = sqrt, abs

function legal_placement(piece_params)
  local bw, bh = 128, 128
  local temp_piece_obj = create_piece(piece_params)
  if not temp_piece_obj then return false end

  local function vec_sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end
  local function vec_dot(a, b) return a.x * b.x + a.y * b.y end
  local function project(vs, ax)
    if not vs or #vs == 0 then return 0,0 end -- Guard against empty vertices
    local mn, mx = vec_dot(vs[1], ax), vec_dot(vs[1], ax)
    for i = 2, #vs do
      local pr = vec_dot(vs[i], ax)
      mn, mx = min(mn, pr), max(mx, pr)
    end
    return mn, mx
  end
  local function get_axes(vs)
    local ua = {}
    if not vs or #vs < 2 then return ua end -- Need at least 2 vertices for an edge
    for i = 1, #vs do
      local p1 = vs[i]
      local p2 = vs[(i % #vs) + 1]
      local e = vec_sub(p2, p1)
      local n = {x = -e.y, y = e.x}
      local l = sqrt(n.x^2 + n.y^2)
      if l > 0.0001 then
        n.x, n.y = n.x / l, n.y / l
        local uniq = true
        for ea in all(ua) do if abs(vec_dot(ea, n)) > 0.999 then uniq = false; break end end
        if uniq then add(ua, n) end
      end
    end
    return ua
  end

  local corners = temp_piece_obj:get_draw_vertices()
  if not corners or #corners == 0 then return false end -- No vertices to check
  for c in all(corners) do
    if c.x < 0 or c.x > bw or c.y < 0 or c.y > bh then return false end
  end

  for _, ep_obj in ipairs(pieces) do
    local ep_corners = ep_obj:get_draw_vertices()
    if not ep_corners or #ep_corners == 0 then goto next_ep_check end -- Skip if existing piece has no vertices

    local combined_axes = {}
    for ax_piece in all(get_axes(corners)) do add(combined_axes, ax_piece) end
    for ax_ep in all(get_axes(ep_corners)) do add(combined_axes, ax_ep) end
    
    if #combined_axes == 0 then -- Potentially both are lines or points
        local min_x1, max_x1, min_y1, max_y1 = bw, 0, bh, 0
        for c in all(corners) do min_x1=min(min_x1,c.x) max_x1=max(max_x1,c.x) min_y1=min(min_y1,c.y) max_y1=max(max_y1,c.y) end
        local min_x2, max_x2, min_y2, max_y2 = bw, 0, bh, 0
        for c in all(ep_corners) do min_x2=min(min_x2,c.x) max_x2=max(max_x2,c.x) min_y2=min(min_y2,c.y) max_y2=max(max_y2,c.y) end
        if not (max_x1 < min_x2 or max_x2 < min_x1 or max_y1 < min_y2 or max_y2 < min_y1) then
            return false 
        end
        goto next_ep_check 
    end

    local collision_with_ep = true
    for ax in all(combined_axes) do
      local min1, max1 = project(corners, ax)
      local min2, max2 = project(ep_corners, ax)
      if max1 < min2 or max2 < min1 then
        collision_with_ep = false
        break
      end
    end
    if collision_with_ep then return false end
    ::next_ep_check::
  end

  if piece_params.type == "attacker" then
    local apex = corners[1]
    local dir_x = cos(piece_params.orientation)
    local dir_y = sin(piece_params.orientation)
    local laser_hits_defender = false
    for _, ep_obj in ipairs(pieces) do
      if ep_obj.type == "defender" then
        local def_corners = ep_obj:get_draw_vertices()
        if not def_corners or #def_corners == 0 then goto next_laser_target_check end
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = ray_segment_intersect(
            apex.x, apex.y, dir_x, dir_y,
            def_corners[j].x, def_corners[j].y, def_corners[k].x, def_corners[k].y
          )
          if t and t >= 0 and t <= LASER_LEN then
            laser_hits_defender = true
            break
          end
        end
      end
      if laser_hits_defender then break end
      ::next_laser_target_check::
    end
    if not laser_hits_defender then return false end
  end

  return true
end

function place_piece(piece_params, player_obj)
  if legal_placement(piece_params) then
    local piece_color_to_place = piece_params.color -- Strictly use the color from params

    if piece_color_to_place == nil then
      printh("PLACE ERROR: piece_params.color is NIL!")
      return false -- Fail if no color specified by controls
    end
    
    printh("Place attempt: P"..player_obj.id.." color: "..tostring(piece_color_to_place).." type: "..piece_params.type)

    if player_obj:use_piece_from_stash(piece_color_to_place) then
      -- piece_params already contains the .color, create_piece should use it
      local new_piece_obj = create_piece(piece_params) 
      if new_piece_obj then
        add(pieces, new_piece_obj)
        score_pieces() -- Recalculate scores after placing a piece
        printh("Placed piece with color: " .. tostring(new_piece_obj:get_color()))
        return true
      else
        printh("Failed to create piece object after stash use.")
        player_obj:add_captured_piece(piece_color_to_place) -- Return piece to stash
        return false
      end
    else
      printh("P" .. player_obj.id .. " has no piece of color " .. tostring(piece_color_to_place) .. " in stash.")
      return false
    end
  else
    printh("Placement not legal for P"..player_obj.id)
    return false
  end
end
