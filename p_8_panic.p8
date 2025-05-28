pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- p8panic - A game of tactical geometry

-------------------------------------------
-- Helpers & Global Constants/Variables --
-------------------------------------------
function point_in_polygon(px, py, vertices)
  local inside = false
  local n = #vertices
  for i = 1, n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end

-- Global game state variables
pieces = {}
scores = {0, 0, 0, 0}   -- Scores for up to 4 players
LASER_LEN = 60          -- Maximum laser beam length

-- Piece dimensions / drawing config
local defender_width = 8
local defender_height = 8
local attacker_triangle_height = 8 -- along orientation axis
local attacker_triangle_base = 6   -- perpendicular

-- Cached math functions
local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

-------------------------------------------
-- Player Configuration --
-------------------------------------------
player = {
  colors = {12, 4, 11, 10},      -- Colors for placed pieces
  ghost_colors = {1, 8, 3, 9}      -- Colors for ghost cursors
}

-------------------------------------------
-- Multi-Cursor Support (one per player) --
-------------------------------------------
cursors = {}

-- Initialize cursors for N players; they spawn in different screen corners.
function init_cursors(num_players)
  local spawn_points = {}
  if num_players == 3 then
    spawn_points = {
      {x = 4, y = 4},                -- top-left
      {x = 128 - 12, y = 4},           -- top-right
      {x = 4, y = 128 - 12}            -- bottom-left
    }
  else -- assume 4 players
    spawn_points = {
      {x = 4, y = 4},                -- top-left
      {x = 128 - 12, y = 4},           -- top-right
      {x = 4, y = 128 - 12},           -- bottom-left
      {x = 128 - 12, y = 128 - 12}     -- bottom-right
    }
  end

  for i, sp in ipairs(spawn_points) do
    cursors[i] = {
      x = sp.x, y = sp.y,
      spawn_x = sp.x, spawn_y = sp.y,
      control_state = 0,       -- 0: Movement/Selection, 1: Rotation/Placement, 2: Cooldown/Return
      pending_type = "defender",  -- "defender", "attacker", "capture"
      -- Use ghost color for cursor, placed pieces will use player.colors in controls below.
      pending_color = (player and player.ghost_colors and player.ghost_colors[i]) or 7,
      pending_orientation = 0,
      return_cooldown = 0
    }
  end
end

init_cursors(4)

-------------------------------------------
-- Piece Drawing & Helper Functions        --
-------------------------------------------
function get_piece_draw_vertices(piece)
  local o = piece.orientation
  local cx = piece.position.x
  local cy = piece.position.y
  local local_corners = {}

  if piece.type == "attacker" then
    local h = attacker_triangle_height
    local b = attacker_triangle_base
    add(local_corners, {x = h/2, y = 0})      -- Apex
    add(local_corners, {x = -h/2, y = b/2})     -- Base corner 1
    add(local_corners, {x = -h/2, y = -b/2})    -- Base corner 2
  else
    local w, h = defender_width, defender_height
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

-- Ray-segment intersection helper.
function ray_segment_intersect(ray_ox, ray_oy, ray_dx, ray_dy,
                               seg_x1, seg_y1, seg_x2, seg_y2)
  local s_dx = seg_x2 - seg_x1
  local s_dy = seg_y2 - seg_y1
  local r_s_cross = ray_dx * s_dy - ray_dy * s_dx
  if r_s_cross == 0 then return nil, nil, nil end
  
  local t2 = ((seg_x1 - ray_ox) * ray_dy - (seg_y1 - ray_oy) * ray_dx) / r_s_cross
  local t1 = ((seg_x1 - ray_ox) * s_dy - (seg_y1 - ray_oy) * s_dx) / r_s_cross
  
  if t1 >= 0 and t2 >= 0 and t2 <= 1 then
    return ray_ox + t1 * ray_dx, ray_oy + t1 * ray_dy, t1
  end
  return nil, nil, nil
end

