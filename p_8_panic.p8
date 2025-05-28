pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- p8panic - A game of tactical geometry
--#include src/4.player.lua
--#include src/5.piece.lua

-------------------------------------------
-- Helpers & Global Constants/Variables --
-------------------------------------------
CAPTURE_RADIUS_SQUARED = 64 -- (8*8) For capture proximity check

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
-- scores = {0, 0, 0, 0}   -- Scores for up to 4 players -- Handled by player_manager
LASER_LEN = 60          -- Maximum laser beam length

-- Piece dimensions / drawing config -- These will be primarily used in 5.piece.lua
-- local defender_width = 8
-- local defender_height = 8
-- local attacker_triangle_height = 8 -- along orientation axis
-- local attacker_triangle_base = 6   -- perpendicular

-- Cached math functions
local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

-------------------------------------------
-- Player Configuration --
-------------------------------------------
-- player = { -- Handled by player_manager
--   colors = {12, 4, 11, 10},      -- Colors for placed pieces
--   ghost_colors = {1, 8, 3, 9}      -- Colors for ghost cursors
-- }

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
    local p_obj = _G.player_manager.get_player(i) -- Use _G.player_manager
    cursors[i] = {
      x = sp.x, y = sp.y,
      spawn_x = sp.x, spawn_y = sp.y,
      control_state = 0,       -- 0: Movement/Selection, 1: Rotation/Placement, 2: Cooldown/Return
      pending_type = "defender",  -- "defender", "attacker", "capture"
      -- Use ghost color for cursor, placed pieces will use player.colors in controls below.
      pending_color = (p_obj and p_obj:get_ghost_color()) or 7,
      pending_orientation = 0,
      return_cooldown = 0
    }
  end
end

-- init_cursors(4) -- Called by player_manager.init_players
_G.player_manager.init_players(4) -- This will also call init_cursors. Use _G.player_manager

------------------------------------------
-- Piece Drawing & Helper Functions        --
-------------------------------------------
-- function get_piece_draw_vertices(piece) -- Moved to Piece class in 5.piece.lua
--   local o = piece.orientation
--   local cx = piece.position.x
--   local cy = piece.position.y
--   local local_corners = {}

--   if piece.type == "attacker" then
--     local h = attacker_triangle_height
--     local b = attacker_triangle_base
--     add(local_corners, {x = h/2, y = 0})      -- Apex
--     add(local_corners, {x = -h/2, y = b/2})     -- Base corner 1
--     add(local_corners, {x = -h/2, y = -b/2})    -- Base corner 2
--   else
--     local w, h = defender_width, defender_height
--     local hw = w / 2
--     local hh = h / 2
--     add(local_corners, {x = -hw, y = -hh})
--     add(local_corners, {x = hw, y = -hh})
--     add(local_corners, {x = hw, y = hh})
--     add(local_corners, {x = -hw, y = hh})
--   end

--   local world_corners = {}
--   for lc in all(local_corners) do
--     local rotated_x = lc.x * cos(o) - lc.y * sin(o)
--     local rotated_y = lc.x * sin(o) + lc.y * cos(o)
--     add(world_corners, {x = cx + rotated_x, y = cy + rotated_y})
--   end
--   return world_corners
-- end

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
function legal_placement(piece_params)
  local bw, bh = 128, 128

  -- Create a temporary piece object to use its get_draw_vertices method
  local temp_piece_obj = _G.create_piece(piece_params) -- Use _G.create_piece
  if not temp_piece_obj then return false end -- Failed to create for some reason

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

  local corners = temp_piece_obj:get_draw_vertices() -- Use method from temp object
  for c in all(corners) do
    if c.x < 0 or c.x > bw or c.y < 0 or c.y > bh then return false end
  end

  for _, ep_obj in ipairs(pieces) do -- ep_obj is now an object
    local ep_corners = ep_obj:get_draw_vertices() -- Use method
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
  if piece_params.type == "attacker" then
    -- `corners` are from temp_piece_obj, which is based on piece_params
    local apex = corners[1]
    local dir_x = cos(piece_params.orientation)
    local dir_y = sin(piece_params.orientation)
    local laser_hits_defender = false
    for _, ep_obj in ipairs(pieces) do -- ep_obj is an object
      if ep_obj.type == "defender" then
        local def_corners = ep_obj:get_draw_vertices() -- Use method
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = ray_segment_intersect( -- Use direct call
            apex.x, apex.y, dir_x, dir_y,
            def_corners[j].x, def_corners[j].y, def_corners[k].x, def_corners[k].y
          )
          if t and t >= 0 and t <= LASER_LEN then -- Use direct global
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

