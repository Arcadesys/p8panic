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
