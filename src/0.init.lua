---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry

player_manager = {} -- Initialize player_manager globally here
STASH_SIZE = 6 -- Default stash size, configurable in menu (min 3, max 10)
create_piece = nil -- Initialize create_piece globally here (will be defined by 3.piece.lua now)
pieces = {} -- Initialize pieces globally here
LASER_LEN = 60 -- Initialize LASER_LEN globally here
N_PLAYERS = 4 -- Initialize N_PLAYERS globally here
cursors = {} -- Initialize cursors globally here
CAPTURE_RADIUS_SQUARED = 64 -- Initialize CAPTURE_RADIUS_SQUARED globally here

-- Declare these here, they will be assigned in _init()
original_update_game_logic_func = nil
original_update_controls_func = nil

-------------------------------------------
-- Helpers & Global Constants/Variables --
-------------------------------------------
--#globals player_manager create_piece pieces LASER_LEN N_PLAYERS cursors CAPTURE_RADIUS_SQUARED
--#globals ray_segment_intersect attempt_capture -- Core helpers defined in this file
--#globals update_controls score_pieces place_piece legal_placement -- Functions from modules
--#globals internal_update_game_logic original_update_game_logic_func original_update_controls_func

-- CAPTURE_RADIUS_SQUARED = 64 -- (8*8) For capture proximity check -- Already defined above

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
-- pieces = {} -- Already defined above
-- N_PLAYERS = 4           -- Default number of players -- Already defined above
-- LASER_LEN = 60          -- Maximum laser beam length -- Already defined above

-- Cached math functions
local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

------------------------------------------
-- Core Helper Functions (defined before includes that might use them)
------------------------------------------
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

-- Moved attempt_capture here, before includes that use it (e.g., 3.controls.lua)
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

-- All modules are loaded via Pico-8 tabs; remove #include directives

-------------------------------------------
-- Multi-Cursor Support (one per player) --
-------------------------------------------
-- cursors table is initialized at the top

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
-- local original_update_game_logic_func -- Now defined after includes
-- local original_update_controls_func -- Now defined after includes

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
  if score_pieces then score_pieces() else printh("Error: score_pieces is nil in internal_update_game_logic!") end
end

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


function _init()
  if not player_manager then
    printh("ERROR: player_manager is NIL in _init() BEFORE init_players", true) -- Debug print
  end
  player_manager.init_players(N_PLAYERS) -- Initialize players
  init_cursors(N_PLAYERS)               -- Initialize cursors for each player
  
  -- Assign function pointers here, after all tabs are loaded
  original_update_game_logic_func = internal_update_game_logic
  if update_controls then
    original_update_controls_func = update_controls
  else
    printh("ERROR: update_controls is NIL in _init!", true)
  end
  if not score_pieces then
     printh("ERROR: score_pieces is NIL in _init!", true)
  end

  go_to_state(GAME_STATE_PLAYING)       -- Immediately enter playing state so controls are active
  if not player_manager then
    printh("ERROR: player_manager is NIL in _init() AFTER init_players", true) -- Debug print
  end
  if not cursors then
    printh("ERROR: cursors is NIL in _init()", true)
  end
  if not player_manager.get_player_count then
     printh("ERROR: player_manager.get_player_count is NIL in _init()", true)
  end
  -- Cursors and game pieces initialized by go_to_state(GAME_STATE_PLAYING)
  -- Start in menu state by default (current_game_state = GAME_STATE_MENU)
end


function update_menu_state()
  -- Adjust stash size with left/right
  if btnp(⬅️) then
    STASH_SIZE = max(3, STASH_SIZE - 1)
  elseif btnp(➡️) then
    STASH_SIZE = min(10, STASH_SIZE + 1)
  end
  -- Start game
  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_PLAYING)
  end
end

function update_playing_state()
  if original_update_controls_func then original_update_controls_func() else printh("Error: original_update_controls_func is nil!") end
  if original_update_game_logic_func then original_update_game_logic_func() else printh("Error: original_update_game_logic_func is nil!") end
end

function _update()
  if current_game_state == GAME_STATE_MENU then
    update_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    if original_update_controls_func then 
      original_update_controls_func() 
    else 
      printh("Error: original_update_controls_func is nil in _update!") 
    end
    if original_update_game_logic_func then 
      original_update_game_logic_func() 
    else 
      printh("Error: original_update_game_logic_func is nil in _update!") 
    end
  end
end


function draw_menu_state()
  print("P8PANIC", 50, 50, 7)
  print("PRESS X OR O", 40, 70, 8)
  print("TO START", 50, 80, 8)
  print("STASH SIZE: "..STASH_SIZE, 36, 100, 11)
  print("(\x8e/\x91 to set 3-10)", 24, 110, 6) -- ⬅️/➡️
end

function draw_playing_state_elements()
  for _, piece_obj in ipairs(pieces) do
    if piece_obj and piece_obj.draw then
      piece_obj:draw()
      -- debug: show number of attackers targeting this defender on-screen
      if piece_obj.type == "defender" then
        local count_to_display = piece_obj.dbg_target_count or 0 -- Use dbg_target_count, default to 0 if nil
        -- print count above defender
        print(count_to_display, piece_obj.position.x + 4, piece_obj.position.y - 8, 7)
      end
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
      -- Draw score in corner
      local x, y = margin, margin
      if i == 1 then x, y = margin, margin
      elseif i == 2 then x, y = 128 - margin - #score_txt * font_width, margin
      elseif i == 3 then x, y = margin, 128 - margin - font_height
      elseif i == 4 then x, y = 128 - margin - #score_txt * font_width, 128 - margin - font_height
      end
      print(score_txt, x, y, p_color)
      -- Draw stash below/above score, one color per line
      local stash_y = y + font_height + 1
      for color, count in pairs(p_obj.stash) do
        if count > 0 then
          print("["..count.."]", x, stash_y, color)
          stash_y = stash_y + font_height
        end
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
