pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry

player_manager = {} -- Initialize player_manager globally here
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
--#globals update_controls score_attackers place_piece legal_placement -- Functions from modules
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
  if score_attackers then score_attackers() else printh("Error: score_attackers is nil in internal_update_game_logic!") end
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
  if not score_attackers then
     printh("ERROR: score_attackers is NIL in _init!", true)
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
end

function draw_playing_state_elements()
  for _, piece_obj in ipairs(pieces) do
    if piece_obj and piece_obj.draw then
      piece_obj:draw()
      -- debug: show number of attackers targeting this defender on-screen
      if piece_obj.type == "defender" then
        local count = 0
        if piece_obj.targeting_attackers then count = #piece_obj.targeting_attackers end
        -- print count above defender
        print(count, piece_obj.position.x + 4, piece_obj.position.y - 8, 7)
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
-->8
-- src/4.player.lua
--#globals player_manager
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
    stash = {} -- Initialize stash as an empty table
  }
  -- Initialize stash with 6 pieces of the player's own color
  instance.stash[color] = 6 
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
player_manager = {}

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
--#globals pieces player_manager ray_segment_intersect LASER_LEN _G
--#globals cos sin add ipairs del deli

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
      -- p_obj.state = nil -- or some default state if applicable
    end
  end
end

function score_pieces()
  reset_player_scores() -- Reset scores for all players
  reset_piece_states_for_scoring() -- Reset hits and targeting attackers for all pieces

  -- Score attackers hitting defenders
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
                  -- Defender is now overcharged. The defender\'s owner can use \'capture\' mode
                  -- to capture attackers targeting this defender. The defender itself is not
                  -- removed by this interaction, nor does the attacker\'s player capture the defender\'s color.
                end
              elseif defender_obj.hits == 1 then
                defender_obj.state = "successful" -- Hit once, still neutral
              end
              -- Only count one hit per attacker-defender pair, then stop checking other segments
              break
            end
          end
        end
        ::next_defender_score::
      end
    end
    ::next_attacker_score::
  end

  -- Score defenders based on incoming attackers
  for _, p_obj in ipairs(pieces) do
    if p_obj and p_obj.type == "defender" then
      local num_total_attackers_targeting = 0
      if p_obj.targeting_attackers then
        num_total_attackers_targeting = #p_obj.targeting_attackers
      end
      p_obj.dbg_target_count = num_total_attackers_targeting -- Store for on-screen debugging

      if num_total_attackers_targeting <= 1 then -- Defender scores if 0 or 1 attacker targets it
        local defender_player = player_manager.get_player(p_obj.owner_id)
        if defender_player then
          defender_player:add_score(1)
          -- Potentially update defender state here if needed, e.g., p_obj.state = "defending_well"
        end
      end
      -- If num_total_attackers_targeting is 2 or more, the defender does not score a point.
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

-- Renamed from score_attackers to score_pieces to reflect broader scope
score_pieces = score_pieces
-->8
-- src/5.piece.lua

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
  setmetatable(o, self) -- Set metatable after o is populated
  return o
end

function Piece:get_color()
  if self.is_ghost and self.ghost_color_override then
    return self.ghost_color_override
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

  local hit_defender_state = nil

  -- Check for intersections with all defenders
  if pieces then
    for _, other_piece in ipairs(pieces) do
      if other_piece.type == "defender" then
        local def_corners = other_piece:get_draw_vertices()
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = ray_segment_intersect(
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
--#globals N_PLAYERS -- Though not directly used, it's part of the context of 0.init

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
    local piece_color_to_place = player_obj:get_color()
    
    if player_obj:use_piece_from_stash(piece_color_to_place) then
      local new_piece_obj = create_piece(piece_params)
      if new_piece_obj then
        add(pieces, new_piece_obj)
        score_pieces() -- Recalculate scores after placing a piece
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
-->8
-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.
--#globals player_manager cursors place_piece attempt_capture original_update_game_logic_func
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
    if not current_player_obj then goto next_cursor_ctrl end

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
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate immediately
          else
            printh("P" .. i .. ": Capture failed.")
          end
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
        local piece_params = {
          owner_id = i, -- Use player index as owner_id
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
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
        cur.pending_orientation = 0
        cur.pending_type = "defender"
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
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
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122222222222222222222222222222300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