function place_piece(piece_params, player_obj)
  -- piece_params is the table: {owner_id, type, position, orientation}
  if legal_placement(piece_params) then
    local piece_color_to_place = player_obj:get_color()
    if player_obj:use_piece_from_stash(piece_color_to_place) then
      local new_piece_obj = _G.create_piece(piece_params) -- Use _G.create_piece
      if new_piece_obj then
        -- Defender specific properties are set in Defender:new now
        -- if new_piece_obj.type == "defender" then
        --   new_piece_obj.hits = 0
        --   new_piece_obj.state = "neutral"
        --   new_piece_obj.targeting_attackers = {}
        -- end
        add(pieces, new_piece_obj)
        return true -- Piece placed successfully
      else
        printh("Failed to create piece object.")
        player_obj:add_captured_piece(piece_color_to_place) -- Return piece to stash if object creation failed
        return false
      end
    else
      printh("Player " .. player_obj.id .. " has no " .. piece_color_to_place .. " pieces.")
      return false -- Piece not placed (no stash)
    end
  end
  return false -- Illegal placement
end

-------------------------------------------
-- Scoring Module (from 2.scoring.lua)    --
-------------------------------------------
function score_attackers()
  for _, attacker_obj in ipairs(pieces) do
    if attacker_obj and attacker_obj.type == "attacker" then
      local attacker_vertices = attacker_obj:get_draw_vertices()
      if not attacker_vertices or #attacker_vertices == 0 then goto next_attacker end -- luacheck: ignore
      local apex = attacker_vertices[1]
      local dir_x = cos(attacker_obj.orientation)
      local dir_y = sin(attacker_obj.orientation)
      
      for _, defender_obj in ipairs(pieces) do
        if defender_obj and defender_obj.type == "defender" then
          local defender_corners = defender_obj:get_draw_vertices()
          if not defender_corners or #defender_corners == 0 then goto next_defender end -- luacheck: ignore
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, -- Use direct call
                                                     defender_corners[j].x, defender_corners[j].y,
                                                     defender_corners[k].x, defender_corners[k].y)
            if t and t >= 0 and t <= LASER_LEN then -- Use direct global
              defender_obj.hits = (defender_obj.hits or 0) + 1
              defender_obj.targeting_attackers = defender_obj.targeting_attackers or {}
              add(defender_obj.targeting_attackers, attacker_obj)
              
              local attacker_player = _G.player_manager.get_player(attacker_obj.owner_id) -- Use _G.player_manager
              local defender_player = _G.player_manager.get_player(defender_obj.owner_id) -- Use _G.player_manager

              if defender_obj.hits == 2 then
                defender_obj.state = "unsuccessful"
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  attacker_player:add_score(1)
                end
              elseif defender_obj.hits == 3 then
                defender_obj.state = "overcharged"
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  attacker_player:add_score(1)
                  local captured_piece_color = defender_player:get_color()
                  attacker_player:add_captured_piece(captured_piece_color)
                  defender_obj.captured = true 
                end
              elseif defender_obj.hits == 1 then
                defender_obj.state = "neutral"
              end
              break
            end
          end
        end
        ::next_defender:: -- luacheck: ignore
      end
    end
    ::next_attacker:: -- luacheck: ignore
  end

  -- Remove captured pieces
  local remaining_pieces = {}
  for _,p_obj in ipairs(pieces) do
    if not p_obj.captured then
      add(remaining_pieces, p_obj)
    end
  end
  pieces = remaining_pieces
end

-------------------------------------------
-- Controls Module (from 3.controls.lua)  --
-------------------------------------------

