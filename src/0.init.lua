---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry
--#include src/4.player.lua
--#include src/5.piece.lua
--#globals player_manager create_piece pieces LASER_LEN ray_segment_intersect N_PLAYERS
--#globals player_manager,create_piece,LASER_LEN,pieces,ray_segment_intersect,N_PLAYERS

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
N_PLAYERS = 4           -- Default number of players
LASER_LEN = 60          -- Maximum laser beam length

-- Cached math functions
local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

-------------------------------------------
-- Multi-Cursor Support (one per player) --
-------------------------------------------
cursors = {}

-- Initialize cursors for N players; they spawn in different screen corners.
function init_cursors(num_players)
  local all_possible_spawn_points = {
    {x = 4, y = 4},                -- P1: top-left
    {x = 128 - 12, y = 4},           -- P2: top-right
    {x = 4, y = 128 - 12},            -- P3: bottom-left
    {x = 128 - 12, y = 128 - 12}     -- P4: bottom-right
  }

  cursors = {} -- Clear existing cursors before re-initializing

  for i = 1, num_players do
    local sp
    if i <= #all_possible_spawn_points then
      sp = all_possible_spawn_points[i]
    else
      printh("Warning: No spawn point defined for P" .. i .. ". Defaulting.")
      sp = {x = 4 + (i-1)*10, y = 4} -- Simple fallback
    end

    local p_obj = player_manager.get_player(i)
    cursors[i] = {
      x = sp.x, y = sp.y,
      spawn_x = sp.x, spawn_y = sp.y,
      control_state = 0,       -- 0: Movement/Selection, 1: Rotation/Placement, 2: Cooldown/Return
      pending_type = "defender",  -- "defender", "attacker", "capture"
      pending_color = (p_obj and p_obj:get_ghost_color()) or 7,
      pending_orientation = 0,
      return_cooldown = 0
    }
  end
end

-- Game States
GAME_STATE_MENU = 0
GAME_STATE_PLAYING = 1
-- GAME_STATE_GAME_OVER = 2 -- Placeholder for future

current_game_state = GAME_STATE_MENU -- Start in the menu

-- Forward declare for state-specific update/draw functions
local original_update_game_logic_func
local original_update_controls_func

function go_to_state(new_state)
  if new_state == GAME_STATE_PLAYING and current_game_state ~= GAME_STATE_PLAYING then
    pieces = {} -- Clear existing pieces
    init_cursors(player_manager.get_player_count()) -- Cursors are initialized on game start
    
    for i=1, player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p then 
        p.score = 0
        p.stash = {} 
        p.stash[p:get_color()] = 6 
      end
    end
    if original_update_game_logic_func then original_update_game_logic_func() end
  end
  current_game_state = new_state
end

------------------------------------------
-- Piece Drawing & Helper Functions        --
-------------------------------------------
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
-- Placement Module --
-------------------------------------------
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
        -- Basic AABB check as a fallback for degenerate cases or if get_axes returns empty
        local min_x1, max_x1, min_y1, max_y1 = bw, 0, bh, 0
        for c in all(corners) do min_x1=min(min_x1,c.x) max_x1=max(max_x1,c.x) min_y1=min(min_y1,c.y) max_y1=max(max_y1,c.y) end
        local min_x2, max_x2, min_y2, max_y2 = bw, 0, bh, 0
        for c in all(ep_corners) do min_x2=min(min_x2,c.x) max_x2=max(max_x2,c.x) min_y2=min(min_y2,c.y) max_y2=max(max_y2,c.y) end
        if not (max_x1 < min_x2 or max_x2 < min_x1 or max_y1 < min_y2 or max_y2 < min_y1) then
            return false -- AABB overlap, assume collision for safety
        end
        goto next_ep_check -- No separating axis from SAT, but AABB says no overlap
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
    local piece_color_to_place = player_obj:get_color() -- This is the color of the player, not a specific piece type color
    
    -- Check if player has a piece of their own color to place
    if player_obj:use_piece_from_stash(piece_color_to_place) then
      local new_piece_obj = create_piece(piece_params)
      if new_piece_obj then
        add(pieces, new_piece_obj)
        return true
      else
        printh("Failed to create piece object.")
        player_obj:add_captured_piece(piece_color_to_place) -- Return piece to stash
        return false
      end
    else
      printh("P" .. player_obj.id .. " has no more of their own pieces.")
      return false
    end
  end
  return false
end

-------------------------------------------
-- Scoring Module --
-------------------------------------------
function internal_score_attackers()
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

-------------------------------------------
-- Controls Module --
-------------------------------------------
function attempt_capture(player_obj, cursor)
  local player_id = player_obj.id
  for _, def_obj in ipairs(pieces) do
    if def_obj.type == "defender" and def_obj.owner_id == player_id and def_obj.state == "overcharged" then
      if def_obj.targeting_attackers then
        for attacker_idx = #def_obj.targeting_attackers, 1, -1 do -- Iterate backwards for safe removal
          local attacker_to_capture = def_obj.targeting_attackers[attacker_idx]
          if attacker_to_capture then -- Ensure attacker still exists
            local dist_x = (cursor.x + 4) - attacker_to_capture.position.x
            local dist_y = (cursor.y + 4) - attacker_to_capture.position.y
            
            if (dist_x*dist_x + dist_y*dist_y) < CAPTURE_RADIUS_SQUARED then
              local captured_color = attacker_to_capture:get_color()
              player_obj:add_captured_piece(captured_color)
              
              if del(pieces, attacker_to_capture) then -- Remove from global pieces
                printh("P" .. player_id .. " captured attacker (color: " .. captured_color .. ")")
                -- Also remove from this defender's targeting list
                deli(def_obj.targeting_attackers, attacker_idx) 
                return true 
              end
            end
          end
        end
      end
    end
  end
  return false
