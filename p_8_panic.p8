pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
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
--#globals update_controls score_pieces place_piece legal_placement create_cursor -- Functions from modules
--#globals internal_update_game_logic original_update_game_logic_func original_update_controls_func
--#globals GAME_STATE_MENU GAME_STATE_PLAYING current_game_state
--#globals GAME_TIMER GAME_TIMER_MAX

-- Game timer constants
GAME_TIMER_MAX = 180 -- 180-second game rounds
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
    {x = 18, y = 18},                -- P1: just outside top-left UI
    {x = 128 - 18 - 1, y = 18},      -- P2: just outside top-right UI
    {x = 18, y = 128 - 18 - 1},      -- P3: just outside bottom-left UI
    {x = 128 - 18 - 1, y = 128 - 18 - 1} -- P4: just outside bottom-right UI
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

    -- Call create_cursor from 7.cursor.lua to create the cursor object
    -- This object will have the correct draw method.
    if create_cursor then
      cursors[i] = create_cursor(i, sp.x, sp.y)
      -- Initialize other properties if create_cursor doesn't set them all,
      -- though ideally create_cursor should handle all necessary defaults.
      -- For example, if create_cursor doesn't set spawn_x/spawn_y:
      -- if cursors[i] then
      --   cursors[i].spawn_x = sp.x
      --   cursors[i].spawn_y = sp.y
      -- end
    else
      printh("ERROR: create_cursor function is not defined! Cannot initialize cursors properly.")
      -- Fallback to basic table if create_cursor is missing (will lack the advanced draw method)
      cursors[i] = {
        id = i,
        x = sp.x, y = sp.y,
        spawn_x = sp.x, spawn_y = sp.y,
        control_state = 0,
        pending_type = "defender",
        pending_color = 7, -- Simplified fallback
        pending_orientation = 0,
        return_cooldown = 0,
        color_select_idx = 1,
        draw = function() printh("Fallback cursor draw for P"..i) end -- Basic fallback draw
      }
    end
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
  -- main title and prompt
  print("P8PANIC", 50, 40, 7)
  print("PRESS X OR O", 40, 54, 8)
  print("TO START", 50, 62, 8)
  -- ensure menu_selection
  if not menu_selection then menu_selection = 1 end
  -- highlight colors
  local stash_color = (menu_selection == 1) and 7 or 11
  local player_color = (menu_selection == 2) and 7 or 11
  -- stash size option
  print((menu_selection == 1 and ">" or " ").." STASH SIZE: "..STASH_SIZE,
        28, 80, stash_color)
  -- player count option
  print((menu_selection == 2 and ">" or " ").." PLAYERS: "..PLAYER_COUNT,
        28, 90, player_color)
  -- controls help icons
  print("\x8e/\x91: ADJUST \x83/\x82: SELECT", 16, 110, 6) -- controls help icons
end