-- Helper function for capture logic
function attempt_capture(player_obj, cursor)
  local player_id = player_obj.id

  for _, def_obj in ipairs(pieces) do
    if def_obj.type == "defender" and def_obj.owner_id == player_id and def_obj.state == "overcharged" then
      -- This player owns this overcharged defender
      if def_obj.targeting_attackers then
        for _, attacker_to_capture in ipairs(def_obj.targeting_attackers) do
          -- Check proximity of cursor to this attacker
          -- Cursor position (cur.x, cur.y) is top-left, center is (cur.x+4, cur.y+4)
          local dist_x = (cursor.x + 4) - attacker_to_capture.position.x
          local dist_y = (cursor.y + 4) - attacker_to_capture.position.y
          
          if (dist_x*dist_x + dist_y*dist_y) < CAPTURE_RADIUS_SQUARED then
            -- Found attacker to capture!
            local captured_color = attacker_to_capture:get_color()
            player_obj:add_captured_piece(captured_color)
            
            -- Remove attacker_to_capture from global pieces
            local new_pieces_table = {}
            local captured_this_one = false
            for _, p_obj_global in ipairs(pieces) do
              if p_obj_global == attacker_to_capture and not captured_this_one then
                captured_this_one = true -- Ensure we only "remove" it once if it somehow appears multiple times
                printh("P" .. player_id .. " captured a piece (color: " .. captured_color .. ")")
              else
                add(new_pieces_table, p_obj_global)
              end
            end
            pieces = new_pieces_table -- Replace global pieces table
            
            return true -- Capture successful
          end
        end
      end
    end
  end
  return false -- No capture occurred
end