end

function internal_update_controls()
  local cursor_speed = 2
  local rotation_speed = 0.02
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)
    if not current_player_obj then goto next_cursor_ctrl end

    if cur.control_state == 0 then -- Movement/Selection
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      if btnp(🅾️, i - 1) then
        if cur.pending_type == "defender" then cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then cur.pending_type = "defender"
        end
      end

      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = 2; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate immediately
          else
            printh("P" .. i .. ": Capture failed.")
          end
        else
          cur.control_state = 1; cur.pending_orientation = 0
        end
      end

    elseif cur.control_state == 1 then -- Rotation/Placement
      if btn(⬅️, i - 1) then cur.pending_orientation = (cur.pending_orientation - rotation_speed + 1) % 1 end
      if btn(➡️, i - 1) then cur.pending_orientation = (cur.pending_orientation + rotation_speed) % 1 end
      
      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i, type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
        }
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = 2; cur.return_cooldown = 6
        else
          printh("Placement failed for P" .. i)
        end
      end
      if btnp(🅾️, i - 1) then cur.control_state = 0 end

    elseif cur.control_state == 2 then -- Cooldown
      cur.return_cooldown -= 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x; cur.y = cur.spawn_y
        cur.control_state = 0; cur.pending_orientation = 0
        cur.pending_type = "defender"
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end

-------------------------------------------
-- Game Logic & Main Loop Integration    --
-------------------------------------------
function internal_update_game_logic()
  for _, p_item in ipairs(pieces) do
    if p_item.type == "defender" then
      p_item.hits = 0
      p_item.targeting_attackers = {}
      p_item.state = "neutral"
      p_item.captured_flag = false -- Reset captured flag
    end
  end
  internal_score_attackers()
end

-- Assign to the forward-declared variables
original_update_game_logic_func = internal_update_game_logic
original_update_controls_func = internal_update_controls


function _init()
  player_manager.init_players(N_PLAYERS)
  -- Cursors and game pieces initialized by go_to_state(GAME_STATE_PLAYING)
  -- Start in menu state by default (current_game_state = GAME_STATE_MENU)
end

function update_menu_state()
  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_PLAYING)
  end
end

function update_playing_state()
  if original_update_controls_func then original_update_controls_func() end
  if original_update_game_logic_func then original_update_game_logic_func() end
end

function _update()
  if current_game_state == GAME_STATE_MENU then
    update_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    update_playing_state()
  end
end

function draw_menu_state()
  print("P8PANIC", 50, 50, 7)
  print("PRESS X OR O", 40, 70, 8)
  print("TO START", 50, 80, 8)
end

function draw_playing_state_elements()
  for _, piece_obj in ipairs(pieces) do
    if piece_obj and piece_obj.draw then
      piece_obj:draw()
    end
  end
  
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)
    if not current_player_obj then goto next_cursor_draw end -- Skip if no player object

    local cursor_draw_color = (current_player_obj and current_player_obj:get_ghost_color()) or cur.pending_color

    if cur.control_state == 0 or cur.control_state == 2 then
      if cur.pending_type == "defender" then
        rect(cur.x, cur.y, cur.x + 7, cur.y + 7, cursor_draw_color)
      elseif cur.pending_type == "attacker" then
        local cx, cy = cur.x + 4, cur.y + 4
        line(cx + 4, cy, cx - 2, cy - 3, cursor_draw_color)
        line(cx - 2, cy - 3, cx - 2, cy + 3, cursor_draw_color)
        line(cx - 2, cy + 3, cx + 4, cy, cursor_draw_color)
      elseif cur.pending_type == "capture" then
        local cx, cy = cur.x + 4, cur.y + 4
        circfill(cx,cy,3,cursor_draw_color) -- Changed capture cursor to a circle
        -- line(cx - 2, cy, cx + 2, cy, cursor_draw_color)
        -- line(cx, cy - 2, cx, cy + 2, cursor_draw_color)
      end
    elseif cur.control_state == 1 then
      local ghost_params = {
        owner_id = i, type = cur.pending_type,
        position = { x = cur.x + 4, y = cur.y + 4 },
        orientation = cur.pending_orientation
      }
      local ghost_piece_obj = create_piece(ghost_params)
      if ghost_piece_obj then
        ghost_piece_obj.is_ghost = true
        ghost_piece_obj.ghost_color_override = cursor_draw_color -- Use the calculated cursor_draw_color
        ghost_piece_obj:draw()
      end
    end
    ::next_cursor_draw::
  end

  local margin = 2
  local font_width = 4
  local font_height = 5
  for i=1, player_manager.get_player_count() do
    local p_obj = player_manager.get_player(i)
    if p_obj then
      local score_txt = p_obj:get_score() .. ""
      local p_color = p_obj:get_color()
      if i == 1 then print(score_txt, margin, margin, p_color)
      elseif i == 2 then print(score_txt, 128 - margin - #score_txt * font_width, margin, p_color)
      elseif i == 3 then print(score_txt, margin, 128 - margin - font_height, p_color)
      elseif i == 4 then print(score_txt, 128 - margin - #score_txt * font_width, 128 - margin - font_height, p_color)
      end
    end
  end
end

function _draw()
  cls(0)
  if current_game_state == GAME_STATE_MENU then
    draw_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    draw_playing_state_elements()
  end
end
