---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry

-- Initialize core global tables BEFORE includes that might use them
player_manager = {} -- Must be defined before 4.player.lua is included
pieces = {}         -- Must be defined before 5.piece.lua (if it uses global pieces during load)

--#include src/4.player.lua
--#include src/5.piece.lua
--#globals player_manager create_piece pieces LASER_LEN ray_segment_intersect
--#globals player_manager,create_piece,LASER_LEN,pieces,ray_segment_intersect
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
    local p_obj = player_manager.get_player(i)
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
  local temp_piece_obj = create_piece(piece_params)
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
    for _, ep_obj in ipairs(pieces) do 
      if ep_obj.type == "defender" then
        local def_corners = ep_obj:get_draw_vertices() -- Use method
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = ray_segment_intersect( -- Use direct call
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

function place_piece(piece_params, player_obj)
  -- piece_params is the table: {owner_id, type, position, orientation}
  if legal_placement(piece_params) then
    local piece_color_to_place = player_obj:get_color()
    if player_obj:use_piece_from_stash(piece_color_to_place) then
      local new_piece_obj = create_piece(piece_params)
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
            local k_idx = (j % #defender_corners) + 1
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, 
                                                     defender_corners[j].x, defender_corners[j].y,
                                                     defender_corners[k_idx].x, defender_corners[k_idx].y)
            if t and t >= 0 and t <= LASER_LEN then 
              defender_obj.hits = (defender_obj.hits or 0) + 1
              defender_obj.targeting_attackers = defender_obj.targeting_attackers or {} -- Ensure initialization
              add(defender_obj.targeting_attackers, attacker_obj)
              
              local attacker_player = player_manager.get_player(attacker_obj.owner_id)
              local defender_player = player_manager.get_player(defender_obj.owner_id)

              if defender_obj.hits == 2 then
                defender_obj.state = "unsuccessful"
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  attacker_player:add_score(1) -- Use player object to add score
                  attacker_obj.is_currently_scoring = true -- Mark attacker as scoring
                end
              elseif defender_obj.hits == 3 then
                defender_obj.state = "overcharged"
                if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
                  attacker_player:add_score(1) -- Use player object to add score
                  attacker_obj.is_currently_scoring = true -- Mark attacker as scoring
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
    local current_player_obj = player_manager.get_player(i)
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
    elseif p_item.type == "attacker" then
      p_item.is_currently_scoring = false -- Reset scoring flag for attackers
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
    local current_player_obj = player_manager.get_player(i)
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
      local ghost_piece_obj = create_piece(ghost_params)
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

  for i=1, player_manager.get_player_count() do
    local p_obj = player_manager.get_player(i)
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