function update_controls()
  local cursor_speed = 2
  local rotation_speed = 0.02
  for i, cur in ipairs(cursors) do
    local current_player_obj = _G.player_manager.get_player(i) -- Use _G.player_manager
    if not current_player_obj then goto next_cursor end -- Skip if player object not found

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
        -- If in capture mode, try to capture
        if cur.pending_type == "capture" then
          -- printh("Capture mode selected for P" .. i .. ". Capture logic TBD.")
          local capture_success = attempt_capture(current_player_obj, cur)
          if capture_success then
            cur.control_state = 2 -- Go to cooldown/return state
            cur.return_cooldown = 6  -- 6 frames cooldown
            update_game_logic() -- Recalculate states immediately
          else
            printh("P" .. i .. ": Capture failed. No valid target.")
          end
        else
          -- If not in capture mode, switch to rotation/placement state
          cur.control_state = 1
          cur.pending_orientation = 0
        end
      end

    elseif cur.control_state == 1 then -- Rotation/Placement state
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end
      if btnp(❎, i - 1) then -- Attempt to place piece
        local piece_params = {
          owner_id = i, -- Store player ID
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
        }
        
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = 2 -- Go to cooldown/return state
          cur.return_cooldown = 6  -- 6 frames cooldown
        else
          -- Optional: Feedback if placement failed (e.g. out of pieces, or illegal)
          -- If it failed due to no pieces, player might want to stay in placement mode
          -- or switch back to movement. For now, let's keep them in placement mode.
          printh("Placement failed for P" .. i)
        end
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
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor:: -- luacheck: ignore
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
  -- Draw all placed pieces using their draw methods
  -- The Attacker:draw method now handles its own laser drawing.
  -- 'pieces' is already a global table.
  for _, piece_obj in ipairs(pieces) do
    if piece_obj and piece_obj.draw then
      piece_obj:draw() -- This will call Attacker:draw() or Defender:draw()
    end
  end
  
  -- Draw cursors and ghost pieces
  for i, cur in ipairs(cursors) do
    local current_player_obj = _G.player_manager.get_player(i) -- Get player for ghost color. Use _G.player_manager
    if cur.control_state == 0 or cur.control_state == 2 then -- Standard cursor shapes
      local cursor_draw_color = (current_player_obj and current_player_obj:get_ghost_color()) or cur.pending_color
      if cur.pending_type == "defender" then
        rect(cur.x, cur.y, cur.x + 7, cur.y + 7, cursor_draw_color)
      elseif cur.pending_type == "attacker" then
        local cx, cy = cur.x + 4, cur.y + 4
        line(cx + 4, cy, cx - 2, cy - 3, cursor_draw_color)
        line(cx - 2, cy - 3, cx - 2, cy + 3, cursor_draw_color)
        line(cx - 2, cy + 3, cx + 4, cy, cursor_draw_color)
      elseif cur.pending_type == "capture" then
        local cx, cy = cur.x + 4, cur.y + 4
        line(cx - 2, cy, cx + 2, cy, cursor_draw_color)
        line(cx, cy - 2, cx, cy + 2, cursor_draw_color)
      end
    elseif cur.control_state == 1 then -- Ghost piece for placement
      local ghost_params = {
        owner_id = i, 
        type = cur.pending_type,
        position = { x = cur.x + 4, y = cur.y + 4 },
        orientation = cur.pending_orientation
      }
      local ghost_piece_obj = _G.create_piece(ghost_params) -- Use _G.create_piece
      if ghost_piece_obj then
        -- We need a way for the ghost piece to draw with the cursor's pending_color
        -- This will be handled by modifying Piece:draw or Piece:get_color in 5.piece.lua
        ghost_piece_obj.is_ghost = true -- Mark it as ghost
        ghost_piece_obj.ghost_color_override = cur.pending_color -- Store the color
        ghost_piece_obj:draw()
      end
    end
  end

  local margin = 2
  local font_width = 4
  local font_height = 5

  for i=1, _G.player_manager.get_player_count() do -- Use _G.player_manager
    local p_obj = _G.player_manager.get_player(i) -- Use _G.player_manager
    if p_obj then
      local score_txt = p_obj:get_score() .. "" -- Pico-8 tostring
      local p_color = p_obj:get_color()
      if i == 1 then
        print(score_txt, margin, margin, p_color)
      elseif i == 2 then
        print(score_txt, 128 - margin - #score_txt * font_width, margin, p_color)
      elseif i == 3 then
        print(score_txt, margin, 128 - margin - font_height, p_color)
      elseif i == 4 then
        print(score_txt, 128 - margin - #score_txt * font_width, 128 - margin - font_height, p_color)
      end
    end
  end
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
-->8
-- src/4.player.lua

local Player = {}
Player.__index = Player -- For metatable inheritance

-- Constructor for a new player object
function Player:new(id, initial_score, color, ghost_color) -- Added initial_score
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {} -- Initialize stash as an empty table
  }
  -- Initialize stash with 6 pieces of the player's own color
  instance.stash[color] = 6 
  setmetatable(instance, self)
  self.__index = self
  return instance
end

-- Method to get player's score (example of a method)
function Player:get_score()
  return self.score
end

-- Method to increment player's score (example of a method)
function Player:add_score(points)
  self.score = self.score + (points or 1)
end

-- Method to get player's color
function Player:get_color()
  return self.color
end

-- Method to get player's ghost color
function Player:get_ghost_color()
  return self.ghost_color
end

-- Method to add a captured piece to the stash
function Player:add_captured_piece(piece_color)
  if self.stash[piece_color] == nil then
    self.stash[piece_color] = 0
  end
  self.stash[piece_color] += 1
end

-- Method to get the count of captured pieces of a specific color
function Player:get_captured_count(piece_color)
  return self.stash[piece_color] or 0
end

-- Method to check if a player has a piece of a certain color in their stash
function Player:has_piece_in_stash(piece_color)
  return (self.stash[piece_color] or 0) > 0
end

-- Method to use a piece from the stash
-- Returns true if successful, false otherwise
function Player:use_piece_from_stash(piece_color)
  if self:has_piece_in_stash(piece_color) then
    self.stash[piece_color] = self.stash[piece_color] - 1
    return true
  end
  return false
end

-- Module-level table to hold player-related functions and data
local player_manager = {}

player_manager.colors = { -- Changed : to .
  [1] = 12, -- Player 1: Light Blue
  [2] = 8,  -- Player 2: Red (Pico-8 color 8 is red)
  [3] = 11, -- Player 3: Green
  [4] = 10  -- Player 4: Yellow
}

-- Ghost/Cursor colors
player_manager.ghost_colors = { -- Added ghost_colors table
  [1] = 1,  -- Player 1: Dark Blue (Pico-8 color 1)
  [2] = 9,  -- Player 2: Orange (Pico-8 color 9)
  [3] = 3,  -- Player 3: Dark Green (Pico-8 color 3)
  [4] = 4   -- Player 4: Brown (Pico-8 color 4)
}

player_manager.max_players = 4
player_manager.current_players = {} -- Table to hold active player instances

-- Function to initialize players at the start of a game
function player_manager.init_players(num_players)
  if num_players < 1 or num_players > player_manager.max_players then
    printh("Error: Invalid number of players. Must be between 1 and " .. player_manager.max_players)
    return
  end

  player_manager.current_players = {} -- Reset current players

  for i = 1, num_players do
    local color = player_manager.colors[i]
    local ghost_color = player_manager.ghost_colors[i] -- Get ghost_color
    if not color then
      printh("Warning: No color defined for player " .. i .. ". Defaulting to white (7).")
      color = 7 -- Default to white if color not found
    end
    if not ghost_color then -- Check for ghost_color
      printh("Warning: No ghost color defined for player " .. i .. ". Defaulting to dark blue (1).")
      ghost_color = 1 -- Default ghost_color
    end
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color) -- Pass ghost_color to constructor
  end
  
  printh("Initialized " .. num_players .. " players.")
end