function draw_playing_state_elements()
  -- Draw game timer in MM:SS
  local secs = flr(GAME_TIMER)
  local timer_str = flr(secs/60) .. ":" .. (secs%60 < 10 and "0" or "") .. (secs%60)
  print(timer_str, 62 - #timer_str*2, 2, GAME_TIMER < 30 and 8 or 7)
  -- Draw pieces and cursors
  for _,o in ipairs(pieces) do if o.draw then o:draw() end end
  for _,c in ipairs(cursors) do if c.draw then c:draw() end end
  -- Draw stash bars for each player
  local m,fw,fh,bh,bw,bs,nb = 2,4,5,8,2,1,4
  for i=1,player_manager.get_player_count() do
    local p = player_manager.get_player(i)
    if p then
      local s = tostr(p:get_score())
      local sw = #s*fw
      local tw = nb*bw + (nb-1)*bs
      local block_w = max(sw,tw)
      local ax = (i==2 or i==4) and (128-m-block_w) or m
      local ay = (i>=3) and (128-m-(fh+2+bh)) or m
      -- score
      print(s, ax + ((block_w-sw) * ((i==2 or i==4) and 1 or 0)), ay, p:get_color())
      -- bars
      local bx = (i==2 or i==4) and (ax + block_w - tw) or ax
      local by = ay + fh + 1
      for j=1,nb do
        local col = player_manager.colors[j] or 0
        local cnt = p.stash[col] or 0
        local h = flr(cnt / STASH_SIZE * bh)
        h = mid(0,h,bh)
        if i==1 or i==2 then
          -- Top players: bars grow down from just below score
          if h>0 then rectfill(bx,by,bx+bw-1,by+h-1,col)
          else line(bx,by,bx+bw-1,by,1) end
        else
          -- Bottom players: bars grow up from bottom as before
          if h>0 then rectfill(bx,by+(bh-h),bx+bw-1,by+bh-1,col)
          else line(bx,by+bh-1,bx+bw-1,by+bh-1,1) end
        end
        bx += bw + bs
      end
    end
  end
end

function _draw()
  cls(0)
  -- Draw background UI map
  map(0, 0, 0, 0, 16, 16,0)
  if current_game_state == GAME_STATE_MENU then
    draw_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    draw_playing_state_elements()
  end
end
-->8
-- src/4.player.lua
--#globals player_manager STASH_SIZE
--#globals player_manager

local Player = {}
Player.__index = Player -- For metatable inheritance

-- Constructor for a new player object
function Player:new(id, initial_score, color, ghost_color) -- Added initial_score
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {}, -- Initialize stash as an empty table
    capture_mode = false -- Added capture_mode
  }
  -- Initialize stash with configurable number of pieces (STASH_SIZE) of the player's own color
  instance.stash[color] = STASH_SIZE or 6
  setmetatable(instance, self)
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

-- Method to check if player is in capture mode
function Player:is_in_capture_mode()
  return self.capture_mode
end

-- Method to toggle capture mode
function Player:toggle_capture_mode()
  self.capture_mode = not self.capture_mode
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

-- Function to get the current number of initialized players
function player_manager.get_player_count()
  return #player_manager.current_players
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
-- player_manager is global by default via the above declaration
-->8
-- src/2.scoring.lua
-- Scoring Module
--#globals pieces player_manager ray_segment_intersect LASER_LEN cos sin add ipairs del deli

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
      p_obj.dbg_target_count = nil -- Ensure debug display counter is cleared
      -- p_obj.state = nil -- or some default state if applicable
    end
  end
end

