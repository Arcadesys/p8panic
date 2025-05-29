---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry

player_manager = {} -- Initialize player_manager globally here
STASH_SIZE = 6 -- Default stash size, configurable in menu (min 3, max 10)
PLAYER_COUNT = 2 -- Default number of players, configurable in menu (min 2, max 4)
create_piece = nil -- Initialize create_piece globally here (will be defined by 3.piece.lua now)
pieces = {} -- Initialize pieces globally here
LASER_LEN = 60 -- Initialize LASER_LEN globally here
-- Player count is now configurable via PLAYER_COUNT in menu
cursors = {} -- Initialize cursors globally here
CAPTURE_RADIUS_SQUARED = 64 -- Initialize CAPTURE_RADIUS_SQUARED globally here

-- Declare these here, they will be assigned in _init()
original_update_game_logic_func = nil
original_update_controls_func = nil

-------------------------------------------
-- Helpers & Global Constants/Variables --
-------------------------------------------
--#globals player_manager create_piece pieces LASER_LEN PLAYER_COUNT cursors CAPTURE_RADIUS_SQUARED
--#globals ray_segment_intersect attempt_capture -- Core helpers defined in this file
--#globals update_controls score_pieces place_piece legal_placement -- Functions from modules
--#globals internal_update_game_logic original_update_game_logic_func original_update_controls_func
--#globals GAME_STATE_MENU GAME_STATE_PLAYING current_game_state
--#globals GAME_TIMER GAME_TIMER_MAX

-- Game timer constants
GAME_TIMER_MAX = 90 -- 90-second game rounds
GAME_TIMER = GAME_TIMER_MAX

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
-- Default number of players is defined as PLAYER_COUNT = 2 above
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
  for _, piece_obj in ipairs(pieces) do
    -- Check for both overcharged defenders and attackers owned by the player
    if piece_obj.owner_id == player_id and piece_obj.state == "overcharged" then
      if piece_obj.targeting_attackers then
        for attacker_idx = #piece_obj.targeting_attackers, 1, -1 do -- Iterate backwards for safe removal
          local attacker_to_capture = piece_obj.targeting_attackers[attacker_idx]
          if attacker_to_capture then -- Ensure attacker still exists
            local dist_x = (cursor.x + 4) - attacker_to_capture.position.x
            local dist_y = (cursor.y + 4) - attacker_to_capture.position.y
            
            if (dist_x*dist_x + dist_y*dist_y) < CAPTURE_RADIUS_SQUARED then
              local captured_color = attacker_to_capture:get_color()
              player_obj:add_captured_piece(captured_color)
              
              if del(pieces, attacker_to_capture) then -- Remove from global pieces
                printh("P" .. player_id .. " captured attacker (color: " .. captured_color .. ")")
                deli(piece_obj.targeting_attackers, attacker_idx) 
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
      return_cooldown = 0,
      color_select_idx = 1 -- For cycling stash colors during placement
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
-- Define the internal game logic update function
function internal_update_game_logic()
  -- Reset defender states before scoring
  for _, p_item in ipairs(pieces) do
    if p_item.type == "defender" then
      p_item.hits = 0
      p_item.targeting_attackers = {}
      -- p_item.state = "neutral" -- REMOVED: State will persist or be set by creation/scoring
      p_item.captured_flag = false -- Reset captured flag
    end
  end
  
  -- Call the scoring function from 2.scoring.lua
  if score_pieces then 
    score_pieces() 
  else 
    printh("Error: score_pieces is nil in internal_update_game_logic!")
  end
end

function go_to_state(new_state)
  if new_state == GAME_STATE_PLAYING and current_game_state ~= GAME_STATE_PLAYING then
    local current_game_stash_size = STASH_SIZE -- Capture STASH_SIZE once for this game start
    printh("GO_TO_STATE: CAPTURED STASH_SIZE="..current_game_stash_size) -- DEBUG

    pieces = {} -- Clear existing pieces
    
    -- Initialize players based on menu selection
    player_manager.init_players(PLAYER_COUNT)
    
    init_cursors(player_manager.get_player_count()) -- Cursors are initialized on game start
    GAME_TIMER = GAME_TIMER_MAX -- Reset game timer
    
    for i=1, player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p then 
        p.score = 0
        p.stash = {} 
        -- Use the locally captured stash size
        p.stash[p:get_color()] = current_game_stash_size 
        printh("P"..i.." STASH INIT: C="..p:get_color().." SZ="..current_game_stash_size.." CT="..p.stash[p:get_color()]) -- DEBUG
      end
    end
    if original_update_game_logic_func then original_update_game_logic_func() end
  end
  current_game_state = new_state
end


function _init()
  if not player_manager then
    printh("ERROR: player_manager is NIL in _init()", true) -- Debug print
  end
  
  -- Assign function pointers here, after all tabs are loaded
  if internal_update_game_logic then
    original_update_game_logic_func = internal_update_game_logic
  else
    printh("ERROR: internal_update_game_logic is NIL in _init!", true)
    -- Define a fallback internal update function if needed
    original_update_game_logic_func = function() end
  end
  
  if update_controls then
    original_update_controls_func = update_controls
  else
    printh("ERROR: update_controls is NIL in _init!", true)
    -- Define a fallback controls function if needed
    original_update_controls_func = function() end
  end
  
  -- Check if score_pieces is available (no need to assign it)
  if not _ENV.score_pieces then
     printh("ERROR: score_pieces is NIL in _init!", true)
  end

  -- Initialize menu variables
  menu_selection = 1 -- Default to first menu option (stash size)
  
  -- Start in the menu state
  current_game_state = GAME_STATE_MENU
  
  if not player_manager.get_player_count then
     printh("ERROR: player_manager.get_player_count is NIL in _init()", true)
  end
  -- Cursors and game pieces will be initialized when transitioning from menu to playing state
