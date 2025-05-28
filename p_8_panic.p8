pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- Helper: Point-in-polygon (works for convex polygons, including triangles and quads)
function point_in_polygon(px, py, vertices)
  local inside = false
  local n = #vertices
  for i=1,n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end
--p8panic
--A game of tactical geometry.

-- luacheck: globals cls btn btnp rect rectfill add all max min pieces cursor_x cursor_y pending_type control_state pending_color pending_orientation current_player
cursor_x=64-4
cursor_y=64-4
pieces={}
scores={0,0,0,0} -- [1]=TL, [2]=TR, [3]=BL, [4]=BR

-- Piece dimensions
local defender_width = 8
local defender_height = 8
local attacker_triangle_height = 8 -- Height along orientation axis
local attacker_triangle_base = 6   -- Base perpendicular to orientation

-- Game constants
LASER_LEN = 60 -- Max length of a laser beam

-- Helper: Ray-segment intersection
-- Returns: ix, iy, t (intersection point and parameter along ray) or nil, nil, nil
function ray_segment_intersect(ray_ox, ray_oy, ray_dx, ray_dy, seg_x1, seg_y1, seg_x2, seg_y2)
  local r_dx, r_dy = ray_dx, ray_dy
  local s_dx, s_dy = seg_x2 - seg_x1, seg_y2 - seg_y1

  local r_s_cross = r_dx * s_dy - r_dy * s_dx
  if r_s_cross == 0 then return nil, nil, nil end -- Parallel or collinear

  local t2 = ( (seg_x1 - ray_ox) * r_dy - (seg_y1 - ray_oy) * r_dx ) / r_s_cross
  local t1 = ( (seg_x1 - ray_ox) * s_dy - (seg_y1 - ray_oy) * s_dx ) / r_s_cross

  if t1 >= 0 and t2 >= 0 and t2 <= 1 then
    return ray_ox + t1 * r_dx, ray_oy + t1 * r_dy, t1
  end
  return nil, nil, nil
end

-- Helper function to get rotated vertices for drawing
function get_piece_draw_vertices(piece)
    local o = piece.orientation -- PICO-8 orientation (0-1)
    -- Rotation center is piece.position
    local cx = piece.position.x
    local cy = piece.position.y

    local local_corners = {}

    if piece.type == "attacker" then
        -- Attacker is a triangle: height 8 (along orientation), base 6
        -- Apex points along the orientation vector
        -- Local coords relative to (cx,cy) which is piece.position
        -- Apex: (height/2, 0)
        -- Base 1: (-height/2, base_width/2)
        -- Base 2: (-height/2, -base_width/2)
        local h = attacker_triangle_height
        local b = attacker_triangle_base
        add(local_corners, {x = h/2, y = 0})      -- Apex
        add(local_corners, {x = -h/2, y = b/2})   -- Base corner 1
        add(local_corners, {x = -h/2, y = -b/2})  -- Base corner 2
    else -- Default to defender (square)
        local w, h = defender_width, defender_height
        -- Local corner coordinates (relative to center piece.position)
        -- For a square centered at (0,0) local_pos:
        -- Top-left, top-right, bottom-right, bottom-left
        local hw = w / 2
        local hh = h / 2
        add(local_corners, {x = -hw, y = -hh})
        add(local_corners, {x = hw, y = -hh})
        add(local_corners, {x = hw, y = hh})
        add(local_corners, {x = -hw, y = hh})
    end

    local world_corners = {}
    for lc in all(local_corners) do
        local rotated_x = lc.x * cos(o) - lc.y * sin(o)
        local rotated_y = lc.x * sin(o) + lc.y * cos(o)
        add(world_corners, {x = cx + rotated_x, y = cy + rotated_y})
    end
    return world_corners
end

-- (Recommended addition for game logic updates - place before _update)
function update_game_logic()
  if pieces then
    for _, p_item in ipairs(pieces) do
      if p_item.type == "defender" then
        p_item.hits = 0
        p_item.targeting_attackers = {} -- Reset list of attackers targeting this defender
        p_item.state = "neutral"      -- Reset state, score_attackers will update it
      end
    end
  end
  score_attackers() -- This function is in 2.scoring.lua

  -- Placeholder for other game logic (e.g., checking win/loss conditions, etc.)
end


-- delegate all input/interaction to controls.lua
function _update()
  update_controls()
  update_game_logic() -- Call game logic updates
end