-- Function to get a player's instance
function player_manager.get_player(player_id)
  return player_manager.current_players[player_id]
end

-- Function to get a player's color (can still be useful as a direct utility)
function player_manager.get_player_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_color()
  else
    return 7 -- Default to white if player not found, or handle error
  end
end

-- Function to get a player's ghost color
function player_manager.get_player_ghost_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_ghost_color()
  else
    return 1 -- Default to dark blue if player not found
  end
end

-- Example Usage (for testing within this file, remove or comment out for production)
-- player_manager.init_players(2)
-- local p1 = player_manager.get_player(1)
-- if p1 then
--   printh("Player 1 ID: " .. p1.id)
--   printh("Player 1 Color: " .. p1:get_color())
--   printh("Player 1 Ghost Color: " .. p1:get_ghost_color()) -- Test ghost color
--   p1:add_score(10)
--   printh("Player 1 Score: " .. p1:get_score())
-- end

-- local p2_color = player_manager.get_player_color(2)
-- printh("Player 2 Color (direct): " .. (p2_color or "not found"))
-- local p2_ghost_color = player_manager.get_player_ghost_color(2)
-- printh("Player 2 Ghost Color (direct): " .. (p2_ghost_color or "not found"))


-- return player_manager -- Old return statement
_G.player_manager = player_manager -- Make player_manager globally accessible
-->8
-- src/5.piece.lua

-- Forward declarations for metatables if needed
local Piece = {}
Piece.__index = Piece

local Attacker = {}
Attacker.__index = Attacker
setmetatable(Attacker, {__index = Piece}) -- Inherit from Piece

local Defender = {}
Defender.__index = Defender
setmetatable(Defender, {__index = Piece}) -- Inherit from Piece

-- Piece constants (can be moved from 0.init.lua)
local DEFENDER_WIDTH = 8
local DEFENDER_HEIGHT = 8
local ATTACKER_TRIANGLE_HEIGHT = 8
local ATTACKER_TRIANGLE_BASE = 6
local LASER_LEN = 60 -- Assuming this is a piece property or accessed during drawing

-- Cached math functions
local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

-- Base Piece methods
function Piece:new(o)
  o = o or {}
  -- Common properties: position, orientation, owner_id, type
  o.position = o.position or {x=64, y=64} -- Default position
  o.orientation = o.orientation or 0
  -- o.owner_id should be provided
  -- o.type should be set by subclasses or factory
  setmetatable(o, self) -- Set metatable after o is populated
  return o
end

function Piece:get_color()
  if self.is_ghost and self.ghost_color_override then
    return self.ghost_color_override
  end
  if self.owner_id then
    local owner_player = _G.player_manager.get_player(self.owner_id) -- Use _G.player_manager
    if owner_player then
      return owner_player:get_color()
    end
  end
  return 7 -- Default color (white)
end

function Piece:get_draw_vertices()
  local o = self.orientation
  local cx = self.position.x
  local cy = self.position.y
  local local_corners = {}

  if self.type == "attacker" then
    local h = ATTACKER_TRIANGLE_HEIGHT
    local b = ATTACKER_TRIANGLE_BASE
    add(local_corners, {x = h/2, y = 0})      -- Apex
    add(local_corners, {x = -h/2, y = b/2})     -- Base corner 1
    add(local_corners, {x = -h/2, y = -b/2})    -- Base corner 2
  else -- defender
    local w, h = DEFENDER_WIDTH, DEFENDER_HEIGHT
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