end


function update_menu_state()
  -- Menu has two options: stash size and player count
  -- Use up/down to switch between options, left/right to adjust values
  
  -- Track which menu item is selected (1=stash size, 2=player count)
  if not menu_selection then menu_selection = 1 end
  
  -- Navigate between menu options with up/down
  if btnp(⬆️) then
    menu_selection = max(1, menu_selection - 1)
  elseif btnp(⬇️) then
    menu_selection = min(2, menu_selection + 1)
  end
  
  -- Adjust the selected option with left/right
  if menu_selection == 1 then
    -- Adjust stash size
    if btnp(⬅️) then
      STASH_SIZE = max(3, STASH_SIZE - 1)
    elseif btnp(➡️) then
      STASH_SIZE = min(10, STASH_SIZE + 1)
    end
  elseif menu_selection == 2 then
    -- Adjust player count
    if btnp(⬅️) then
      PLAYER_COUNT = max(2, PLAYER_COUNT - 1)
    elseif btnp(➡️) then
      PLAYER_COUNT = min(4, PLAYER_COUNT + 1)
    end
  end
  
  -- Start game
  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_PLAYING)
  end
end

function update_playing_state()
  -- Update game controls
  if original_update_controls_func then 
    original_update_controls_func() 
  else 
    printh("Error: original_update_controls_func is nil in update_playing_state!") 
  end
  
  -- Update game logic - carefully wrapped to avoid errors
  if original_update_game_logic_func then
    if type(original_update_game_logic_func) == "function" then
      original_update_game_logic_func()
    else
      printh("Error: original_update_game_logic_func is not a function in update_playing_state!")
    end
  else 
    printh("Error: original_update_game_logic_func is nil in update_playing_state!") 
  end
  
  -- Update game timer (decrease by 1/30th of a second each frame)
  GAME_TIMER = max(0, GAME_TIMER - (1/30))
  
  -- Check for game over condition when timer runs out
  if GAME_TIMER <= 0 then
    -- TODO: Implement game over state transition
    -- For now, just restart the timer
    GAME_TIMER = GAME_TIMER_MAX
  end
end

function _update()
  if current_game_state == GAME_STATE_MENU then
    update_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    update_playing_state() -- Call the playing state update function
  end
end


function draw_menu_state()
  print("P8PANIC", 50, 40, 7)
  print("PRESS X OR O", 40, 54, 8)
  print("TO START", 50, 62, 8)
  
  -- Calculate colors based on selection
  local stash_color = 11
  local player_color = 11
  
  -- Make sure menu_selection is initialized
  if not menu_selection then 
    menu_selection = 1 
  end
  
  if menu_selection == 1 then
    stash_color = 7 -- Highlight with white when selected
  elseif menu_selection == 2 then
    player_color = 7 -- Highlight with white when selected
  end
  
  -- Draw stash size option
  if menu_selection == 1 then
    print("> STASH SIZE: "..STASH_SIZE, 28, 80, stash_color)
  else
    print("  STASH SIZE: "..STASH_SIZE, 28, 80, stash_color)
  end
  
  -- Draw player count option
  if menu_selection == 2 then
    print("> PLAYERS: "..PLAYER_COUNT, 28, 90, player_color)
  else
    print("  PLAYERS: "..PLAYER_COUNT, 28, 90, player_color)
  end
  
  -- Draw controls help
  print("\x8e/\x91: ADJUST \x83/\x82: SELECT", 16, 110, 6) -- ⬅️/➡️ and ⬆️/⬇️ icons
end

function draw_playing_state_elements()
  -- Draw game timer at the top center in MM:SS format
  local total_secs = flr(GAME_TIMER)
  local mins = flr(total_secs / 60)
  local secs = total_secs % 60
  local timer_str = mins .. ":" .. (secs < 10 and "0" or "") .. secs
  local timer_x = 62 - #timer_str * 2
  local timer_color = 7 -- Default white
  if GAME_TIMER < 30 then timer_color = 8 end -- Red for low time
  print(timer_str, timer_x, 2, timer_color)
  
  -- Draw pieces
  for _, piece_obj in ipairs(pieces) do
    if piece_obj and piece_obj.draw then
      piece_obj:draw()
      -- Debug display of attacker count removed
      -- No longer showing numbers above defenders
    end
  end
  
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)
    if not current_player_obj then goto next_cursor_draw end -- Skip if no player object

    -- In placement mode, use the selected color for the ghost piece
    local cursor_draw_color = cur.pending_color or ((current_player_obj and current_player_obj:get_ghost_color()) or 7)

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
      -- Draw compact stash
      local stash_y = y + font_height + 1
      
      for color, count in pairs(p_obj.stash) do
        if count > 0 then
          -- Draw color and count (e.g., "○5" in color 8)
          print("○"..count, x, stash_y, color)
          stash_y += font_height - 1 -- Slightly tighter spacing
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