function _draw()
  cls(0)
  -- print("#pieces: "..#pieces, 0, 0, 7) -- Debug: show number of pieces

  -- draw placed pieces
  for i=1,#pieces do
    local p = pieces[i]
    -- Debug: Print piece properties
    -- local debug_y = (i-1)*6
    -- print("p"..i.." t:"..(p.type or "NIL").." c:"..(p.owner or "NIL").." o:"..(p.orientation or "NIL"), 0, debug_y, 7)
    -- if p.position then
    --   print("x:"..(p.position.x or "NIL").." y:"..(p.position.y or "NIL"), 60, debug_y, 7)
    -- else
    --   print("pos:NIL", 60, debug_y, 7)
    -- end

    if p and p.position and p.orientation ~= nil then
      local vertices = get_piece_draw_vertices(p)
      local min_verts_required = (p.type == "attacker" and 3 or 4)

      if vertices and #vertices >= min_verts_required then
        local body_color = p.owner or 7 -- Default to white if no owner

        if p.type == "attacker" then
          -- Draw attacker body (triangle)
          line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, body_color)
          line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, body_color)
          line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, body_color)

          -- Laser Drawing Logic
          local apex = vertices[1] -- Assuming get_piece_draw_vertices returns apex first
          local dir_x = cos(p.orientation)
          local dir_y = sin(p.orientation)
          
          local min_t_intersect = LASER_LEN
          local hit_defender_object = nil

          -- Find closest defender hit by this attacker's laser
          if pieces then
            for _, ep_check in ipairs(pieces) do
              if ep_check and ep_check ~= p and ep_check.type == "defender" then
                local def_verts = get_piece_draw_vertices(ep_check)
                if def_verts and #def_verts >= 4 then -- Defenders are quads
                  for j_vert=1, #def_verts do
                    local k_vert = (j_vert % #def_verts) + 1
                    local ix, iy, t = ray_segment_intersect(
                      apex.x, apex.y, dir_x, dir_y,
                      def_verts[j_vert].x, def_verts[j_vert].y, def_verts[k_vert].x, def_verts[k_vert].y
                    )
                    if t and t >= 0 and t < min_t_intersect then
                      min_t_intersect = t
                      hit_defender_object = ep_check
                    end
                  end
                end
              end
            end
          end

          local current_laser_color = 5 -- Default: Dark Grey (PICO-8 color 5) for not successful
          local effective_laser_len = min(min_t_intersect, LASER_LEN)

          if hit_defender_object and min_t_intersect <= LASER_LEN then
            -- A defender is hit within range. Now determine if the attacker is "successful" against it.
            -- The "successful" state of the defender itself (hit_defender_object.state) is key.
            -- And the number of attackers targeting it (hit_defender_object.targeting_attackers)
            
            local target_def = hit_defender_object
            target_def.state = target_def.state or "neutral" -- Defensive initialization
            target_def.targeting_attackers = target_def.targeting_attackers or {} -- Defensive initialization
            
            local num_attackers_on_target = #target_def.targeting_attackers
            
            -- Check if this specific attacker 'p' is among those successfully targeting 'target_def'
            -- This requires 'score_attackers' to correctly populate 'target_def.targeting_attackers'
            -- with attackers that contribute to its 'successful' or 'overcharged' state.
            local is_this_attacker_successful = false
            for _, successful_attacker in ipairs(target_def.targeting_attackers) do
              if successful_attacker == p then
                is_this_attacker_successful = true
                break
              end
            end

            if is_this_attacker_successful then
              if target_def.state == "overcharged" then -- Defender has 3+ hits
                current_laser_color = 13 -- Purple: Defender is overcharged
              elseif num_attackers_on_target == 2 and target_def.state == "successful" then
                current_laser_color = 10 -- Yellow: Successful, and exactly 2 attackers on this defender
              elseif num_attackers_on_target > 3 and target_def.state == "successful" then
                 current_laser_color = 13 -- Purple: Successful, and more than 3 attackers on this defender
              else
                -- Successful, but not meeting other specific color conditions (e.g. 1 attacker, or 3 attackers but not overcharged yet)
                current_laser_color = p.owner or 7 -- Use attacker's owner color (or default white)
              end
            end
          end

          -- Draw "dancing ants" laser
          local segments = 16 
          local anim_speed = 4 
          local phase = (time()*anim_speed)%2 -- time() is a PICO-8 global
          for s=0,segments-1 do
            if ((s+phase)%2)<1 then -- Draw only every other segment for "ants"
              local x1 = apex.x + dir_x*effective_laser_len*(s/segments)
              local y1 = apex.y + dir_y*effective_laser_len*(s/segments)
              local x2 = apex.x + dir_x*effective_laser_len*((s+1)/segments)
              local y2 = apex.y + dir_y*effective_laser_len*((s+1)/segments)
              line(x1,y1,x2,y2, current_laser_color)
            end
          end

          -- If in capture mode, draw a purple circle around attackers
          if pending_type == "capture" then
            circ(p.position.x, p.position.y, attacker_triangle_height / 2 + 2, 13) -- Purple circle
          end
        else -- Defender (rectangle)
          line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, body_color)
          line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, body_color)
          line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, body_color)
          line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, body_color)
        end
      else
        -- print("Skipping draw for piece "..i..": invalid vertices", 0, 56, 8) -- Debug
      end
    else
      -- print("Skipping draw for piece "..i..": invalid base properties", 0, 50, 8) -- Debug
    end
  end

  -- Draw cursor based on mode
  if control_state == 0 then -- Movement mode
    if pending_type == "defender" then
      rect(cursor_x, cursor_y, cursor_x + 7, cursor_y + 7, 7) -- White square for defender
    elseif pending_type == "attacker" then
      -- Draw a small triangle preview for attacker (simplified)
      local cx, cy = cursor_x + 4, cursor_y + 4 -- Center of cursor cell
      line(cx + 4, cy, cx - 2, cy - 3, 7)
      line(cx - 2, cy - 3, cx - 2, cy + 3, 7)
      line(cx - 2, cy + 3, cx + 4, cy, 7)
    elseif pending_type == "capture" then
      -- Draw a small crosshair for capture mode
      local cx, cy = cursor_x + 4, cursor_y + 4 -- Center of cursor cell
      line(cx - 2, cy, cx + 2, cy, 7) -- Horizontal line
      line(cx, cy - 2, cx, cy + 2, 7) -- Vertical line
    end
  elseif control_state == 1 then -- Rotation/Confirmation mode
    -- Draw pending piece with orientation and color
    local temp_piece = {
      owner = pending_color,
      type = pending_type,
      position = { x = cursor_x + 4, y = cursor_y + 4 },
      orientation = pending_orientation
    }
    local vertices = get_piece_draw_vertices(temp_piece)
    if vertices and #vertices >=3 then
      if temp_piece.type == "attacker" then
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, pending_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, pending_color)
        line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, pending_color)
      else -- Defender
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, pending_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, pending_color)
        line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, pending_color)
        line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, pending_color)
      end
    end
  end

  -- Draw scores in corners
  local margin = 2
  local font_width = 4 -- Approximate width of a character
  local font_height = 5 -- Height of a character

  -- Top-left score (Player 1 color, if available, else white)
  print(scores[1], margin, margin, player and player.colors and player.colors[1] or 7)
  -- Top-right score (Player 2 color, if available, else red)
  local s2_txt = tostring(scores[2])
  print(s2_txt, 128 - margin - #s2_txt * font_width, margin, player and player.colors and player.colors[2] or 8)
  -- Bottom-left score (Player 3 color, if available, else orange)
  print(scores[3], margin, 128 - margin - font_height, player and player.colors and player.colors[3] or 9)
  -- Bottom-right score (Player 4 color, if available, else yellow)
  local s4_txt = tostring(scores[4])
  print(s4_txt, 128 - margin - #s4_txt * font_width, 128 - margin - font_height, player and player.colors and player.colors[4] or 10)
end
-->8
-- SECTION 4: Placement Module
function legal_placement(piece) -- Made global by removing 'local'
  local w,h=8,8
  local th, tb = 8,6
  local bw,bh=128,128 
  local function vec_sub(a,b) return {x=a.x-b.x, y=a.y-b.y} end
  local function vec_dot(a,b) return a.x*b.x+a.y*b.y end

  local function get_rot(p)
    local o,pv={},{}
    local cx,cy=p.position.x,p.position.y
    local lc={}
    if p.type=="attacker" then
      add(lc,{x=th/2,y=0}); add(lc,{x=-th/2,y=tb/2}); add(lc,{x=-th/2,y=-tb/2})
    else
      local hw,hh=w/2,h/2
      add(lc,{x=-hw,y=-hh});add(lc,{x=hw,y=-hh})
      add(lc,{x=hw,y=hh}); add(lc,{x=-hw,y=hh})
    end
    for c in all(lc) do
      local rx=c.x*cos(p.orientation)-c.y*sin(p.orientation)
      local ry=c.x*sin(p.orientation)+c.y*cos(p.orientation)
      add(pv,{x=cx+rx,y=cy+ry})
    end
    return pv
  end

  local function project(vs,ax)
    local mn,mx=vec_dot(vs[1],ax),vec_dot(vs[1],ax)
    for i=2,#vs do
      local pr=vec_dot(vs[i],ax)
      mn, mx = min(mn,pr), max(mx,pr)
    end
    return mn,mx
  end

  local function get_axes(vs)
    local ua={}
    for i=1,#vs do
      local p1=vs[i]; local p2=vs[(i%#vs)+1]
      local e=vec_sub(p2,p1); local n={x=-e.y,y=e.x}
      local l=sqrt(n.x^2+n.y^2)
      if l>0.0001 then n.x,n.y=n.x/l,n.y/l
        local uniq=true
        for ea in all(ua) do if abs(vec_dot(ea,n))>0.999 then uniq=false end end
        if uniq then add(ua,n) end
      end
    end
    return ua
  end

  -- 1. bounds
  local corners=get_rot(piece)
  for c in all(corners) do
    if c.x<0 or c.x>bw or c.y<0 or c.y>bh then return false end
  end

  -- 2. collision
  local piece_corners = get_rot(piece) -- Cache rotated vertices of the current piece
  if pieces then
    for _, ep in ipairs(pieces) do -- Use ipairs for dense, 1-indexed array
      -- The check 'ep~=piece' is removed as 'piece' is not in 'pieces' table yet during this call.
      local ep_corners = get_rot(ep)
      
      local combined_axes = {}
      for ax_piece in all(get_axes(piece_corners)) do add(combined_axes, ax_piece) end
      for ax_ep in all(get_axes(ep_corners)) do add(combined_axes, ax_ep) end

      local collision_with_ep = true -- Assume collision until a separating axis is found
      if #combined_axes == 0 and #piece_corners > 0 and #ep_corners > 0 then
        -- This case can happen if polygons are degenerate (e.g. a line)
        -- For simplicity, assume non-degenerate or handle as collision if unsure.
      end

      for ax in all(combined_axes) do
        local min1, max1 = project(piece_corners, ax)
        local min2, max2 = project(ep_corners, ax)
        if max1 < min2 or max2 < min1 then -- Separating axis found
          collision_with_ep = false -- No collision between piece and ep
          break -- Stop checking axes for this pair
        end
      end

      if collision_with_ep then
        -- All axes showed overlap for this pair (piece, ep), so they collide
        return false -- Illegal placement
      end
    end
  end

  -- 3. attacker laser validation
  if piece.type == "attacker" then
    local apex = piece_corners[1] -- First vertex from get_rot for attacker is the apex
    local dir_x = cos(piece.orientation)
    local dir_y = sin(piece.orientation)
    
    local laser_hits_defender = false
    if pieces then -- Ensure pieces table exists
      for _, ep_val in ipairs(pieces) do -- Use ipairs for dense, 1-indexed array
        if ep_val.type == "defender" then
          local defender_corners = get_rot(ep_val) -- Get rotated corners of the existing defender
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local x1, y1 = defender_corners[j].x, defender_corners[j].y
            local x2, y2 = defender_corners[k].x, defender_corners[k].y
            
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, x1, y1, x2, y2)
            
            if t and t >= 0 and t <= LASER_LEN then -- Hit within laser range (t>=0 ensures it's forward)
              laser_hits_defender = true
              break -- Found a hit with this defender's segment
            end
          end
        end
        if laser_hits_defender then
          break -- Found a defender hit by the laser
        end
      end
    end
    
    if not laser_hits_defender then
      return false -- Attacker laser must hit a defender
    end
  end

  return true
end

function place_piece(p) -- Made global by removing 'local'
  -- p is the candidate piece data: { owner, type, position, orientation }
  if legal_placement(p) then
    -- Augment the piece data 'p' before adding it to the global 'pieces' list
    if p.type == "defender" then
      p.hits = 0
      p.state = "neutral" -- "successful", "unsuccessful", "overcharged"
      p.targeting_attackers = {} -- List of attacker pieces targeting this defender
    elseif p.type == "attacker" then
      -- Attackers don't have specific state like defenders in this mechanic
      -- but could have properties like 'currently_hitting = {}' if needed later
    end
    add(pieces, p) -- Add the (potentially augmented) piece 'p'
    -- redraw_lasers() was a placeholder, actual laser drawing is in _draw
  end
end
-->8
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
__gfx__
00000000aaaaaaaaaaaaaaaaaaaaaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9999999999999999999999a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9444444444444444444449a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9444444444444444444449a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9999999999999999999999a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000aaaaaaaaaaaaaaaaaaaaaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0102020202020202020202020202020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122222222222222222222222222222300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