function Piece:draw()
  -- Basic draw, to be overridden by Attacker/Defender
  local vertices = self:get_draw_vertices()
  local color = self:get_color()
  if #vertices >= 3 then
    for i=1,#vertices do
      local v1 = vertices[i]
      local v2 = vertices[(i % #vertices) + 1]
      line(v1.x, v1.y, v2.x, v2.y, color)
    end
  end
end

-- Attacker methods
function Attacker:new(o)
  o = o or {}
  o.type = "attacker"
  -- Attacker-specific initializations
  return Piece.new(self, o) -- Call base constructor
end

function Attacker:draw()
  -- First, draw the attacker triangle itself
  Piece.draw(self) -- Call base Piece:draw to draw the triangle shape

  -- Now, draw the laser
  local vertices = self:get_draw_vertices()
  if not vertices or #vertices == 0 then return end
  local apex = vertices[1] -- Assuming apex is the first vertex for attacker

  local dir_x = cos(self.orientation)
  local dir_y = sin(self.orientation)
  local laser_color = self:get_color() -- Default laser color
  local laser_end_x = apex.x + dir_x * _G.LASER_LEN -- Use _G.LASER_LEN
  local laser_end_y = apex.y + dir_y * _G.LASER_LEN -- Use _G.LASER_LEN
  local closest_hit_t = _G.LASER_LEN -- Use _G.LASER_LEN

  local hit_defender_state = nil

  -- Check for intersections with all defenders
  if _G.pieces then -- Use _G.pieces
    for _, other_piece in ipairs(_G.pieces) do -- Use _G.pieces
      if other_piece.type == "defender" then
        local def_corners = other_piece:get_draw_vertices()
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = _G.ray_segment_intersect( -- Use _G.ray_segment_intersect
            apex.x, apex.y, dir_x, dir_y,
            def_corners[j].x, def_corners[j].y, def_corners[k].x, def_corners[k].y
          )
          if t and t >= 0 and t < closest_hit_t then
            closest_hit_t = t
            laser_end_x = ix
            laser_end_y = iy
            hit_defender_state = other_piece.state -- Store the state of the hit defender
          end
        end
      end
    end
  end

  -- Adjust laser color based on hit defender's state
  if hit_defender_state == "unsuccessful" then
    laser_color = 8 -- Red for unsuccessful
  elseif hit_defender_state == "overcharged" then
    laser_color = 10 -- Yellow for overcharged
  end

  -- "Dancing ants" animation for the laser beam
  local ant_spacing = 4
  local ant_length = 2
  local num_ants = flr(closest_hit_t / ant_spacing)
  local time_factor = time() * 20 -- Adjust speed of ants

  for i = 0, num_ants - 1 do
    local ant_start_t = (i * ant_spacing + time_factor) % closest_hit_t
    local ant_end_t = ant_start_t + ant_length
    
    if ant_end_t <= closest_hit_t then
      local ant_start_x = apex.x + dir_x * ant_start_t
      local ant_start_y = apex.y + dir_y * ant_start_t
      local ant_end_x = apex.x + dir_x * ant_end_t
      local ant_end_y = apex.y + dir_y * ant_end_t
      line(ant_start_x, ant_start_y, ant_end_x, ant_end_y, laser_color)
    else -- Handle ant wrapping around the end of the laser segment
      local segment1_end_t = closest_hit_t
      local segment1_start_x = apex.x + dir_x * ant_start_t
      local segment1_start_y = apex.y + dir_y * ant_start_t
      local segment1_end_x = apex.x + dir_x * segment1_end_t
      local segment1_end_y = apex.y + dir_y * segment1_end_t
      line(segment1_start_x, segment1_start_y, segment1_end_x, segment1_end_y, laser_color)
      
      local segment2_len = ant_end_t - closest_hit_t
      if segment2_len > 0 then -- only draw if there's a remainder
        local segment2_start_x = apex.x
        local segment2_start_y = apex.y
        local segment2_end_x = apex.x + dir_x * segment2_len
        local segment2_end_y = apex.y + dir_y * segment2_len
        line(segment2_start_x, segment2_start_y, segment2_end_x, segment2_end_y, laser_color)
      end
    end
  end
end

-- Defender methods
function Defender:new(o)
  o = o or {}
  o.type = "defender"
  o.hits = 0
  o.state = "neutral" -- "neutral", "unsuccessful", "overcharged"
  o.targeting_attackers = {}
  return Piece.new(self, o) -- Call base constructor
end

function Defender:draw()
  local vertices = self:get_draw_vertices()
  local color = self:get_color()
  -- Defenders always draw in their owner's color
  if #vertices == 4 then
    line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, color)
    line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, color)
    line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, color)
    line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, color)
  end
end

-- Factory function to create pieces
-- Global `pieces` table will be needed for laser interactions in Attacker:draw
-- It might be passed to Attacker:draw or accessed globally if available.
function create_piece(params) -- `params` should include owner_id, type, position, orientation
  local piece_obj
  if params.type == "attacker" then
    piece_obj = Attacker:new(params)
  elseif params.type == "defender" then
    piece_obj = Defender:new(params)
  else
    printh("Error: Unknown piece type: " .. (params.type or "nil"))
    return nil
  end
  return piece_obj
end

-- The return statement makes these functions/tables available when this file is included.
-- We might not need to return Piece, Attacker, Defender if only create_piece is used externally.
_G.create_piece = create_piece -- Make create_piece globally accessible
-- Or, more structured:
-- return {
--   create_piece = create_piece
-- }
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