-------------------------------------------
-- Placement Module (from 1.placement.lua) --
-------------------------------------------
function legal_placement(piece)
  local bw, bh = 128, 128

  local function vec_sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end
  local function vec_dot(a, b) return a.x * b.x + a.y * b.y end
  local function project(vs, ax)
    local mn, mx = vec_dot(vs[1], ax), vec_dot(vs[1], ax)
    for i = 2, #vs do
      local pr = vec_dot(vs[i], ax)
      mn, mx = min(mn, pr), max(mx, pr)
    end
    return mn, mx
  end
  local function get_axes(vs)
    local ua = {}
    for i = 1, #vs do
      local p1 = vs[i]
      local p2 = vs[(i % #vs) + 1]
      local e = vec_sub(p2, p1)
      local n = {x = -e.y, y = e.x}
      local l = sqrt(n.x^2 + n.y^2)
      if l > 0.0001 then
        n.x, n.y = n.x / l, n.y / l
        local uniq = true
        for ea in all(ua) do if abs(vec_dot(ea, n)) > 0.999 then uniq = false end end
        if uniq then add(ua, n) end
      end
    end
    return ua
  end

  local corners = get_piece_draw_vertices(piece)
  for c in all(corners) do
    if c.x < 0 or c.x > bw or c.y < 0 or c.y > bh then return false end
  end

  for _, ep in ipairs(pieces) do
    local ep_corners = get_piece_draw_vertices(ep)
    local combined_axes = {}
    for ax_piece in all(get_axes(corners)) do add(combined_axes, ax_piece) end
    for ax_ep in all(get_axes(ep_corners)) do add(combined_axes, ax_ep) end
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
  end

  -- Attacker laser validation (ensure that a placed attacker’s laser hits a defender)
  if piece.type == "attacker" then
    local apex = corners[1]
    local dir_x = cos(piece.orientation)
    local dir_y = sin(piece.orientation)
    local laser_hits_defender = false
    for _, ep in ipairs(pieces) do
      if ep.type == "defender" then
        local def_corners = get_piece_draw_vertices(ep)
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
    end
    if not laser_hits_defender then return false end
  end

  return true
end

function place_piece(p)
  if legal_placement(p) then
    if p.type == "defender" then
      p.hits = 0
      p.state = "neutral"
      p.targeting_attackers = {}
    end
    add(pieces, p)
  end
end

-------------------------------------------
-- Scoring Module (from 2.scoring.lua)    --
-------------------------------------------
function score_attackers()
  for _, attacker in ipairs(pieces) do
    if attacker and attacker.type == "attacker" then
      local attacker_vertices = get_piece_draw_vertices(attacker)
      if not attacker_vertices or #attacker_vertices == 0 then goto next_attacker end
      local apex = attacker_vertices[1]
      local dir_x = cos(attacker.orientation)
      local dir_y = sin(attacker.orientation)
      
      for _, defender in ipairs(pieces) do
        if defender and defender.type == "defender" then
          local defender_corners = get_piece_draw_vertices(defender)
          if not defender_corners or #defender_corners == 0 then goto next_defender end
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y,
                                                     defender_corners[j].x, defender_corners[j].y,
                                                     defender_corners[k].x, defender_corners[k].y)
            if t and t >= 0 and t <= LASER_LEN then
              defender.hits = (defender.hits or 0) + 1
              defender.targeting_attackers = defender.targeting_attackers or {}
              add(defender.targeting_attackers, attacker)
              -- Only attackers score, not defenders, for 2+ hits
              if defender.hits == 2 then
                defender.state = "unsuccessful"
                if attacker.owner and defender.owner and attacker.owner ~= defender.owner then
                  scores[attacker.owner] += 1
                end
              elseif defender.hits == 3 then
                defender.state = "overcharged"
                if attacker.owner and defender.owner and attacker.owner ~= defender.owner then
                  scores[attacker.owner] += 1
                end
              elseif defender.hits == 1 then
                defender.state = "neutral"
              end
              break
            end
          end
        end
        ::next_defender::
      end
    end
    ::next_attacker::
  end
end

-------------------------------------------
-- Controls Module (from 3.controls.lua)  --
-------------------------------------------
function update_controls()
  local cursor_speed = 2
  local rotation_speed = 0.02
  for i, cur in ipairs(cursors) do
    -- Pico-8 controller index is (i-1)
    if cur.control_state == 0 then
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      if btnp(🅾️, i - 1) then
        if cur.pending_type == "defender" then
          cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
          cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
          cur.pending_type = "defender"
        end
      end

      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          -- (Capture logic placeholder)
        else
          cur.control_state = 1
          cur.pending_orientation = 0
        end
      end

    elseif cur.control_state == 1 then
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end
      if btnp(❎, i - 1) then
        local piece_to_place = {
          -- Use the placed piece color from player.colors:
          owner = (player and player.colors and player.colors[i]) or 7,
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
        }
        place_piece(piece_to_place)
        cur.control_state = 2
        cur.return_cooldown = 6  -- 6 frames cooldown
      end
      if btnp(🅾️, i - 1) then
        cur.control_state = 0
      end

    elseif cur.control_state == 2 then
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = 0
        cur.pending_orientation = 0
        cur.pending_type = "defender"
        -- Reset ghost color to player's ghost color
        cur.pending_color = (player and player.ghost_colors and player.ghost_colors[i]) or 7
      end
    end
  end
end

-------------------------------------------
-- Game Logic & Main Loop                --
-------------------------------------------
function update_game_logic()
  for _, p_item in ipairs(pieces) do
    if p_item.type == "defender" then
      p_item.hits = 0
      p_item.targeting_attackers = {}
      p_item.state = "neutral"
    end
  end
  score_attackers()
end

function _update()
  update_controls()
  update_game_logic()
end

function _draw()
  cls(0)
  for i = 1, #pieces do
    local p = pieces[i]
    if p and p.position and p.orientation ~= nil then
      local vertices = get_piece_draw_vertices(p)
      local body_color = p.owner or 7
      if p.type == "attacker" then
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, body_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, body_color)
        line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, body_color)
        local apex = vertices[1]
        local dir_x = cos(p.orientation)
        local dir_y = sin(p.orientation)
        local min_t_intersect = LASER_LEN
        local laser_color = body_color -- default: owner's color
        -- Check if this attacker's laser hits an overcharged or successful defender
        for _, ep in ipairs(pieces) do
          if ep and ep ~= p and ep.type == "defender" then
            local def_verts = get_piece_draw_vertices(ep)
            if def_verts and #def_verts >= 4 then
              for j = 1, #def_verts do
                local k = (j % #def_verts) + 1
                local ix, iy, t = ray_segment_intersect(
                  apex.x, apex.y, dir_x, dir_y,
                  def_verts[j].x, def_verts[j].y, def_verts[k].x, def_verts[k].y
                )
                if t and t >= 0 and t < min_t_intersect then
                  min_t_intersect = t
                  -- Set laser color based on defender state
                  if ep.state == "overcharged" then
                    laser_color = 8 -- red/pink
                  elseif ep.state == "successful" then
                    laser_color = 11 -- green
                  end
                end
              end
            end
          end
        end
        local effective_len = min(min_t_intersect, LASER_LEN)
        if effective_len >= 8 then
          local segments = 16         -- total dash parts (dashes+gaps)
          local dash_ratio = 0.6        -- proportion of each segment that is drawn
          local segment_length = effective_len / segments
          local anim_speed = 30
          local offset = (time() * anim_speed) % segment_length
          for s = 0, segments - 1 do
            local seg_start = s * segment_length + offset
            local seg_end = seg_start + segment_length * dash_ratio
            if seg_end > effective_len then seg_end = effective_len end
            local x1 = apex.x + dir_x * seg_start
            local y1 = apex.y + dir_y * seg_start
            local x2 = apex.x + dir_x * seg_end
            local y2 = apex.y + dir_y * seg_end
            line(x1, y1, x2, y2, laser_color)
          end
        elseif effective_len > 0 then
          local ex = apex.x + dir_x * effective_len
          local ey = apex.y + dir_y * effective_len
          line(apex.x, apex.y, ex, ey, laser_color)
        end
        if p.pending_type == "capture" then
          circ(p.position.x, p.position.y, attacker_triangle_height / 2 + 2, 13)
        end
      else
        -- Defender color always player's color
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, body_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, body_color)
        line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, body_color)
        line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, body_color)
      end
    end
  end
  
  for i, cur in ipairs(cursors) do
    if cur.control_state == 0 or cur.control_state == 2 then
      if cur.pending_type == "defender" then
        rect(cur.x, cur.y, cur.x + 7, cur.y + 7, cur.pending_color)
      elseif cur.pending_type == "attacker" then
        local cx, cy = cur.x + 4, cur.y + 4
        line(cx + 4, cy, cx - 2, cy - 3, cur.pending_color)
        line(cx - 2, cy - 3, cx - 2, cy + 3, cur.pending_color)
        line(cx - 2, cy + 3, cx + 4, cy, cur.pending_color)
      elseif cur.pending_type == "capture" then
        local cx, cy = cur.x + 4, cur.y + 4
        line(cx - 2, cy, cx + 2, cy, cur.pending_color)
        line(cx, cy - 2, cx, cy + 2, cur.pending_color)
      end
    elseif cur.control_state == 1 then
      local temp_piece = {
        owner = (player and player.ghost_colors and player.ghost_colors[i]) or 7,
        type = cur.pending_type,
        position = { x = cur.x + 4, y = cur.y + 4 },
        orientation = cur.pending_orientation
      }
      local vertices = get_piece_draw_vertices(temp_piece)
      if vertices then
        if temp_piece.type == "attacker" then
          line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, cur.pending_color)
          line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, cur.pending_color)
          line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, cur.pending_color)
        else
          line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, cur.pending_color)
          line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, cur.pending_color)
          line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, cur.pending_color)
          line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, cur.pending_color)
        end
      end
    end
  end

  local margin = 2
  local font_width = 4
  local font_height = 5
  print(scores[1], margin, margin, (player and player.colors and player.colors[1]) or 7)
  local s2_txt = tostring(scores[2])
  print(s2_txt, 128 - margin - #s2_txt * font_width, margin, (player and player.colors and player.colors[2]) or 8)
  print(scores[3], margin, 128 - margin - font_height, (player and player.colors and player.colors[3]) or 9)
  local s4_txt = tostring(scores[4])
  print(s4_txt, 128 - margin - #s4_txt * font_width, 128 - margin - font_height, (player and player.colors and player.colors[4]) or 10)
end
-->8
-- SECTION 4: Placement Module
function legal_placement(piece) -- Made global by removing 'local'
  -- Dimensions are now sourced from global vars used by get_piece_draw_vertices
  local bw,bh=128,128 
  local function vec_sub(a,b) return {x=a.x-b.x, y=a.y-b.y} end
  local function vec_dot(a,b) return a.x*b.x+a.y*b.y end

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
  local corners=get_piece_draw_vertices(piece) -- Use global helper
  for c in all(corners) do
    if c.x<0 or c.x>bw or c.y<0 or c.y>bh then return false end
  end

  -- 2. collision
  local piece_corners = get_piece_draw_vertices(piece) -- Use global helper
  if pieces then
    for _, ep in ipairs(pieces) do -- Use ipairs for dense, 1-indexed array
      local ep_corners = get_piece_draw_vertices(ep) -- Use global helper
      
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
          local defender_corners = get_piece_draw_vertices(ep_val) -- Use global helper
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
-->8
-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.

-- Constants for control states (optional)
local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2        -- pixels per frame; adjust as needed
  local rotation_speed = 0.02   -- rotation amount per frame; adjust

  -- Iterate through each player's cursor in the global 'cursors' table.
  for i, cur in ipairs(cursors) do
    -- Pico-8 controller index is (i - 1).
    if cur.control_state == CSTATE_MOVE_SELECT then
      -- Continuous movement with the d-pad.
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      -- Cycle piece/action type (using Button O)
      if btnp(🅾️, i - 1) then
        if cur.pending_type == "defender" then
          cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
          cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
          cur.pending_type = "defender"
        end
      end

      -- Initiate placement/rotation with Button X.
      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          -- (Capture logic placeholder)
        else
          cur.control_state = CSTATE_ROTATE_PLACE
          cur.pending_orientation = 0 -- Reset orientation when starting placement
        end
      end

    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      -- Rotate pending piece using d-pad.
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end

      -- Confirm placement with Button X.
      if btnp(❎, i - 1) then
        local piece_to_place = {
          owner = (player and player.colors and player.colors[i]) or 7,
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
        }
        place_piece(piece_to_place)
        cur.control_state = CSTATE_COOLDOWN
        cur.return_cooldown = 6  -- 6-frame cooldown after placement
      end

      -- Cancel placement with Button O.
      if btnp(🅾️, i - 1) then
        cur.control_state = CSTATE_MOVE_SELECT
      end

    elseif cur.control_state == CSTATE_COOLDOWN then
      -- Decrement cooldown timer and snap cursor back to spawn when done.
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = CSTATE_MOVE_SELECT
        cur.pending_orientation = 0
        cur.pending_type = "defender"
        cur.pending_color = (player and player.ghost_colors and player.ghost_colors[i]) or 7
      end
    end
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