function _check_attacker_hit_piece(attacker_obj, target_obj, player_manager_param, ray_segment_intersect_func, current_laser_len, add_func)
  local attacker_vertices = attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices == 0 then return end
  local apex = attacker_vertices[1]
  local dir_x = cos(attacker_obj.orientation) -- cos is global via --#globals
  local dir_y = sin(attacker_obj.orientation) -- sin is global via --#globals

  local target_corners = target_obj:get_draw_vertices()
  if not target_corners or #target_corners == 0 then return end

  for j = 1, #target_corners do
    local k = (j % #target_corners) + 1
    local ix, iy, t = ray_segment_intersect_func(apex.x, apex.y, dir_x, dir_y,
                                                 target_corners[j].x, target_corners[j].y,
                                                 target_corners[k].x, target_corners[k].y)
    if t and t >= 0 and t <= current_laser_len then
      target_obj.hits = (target_obj.hits or 0) + 1
      target_obj.targeting_attackers = target_obj.targeting_attackers or {}
      add_func(target_obj.targeting_attackers, attacker_obj)

      local attacker_player = player_manager_param.get_player(attacker_obj.owner_id)
      local target_player = player_manager_param.get_player(target_obj.owner_id)

      if attacker_player and target_player and attacker_obj.owner_id ~= target_obj.owner_id then
        attacker_player:add_score(1)
      end

      -- Update state of the target_obj based on hits
      if target_obj.type == "defender" then
        if target_obj.hits >= 3 then
          target_obj.state = "overcharged"
        elseif target_obj.hits == 2 then
          target_obj.state = "unsuccessful"
        elseif target_obj.hits == 1 then
          target_obj.state = "successful"
        end
        -- If a defender has 0 hits, its state is not changed here; it retains its prior state (e.g., from creation or previous scoring).
      end
      -- Attacker pieces do not change their state to 'overcharged', 'unsuccessful', or 'successful' based on being hit.
      -- Their state (e.g., 'neutral') would be managed by other game mechanics if needed.
      return true
    end
  end
  return false
end

function _score_defender(p_obj, player_manager_param)
  if p_obj and p_obj.type == "defender" then
    local num_total_attackers_targeting = 0
    if p_obj.targeting_attackers then
      num_total_attackers_targeting = #p_obj.targeting_attackers
    end

    if num_total_attackers_targeting <= 1 then
      local defender_player = player_manager_param.get_player(p_obj.owner_id)
      if defender_player then
        defender_player:add_score(1)
      end
    end
  end
end

function score_pieces()
  reset_player_scores()
  reset_piece_states_for_scoring()

  -- Score attackers hitting other pieces (defenders and other attackers)
  for _, attacker_obj in ipairs(pieces) do -- Use global 'pieces' directly
    if attacker_obj and attacker_obj.type == "attacker" then
      -- First check against defenders
      for _, defender_obj in ipairs(pieces) do -- Use global 'pieces' directly
        if defender_obj and defender_obj.type == "defender" then
          -- Pass global variables directly to the helper function
          _check_attacker_hit_piece(attacker_obj, defender_obj, player_manager, ray_segment_intersect, LASER_LEN, add)
        end
      end
      
      -- Then check against other attackers (excluding self)
      for _, other_attacker_obj in ipairs(pieces) do
        if other_attacker_obj and other_attacker_obj.type == "attacker" and other_attacker_obj ~= attacker_obj then
          -- Check if attacker hits other attacker
          _check_attacker_hit_piece(attacker_obj, other_attacker_obj, player_manager, ray_segment_intersect, LASER_LEN, add)
        end
      end
    end
  end

  -- Score defenders based on incoming attackers
  for _, p_obj in ipairs(pieces) do -- Use global 'pieces' directly
    -- Pass global 'player_manager' directly
    _score_defender(p_obj, player_manager)
    
    -- Clear any debug target count that might be set
    if p_obj.type == "defender" then
      p_obj.dbg_target_count = nil
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

-- No need for any additional export - in PICO-8, functions are global by default
-->8
-- src/5.piece.lua

--#globals pieces player_manager ray_segment_intersect LASER_LEN 
--#globals cos sin ipairs

-- Forward declarations for metatables if needed
Piece = {}
Piece.__index = Piece

Attacker = {}
Attacker.__index = Attacker
setmetatable(Attacker, {__index = Piece}) -- Inherit from Piece

Defender = {}
Defender.__index = Defender
setmetatable(Defender, {__index = Piece}) -- Inherit from Piece

-- Piece constants (can be moved from 0.init.lua)
DEFENDER_WIDTH = 8
DEFENDER_HEIGHT = 8
local ATTACKER_TRIANGLE_HEIGHT = 8
local ATTACKER_TRIANGLE_BASE = 6
    -- local LASER_LEN = 60 -- This is globally defined in 0.init.lua as LASER_LEN and accessed via LASER_LEN

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
  -- o.color is now passed in params for placed pieces
  setmetatable(o, self) -- Set metatable after o is populated
  return o
end

function Piece:get_color()
  if self.is_ghost and self.ghost_color_override then
    return self.ghost_color_override
  end
  -- If a color is explicitly set on the piece (e.g., when placed from stash), use it.
  if self.color then
    return self.color
  end
  if self.owner_id then
    local owner_player = player_manager.get_player(self.owner_id)
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
  o.hits = 0
  o.state = "neutral" -- "neutral", "unsuccessful", "overcharged"
  o.targeting_attackers = {}
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
  local laser_end_x = apex.x + dir_x * LASER_LEN
  local laser_end_y = apex.y + dir_y * LASER_LEN
  local closest_hit_t = LASER_LEN

  local hit_piece_state = nil
  local hit_piece_type = nil

  -- Check for intersections with all pieces (defenders and attackers)
  if pieces then
    for _, other_piece in ipairs(pieces) do
      if other_piece ~= self then -- Don't check against self
        local piece_corners = other_piece:get_draw_vertices()
        for j = 1, #piece_corners do
          local k = (j % #piece_corners) + 1
          local ix, iy, t = ray_segment_intersect(
            apex.x, apex.y, dir_x, dir_y,
            piece_corners[j].x, piece_corners[j].y, piece_corners[k].x, piece_corners[k].y
          )
          if t and t >= 0 and t < closest_hit_t then
            closest_hit_t = t
            laser_end_x = ix
            laser_end_y = iy
            hit_piece_state = other_piece.state -- Store the state of the hit piece
            hit_piece_type = other_piece.type
          end
        end
      end
    end
  end

  -- Adjust laser color based on hit piece's state
  if hit_piece_state == "unsuccessful" then
    laser_color = 8 -- Red for unsuccessful
  elseif hit_piece_state == "overcharged" then
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
  o.state = "successful" -- "neutral", "unsuccessful", "overcharged"
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
function create_piece(params) -- `params` should include owner_id, type, position, orientation, color
  local piece_obj
  if params.type == "attacker" then
    piece_obj = Attacker:new(params) -- Pass all params, including color
  elseif params.type == "defender" then
    piece_obj = Defender:new(params) -- Pass all params, including color
  else
    printh("Error: Unknown piece type: " .. (params.type or "nil"))
    return nil
  end
  return piece_obj
end

-- The return statement makes these functions/tables available when this file is included.
-- We might not need to return Piece, Attacker, Defender if only create_piece is used externally.
-- create_piece is global by default
-- Or, more structured:
-- return {
--   create_piece = create_piece
-- }
-->8
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
  -- UI overlay forbidden zones (16x16 px in each corner)
  local ui_zones = {
    {x1=0, y1=0, x2=15, y2=15}, -- top-left
    {x1=112, y1=0, x2=127, y2=15}, -- top-right
    {x1=0, y1=112, x2=15, y2=127}, -- bottom-left
    {x1=112, y1=112, x2=127, y2=127} -- bottom-right
  }

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
    -- Block placement if any vertex is inside a UI overlay zone
    for z in all(ui_zones) do
      if c.x >= z.x1 and c.x <= z.x2 and c.y >= z.y1 and c.y <= z.y2 then
        return false
      end
    end
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
-->8
-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.
--#globals player_manager cursors place_piece attempt_capture original_update_game_logic_func pieces
--#globals max min btn btnp
-- Constants for control states (optional)
local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2        -- pixels per frame; adjust as needed
  local rotation_speed = 0.02   -- rotation amount per frame; adjust

  -- Iterate through each player's cursor in the global 'cursors' table.
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)
    printh("P"..i.." CTRL: P_OBJ IS ".. (current_player_obj and "OK" or "NIL")) -- DEBUG
    if current_player_obj and current_player_obj.stash then -- DEBUG
      for k,v in pairs(current_player_obj.stash) do -- DEBUG
        printh("P"..i.." STASH: K="..k.." V="..v) -- DEBUG, no tostring
      end
    elseif current_player_obj then -- DEBUG
        printh("P"..i.." STASH IS NIL") -- DEBUG
    end -- DEBUG

    if not current_player_obj then goto next_cursor_ctrl end

    -- Determine Player Status and Forced Action State
    local player_has_empty_stash = true
    if current_player_obj and current_player_obj.stash then
      for _color_id, count in pairs(current_player_obj.stash) do
        if count > 0 then
          player_has_empty_stash = false
          break -- Found a piece, stash is not empty
        end
      end
    else
      -- If current_player_obj is nil or stash is nil, it's effectively empty for this check
      player_has_empty_stash = true
    end

    local player_has_successful_defender = false
    if pieces then -- Ensure pieces table exists
      for piece_idx, p_obj in pairs(pieces) do -- Changed to pairs to get index for print
        -- DEBUG: Print properties of pieces being checked
        if p_obj.type == "defender" then -- Only print for defenders to reduce log spam
          printh("P"..i.." CHK_DEF: ID="..piece_idx.." OWNER="..p_obj.owner_id.." TYPE="..p_obj.type.." STATE="..p_obj.state)
        end
        if p_obj.owner_id == i and p_obj.type == "defender" and p_obj.state == "successful" then
          player_has_successful_defender = true
          printh("P"..i.." FOUND SUCCESSFUL DEFENDER: ID="..piece_idx) -- DEBUG
          break
        end
      end
    end

    local forced_action_state = "normal" -- "normal", "capture_only", "must_place_defender"

    if player_has_empty_stash then
      cur.pending_type = "capture"
      forced_action_state = "capture_only"
    elseif not player_has_successful_defender then
      cur.pending_type = "defender"
      cur.pending_color = current_player_obj:get_color()
      forced_action_state = "must_place_defender"
    end
    printh("P"..i.." FLAGS: EMPTY="..(player_has_empty_stash and "T" or "F").." HAS_DEF="..(player_has_successful_defender and "T" or "F").." FORCE_STATE="..forced_action_state) -- DEBUG

    -- Handle player cycling piece/action type if in normal state and CSTATE_MOVE_SELECT
    if cur.control_state == CSTATE_MOVE_SELECT and btnp(🅾️, i - 1) and forced_action_state == "normal" then
        local current_orientation = cur.pending_orientation
        if cur.pending_type == "defender" then
            cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
            cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
            cur.pending_type = "defender"
        end
        cur.pending_orientation = current_orientation
    end

    -- Set player's capture_mode based on the FINAL cur.pending_type for this frame
    if current_player_obj then
        current_player_obj.capture_mode = (cur.pending_type == "capture")
        printh("P"..i.." CAPTURE MODE: "..(current_player_obj.capture_mode and "ON" or "OFF").." PENDING_TYPE: "..cur.pending_type) -- DEBUG
    end

    if cur.control_state == CSTATE_MOVE_SELECT then
      -- Continuous movement with the d-pad.
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      -- Initiate placement/rotation/capture with Button X.
      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then -- If pending type is capture (either forced or selected)
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate immediately
          else
            printh("P" .. i .. ": Capture failed.")
          end
        else -- pending_type is "defender" or "attacker"
          cur.control_state = CSTATE_ROTATE_PLACE
          -- Orientation and color will be handled in CSTATE_ROTATE_PLACE
          -- No longer resetting orientation when starting placement
        end
      end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if forced_action_state == "must_place_defender" then
        -- Only player's own color is available
        add(available_colors, current_player_obj:get_color())
        cur.color_select_idx = 1 -- Ensure it's selected
      else
        -- Gather available colors in stash (player's own and captured)
        if current_player_obj and current_player_obj.stash then -- Ensure player and stash exist
          for color, count in pairs(current_player_obj.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      -- If no colors were added (e.g., stash is completely empty, which shouldn't happen if forced_action_state isn's capture_only),
      -- or if in a state where only own color is allowed but not present (edge case).
      -- Fallback to player's own color if available_colors is still empty.
      -- This handles the scenario where a player might have 0 of their own color but prisoners.
      if #available_colors == 0 and current_player_obj and current_player_obj:has_piece_in_stash(current_player_obj:get_color()) then
         add(available_colors, current_player_obj:get_color())
      elseif #available_colors == 0 then
        -- If truly no pieces are placeable (e.g. empty stash and not forced to place defender)
        -- this situation should ideally be handled by `forced_action_state` pushing to "capture_only"
        -- or preventing entry into CSTATE_ROTATE_PLACE.
        -- For safety, if we reach here with no available colors, revert to move/select.
        printh("P"..i.." WARN: No available colors in ROTATE_PLACE, reverting state.")
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl -- Skip further processing for this cursor this frame
      end

      -- Clamp color_select_idx
      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      -- Cycle color selection with up/down
      if forced_action_state ~= "must_place_defender" then
        if btnp(⬆️, i - 1) then
          cur.color_select_idx = cur.color_select_idx - 1
          if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end
        elseif btnp(⬇️, i - 1) then
          cur.color_select_idx = cur.color_select_idx + 1
          if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
        end
      end

      -- Rotate pending piece using left/right
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end

      -- Set pending_color to selected color
      if forced_action_state == "must_place_defender" then
        cur.pending_color = current_player_obj:get_color()
      else
        -- Ensure available_colors has entries before trying to access
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_ghost_color() -- Fallback to ghost color
        else
            -- This case should ideally be prevented by earlier checks.
            -- If somehow reached, use player's ghost color as a safe default.
            cur.pending_color = current_player_obj:get_ghost_color() 
            printh("P"..i.." WARN: Setting pending_color to ghost_color due to no available_colors.")
        end
      end

      -- Confirm placement with Button X.
      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i, -- Use player index as owner_id
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation,
          color = cur.pending_color -- Add the selected color to piece_params
        }
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = CSTATE_COOLDOWN
          cur.return_cooldown = 6  -- 6-frame cooldown after placement
          if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate board state
        else
          printh("Placement failed for P" .. i)
        end
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
        -- The status checks at the start of CSTATE_MOVE_SELECT will handle pending_type and pending_color
        -- So, we can reset to a sensible default or leave as is,
        -- as it will be overridden if a forced state is active.
        cur.pending_type = "defender" -- Default, will be overridden if needed
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
--cursor
local default_cursor_props={
  control_state=0,
  pending_type="defender",
  pending_orientation=0.25, -- Start with a useful default angle
  color_select_idx=1,
  return_cooldown=0,
}
function create_cursor(player_id,initial_x,initial_y)
  local p_color=7
  local p_ghost_color=7
  if player_manager and player_manager.get_player then
    local player=player_manager.get_player(player_id)
    if player then
      if player.get_color then
        p_color=player:get_color()
      end
      if player.get_ghost_color then
        local ghost_color_val=player:get_ghost_color()
        if ghost_color_val then
          p_ghost_color=ghost_color_val
        end
      end
    end
  end
  local cur={
    id=player_id,
    x=initial_x,
    y=initial_y,
    spawn_x=initial_x,
    spawn_y=initial_y,
    control_state=default_cursor_props.control_state,
    pending_type=default_cursor_props.pending_type,
    pending_orientation=default_cursor_props.pending_orientation,
    pending_color=p_ghost_color,
    color_select_idx=default_cursor_props.color_select_idx,
    return_cooldown=default_cursor_props.return_cooldown,
    draw=function(self)
      printh("P"..self.id.." CURSOR: DRAW FUNCTION CALLED") -- <<< ADD THIS LINE

      local cursor_color
      local current_player
      if player_manager and player_manager.get_player then
        current_player = player_manager.get_player(self.id)
        if current_player and current_player.get_color then
          cursor_color=current_player:get_color()
        end
      end
      if not cursor_color then
        cursor_color=self.pending_color
      end
      
      local cx,cy=self.x+4,self.y+4
      -- Draw X-shaped crosshair with 5-pixel size
      line(cx-2,cy-2,cx+2,cy+2,cursor_color)
      line(cx-2,cy+2,cx+2,cy-2,cursor_color)
      
      -- Show ghost piece only when applicable
      if self.pending_type=="attacker" or self.pending_type=="defender" then
        local ghost_piece_params={
          owner_id=self.id,
          type=self.pending_type,
          position={x=self.x+4,y=self.y+4},
          orientation=self.pending_orientation,
          color=self.pending_color,
          is_ghost=true
        }
        local ghost_piece=create_piece(ghost_piece_params)
        if ghost_piece and ghost_piece.draw then
          ghost_piece:draw()
        end
      end

      -- Draw purple circles around capturable ships if in capture mode
      if current_player and current_player:is_in_capture_mode() then
        printh("P"..self.id.." CURSOR: In Capture Mode. Searching for capturable pieces...") -- DEBUG
        if pieces then
          local found_overcharged_defender_for_player = false
          for _, my_piece in ipairs(pieces) do
            -- Condition 1: Is it MY piece, is it a DEFENDER, and is it OVERCHARGED?
            if my_piece.owner_id == self.id and my_piece.type == "defender" and my_piece.state == "overcharged" then
              found_overcharged_defender_for_player = true
              printh("P"..self.id.." CURSOR: Found OWNED OVERCHARGED DEFENDER (Owner: "..my_piece.owner_id..", Type: "..my_piece.type..", State: "..my_piece.state..")") -- DEBUG
              
              if my_piece.targeting_attackers and #my_piece.targeting_attackers > 0 then
                printh("P"..self.id.." CURSOR: Overcharged defender has "..#my_piece.targeting_attackers.." targeting attacker(s).") -- DEBUG
                
                for _, attacker_to_capture in ipairs(my_piece.targeting_attackers) do
                  if attacker_to_capture and attacker_to_capture.position then
                    -- Condition 2: Is the targeting piece an ATTACKER? (Owner doesn't matter for highlighting)
                    if attacker_to_capture.type == "attacker" then -- Removed owner check attacker_to_capture.owner_id ~= self.id
                      local piece_pos = attacker_to_capture.position
                      local radius = 5 -- Attackers are triangles, 5 should be a decent radius
                      
                      printh("P"..self.id.." CURSOR: DRAWING CIRCLE around ATTACKER (Owner: "..attacker_to_capture.owner_id..", Type: "..attacker_to_capture.type..") at X:"..piece_pos.x..", Y:"..piece_pos.y) -- DEBUG
                      circ(piece_pos.x, piece_pos.y, radius, 14) -- Pico-8 color 14 is purple
                    else
                      printh("P"..self.id.." CURSOR: A targeting piece in 'targeting_attackers' is NOT an attacker (Type: "..(attacker_to_capture.type or "NIL").."). No circle.") -- DEBUG
                    end
                  else
                     printh("P"..self.id.." CURSOR ERR: A piece in targeting_attackers is invalid or has no position.") -- DEBUG
                  end
                end
              else
                printh("P"..self.id.." CURSOR: Owned overcharged defender has NO targeting attackers.") -- DEBUG
              end
            end
          end
          if not found_overcharged_defender_for_player then
            printh("P"..self.id.." CURSOR: No owned overcharged defenders found.") -- DEBUG
          end
        else
          printh("P"..self.id.." CURSOR ERR: 'pieces' table is nil.") -- DEBUG
        end
      else
        if current_player and not current_player:is_in_capture_mode() then
           -- This log can be very spammy, enable if specifically debugging capture mode toggle
           -- printh("P"..self.id.." CURSOR: Not in capture mode.") 
        elseif not current_player then
            printh("P"..self.id.." CURSOR ERR: current_player is nil.") -- DEBUG
        end
      end
    end
  }
  return cur
end
__gfx__
00000000777777777777777777777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000766666666666666666666667000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000766666666666666666666667000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000777777777777777777777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111677611111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111677611111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000151111677611151111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000001d51116776115d1111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000011111167761111111111d111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000001111116776111111111d1111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111677611111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000111111677611111111111111000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
1213000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2223000000000000000000000000212200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0203000000000000000000000000010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1213000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

