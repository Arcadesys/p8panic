pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
---@diagnostic disable: undefined-global
-- p8panic - A game of tactical geometry

player_manager = {} -- Initialize player_manager globally here
STASH_SIZE = 6 -- Default stash size, configurable in menu (min 3, max 10)
create_piece = nil -- Initialize create_piece globally here (will be defined by 3.piece.lua)
pieces = {} -- Initialize pieces globally here
LASER_LEN = 60 -- Initialize LASER_LEN globally here
N_PLAYERS = 4 -- Initialize N_PLAYERS globally here
cursors = {} -- Initialize cursors globally here
CAPTURE_RADIUS_SQUARED = 64 -- Initialize CAPTURE_RADIUS_SQUARED globally here

-- Global game state
global_game_state = "main_menu" -- "main_menu", "in_game", "game_over", etc.

-- Global variables for menu settings (to be set by the menu via 7.main.lua)
player_count = N_PLAYERS -- Default to current N_PLAYERS
stash_count = STASH_SIZE  -- Default to current STASH_SIZE

-------------------------------------------
-- Helpers & Global Constants/Variables --
-------------------------------------------
--#globals player_manager create_piece pieces LASER_LEN N_PLAYERS cursors CAPTURE_RADIUS_SQUARED global_game_state player_count stash_count
--#globals ray_segment_intersect attempt_capture -- Core helpers defined in this file
--#globals update_controls score_pieces place_piece legal_placement -- Functions from modules
--#globals internal_update_game_logic original_update_game_logic_func original_update_controls_func ui_handler -- ui_handler is now set in 7.main.lua

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

sfx_on=true

game_timer = 3 -- Default game time in minutes

-- All modules are loaded via Pico-8 tabs; #include directives are not used.
-- Main Pico-8 functions (_init, _update, _draw) and their specific logic
-- (e.g., init_game_properly, _update_main_menu, _draw_game)
-- have been moved to src/7.main.lua.

-- This file now primarily serves to define global variables, constants,
-- and core helper functions that are used across multiple modules.

-- Example of a function that might have been wrapped, now handled in 7.main.lua
-- if it needs wrapping. If it's a core game logic update that doesn't need
-- state-based wrapping (like menu vs game), it could live here or in its own module.
-- For now, assuming update_game_logic and update_controls are functions defined
-- in other modules (e.g. 2.scoring.lua for game logic, 5.controls.lua for controls)
-- and will be called by the main loop in 7.main.lua.

-- function internal_update_game_logic()
--   if original_update_game_logic_func then
--     original_update_game_logic_func()
--   end
--   -- Add any logic that should always run, regardless of game state, if any.
--   -- Or, this function itself is the "original" if no other module defines `update_game_logic`.
-- end

-- Note: The original_update_game_logic_func and original_update_controls_func
-- are now declared and managed within src/7.main.lua as they are part of the
-- main loop's state management.
-->8
-- src/1.player.lua (Corrected filename in comment)
--#globals player_manager STASH_SIZE create_player Player -- Added STASH_SIZE, create_player, Player to globals for clarity if used by other files directly.
-- Ensure player_manager is treated as the global table defined in 0.init.lua

local Player = {}
Player.__index = Player -- For metatable inheritance

-- Constructor for a new player object
function Player:new(id, initial_score, color, ghost_color) -- Added initial_score
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {}, -- Remains for any other logic, but HUD uses stash_counts
    stash_counts = {}, -- Initialize as an empty table (map)
    captured_pieces_count = 0 
  }
  -- Initialize stash_counts with STASH_SIZE pieces of the player's own color
  instance.stash_counts[color] = STASH_SIZE or 6

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
  if self.stash_counts[piece_color] == nil then
    self.stash_counts[piece_color] = 0
  end
  self.stash_counts[piece_color] += 1

  -- Keep self.stash for compatibility or other logic if needed, though HUD uses stash_counts
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
function Player:use_piece_from_stash(piece_color_to_use)
  if self.stash_counts[piece_color_to_use] and self.stash_counts[piece_color_to_use] > 0 then
    self.stash_counts[piece_color_to_use] -= 1
    printh("P"..self.id.." used piece color "..piece_color_to_use..". Stash count: "..(self.stash_counts[piece_color_to_use] or 0)) -- DEBUG
    
    -- Also update the old self.stash table for consistency if it's used elsewhere
    if self.stash[piece_color_to_use] and self.stash[piece_color_to_use] > 0 then
      self.stash[piece_color_to_use] -= 1
    end
    return true
  else
    printh("P"..self.id.." has no pieces of color "..piece_color_to_use.." in stash_counts.") -- DEBUG
    return false
  end
end

-- Module-level table player_manager is already defined globally in 0.init.lua
-- We are adding functions to it.
-- REMOVED: player_manager = {} -- This was overwriting the global instance.

player_manager.colors = {
  [1] = 12, -- Player 1: Light Blue
  [2] = 8,  -- Player 2: Red (Pico-8 color 8 is red)
  [3] = 11, -- Player 3: Green
  [4] = 10  -- Player 4: Yellow
}

-- Ghost/Cursor colors
player_manager.ghost_colors = {
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
    local ghost_color = player_manager.ghost_colors[i]
    if not color then
      printh("Warning: No color defined for player " .. i .. ". Defaulting to white (7).")
      color = 7
    end
    if not ghost_color then
      printh("Warning: No ghost color defined for player " .. i .. ". Defaulting to dark blue (1).")
      ghost_color = 1
    end
    -- Player:new uses global STASH_SIZE, which should be set before this by menu/game init
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color)
  end
end

-- Function to get a player's instance
function player_manager.get_player(player_id)
  if not player_manager.current_players then
     printh("Accessing player_manager.current_players before init_players?")
     return nil
  end
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
  if not player_manager.current_players then return 0 end
  return #player_manager.current_players
end

-- Expose Player class if other modules need to create players or check type (optional)
-- Player = Player
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

function _check_attacker_hit_defender(attacker_obj, defender_obj, player_manager_param, ray_segment_intersect_func, current_laser_len, add_func)
  local attacker_vertices = attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices == 0 then return end
  local apex = attacker_vertices[1]
  local dir_x = cos(attacker_obj.orientation) -- cos is global via --#globals
  local dir_y = sin(attacker_obj.orientation) -- sin is global via --#globals

  local defender_corners = defender_obj:get_draw_vertices()
  if not defender_corners or #defender_corners == 0 then return end

  for j = 1, #defender_corners do
    local k = (j % #defender_corners) + 1
    local ix, iy, t = ray_segment_intersect_func(apex.x, apex.y, dir_x, dir_y,
                                                 defender_corners[j].x, defender_corners[j].y,
                                                 defender_corners[k].x, defender_corners[k].y)
    if t and t >= 0 and t <= current_laser_len then
      defender_obj.hits = (defender_obj.hits or 0) + 1
      defender_obj.targeting_attackers = defender_obj.targeting_attackers or {}
      add_func(defender_obj.targeting_attackers, attacker_obj)

      local attacker_player = player_manager_param.get_player(attacker_obj.owner_id)
      local defender_player = player_manager_param.get_player(defender_obj.owner_id)

      if attacker_player and defender_player and attacker_obj.owner_id ~= defender_obj.owner_id then
        attacker_player:add_score(1)
      end

      if defender_obj.hits == 1 then
        defender_obj.state = "successful"
      elseif defender_obj.hits == 2 then
        defender_obj.state = "unsuccessful"
      elseif defender_obj.hits >= 3 then
        defender_obj.state = "overcharged"
      end
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
    p_obj.dbg_target_count = num_total_attackers_targeting

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

  -- Score attackers hitting defenders
  for _, attacker_obj in ipairs(pieces) do -- Use global 'pieces' directly
    if attacker_obj and attacker_obj.type == "attacker" then
      for _, defender_obj in ipairs(pieces) do -- Use global 'pieces' directly
        if defender_obj and defender_obj.type == "defender" then
          -- Pass global variables directly to the helper function
          _check_attacker_hit_defender(attacker_obj, defender_obj, player_manager, ray_segment_intersect, LASER_LEN, add)
        end
      end
    end
  end

  -- Score defenders based on incoming attackers
  for _, p_obj in ipairs(pieces) do -- Use global 'pieces' directly
    -- Pass global 'player_manager' directly
    _score_defender(p_obj, player_manager)
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

-- Renamed from score_pieces to update_game_state to reflect broader scope
update_game_state = score_pieces
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
      -- Gather available colors in stash
      local available_colors = {}
      -- Use stash_counts (the map) instead of stash (the old array)
      if current_player_obj and current_player_obj.stash_counts then
        for color, count in pairs(current_player_obj.stash_counts) do
          if count > 0 then add(available_colors, color) end
        end
      end
      -- If no color, fallback to player's own color
      if #available_colors == 0 then available_colors = {current_player_obj:get_color()} end
      -- Clamp color_select_idx
      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      -- Cycle color selection with up/down
      if btnp(⬆️, i - 1) then
        cur.color_select_idx = cur.color_select_idx - 1
        if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end
      elseif btnp(⬇️, i - 1) then
        cur.color_select_idx = cur.color_select_idx + 1
        if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
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
      cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_color()

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
        cur.pending_orientation = 0
        cur.pending_type = "defender"
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count menu_option menu_player_count menu_stash_size game_timer tostring rectfill min type pairs ipairs btnp max STASH_SIZE

ui = {}
-- NP and PM can remain cached if N_PLAYERS and player_manager are set before this file loads
local NP, PM = N_PLAYERS, player_manager

function ui.draw_main_menu()
  cls(0)
  print("P8PANIC", 48, 20, 7)
  local options = {
    "Players: " .. (menu_player_count or N_PLAYERS or 2), -- Use global menu_player_count
    "Stash Size: " .. (menu_stash_size or STASH_SIZE or 3), -- Use global menu_stash_size
    "Game Timer: " .. (game_timer or 3) .. " min", -- Add game timer option
    "Start Game",
    "How To Play"
  }
  for i, opt in ipairs(options) do
    local y = 40 + i * 10
    local col = (menu_option == i and 11) or 7 -- Use global menu_option
    print(opt, 20, y, col)
    if menu_option == i then -- Use global menu_option
      print("\136", 10, y, 11) -- draw a yellow arrow (character 136)
    end
  end
end

-- Draw how-to-play screen
function ui.draw_how_to_play()
  cls(0)
  print("HOW TO PLAY", 30, 20, 7)
  print("Use arrows to navigate", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
end

function ui.draw_game_hud()
  local screen_w = 128
  local screen_h = 128
  local margin = 5
  local line_h = 6 -- Standard Pico-8 font height (5px char + 1px spacing)

  local corners = {
    -- P1: Top-Left (score at y, stash below)
    { x = margin, y = margin, align_right = false, stash_y_multiplier = 1 },
    -- P2: Top-Right (score at y, stash below)
    { x = screen_w - margin, y = margin, align_right = true, stash_y_multiplier = 1 },
    -- P3: Bottom-Left (score at y, stash above)
    { x = margin, y = screen_h - margin - line_h, align_right = false, stash_y_multiplier = -1 },
    -- P4: Bottom-Right (score at y, stash above)
    { x = screen_w - margin, y = screen_h - margin - line_h, align_right = true, stash_y_multiplier = -1 }
  }

  for i = 1, NP or 1 do
    local p = PM and PM.current_players and PM.current_players[i]
    if p then
      local corner_cfg = corners[i]
      if not corner_cfg then goto continue_loop end

      local current_x_anchor = corner_cfg.x
      local score_print_y = corner_cfg.y
      local align_right = corner_cfg.align_right

      -- 1. Print Score
      local score_val = p.score or 0
      local score_text_prefix = "" -- "SCORE " removed
      local score_text_full = score_text_prefix .. score_val
      local print_x_score
      if align_right then
        print_x_score = current_x_anchor - (#score_text_full * 4)
      else
        print_x_score = current_x_anchor
      end
      print(score_text_full, print_x_score, score_print_y, p.color or 7)

      -- 2. Print Stash Bars
      local bar_width = 2 -- Remains 2, as per previous modification
      local bar_h_spacing = 1 
      local effective_bar_step = bar_width + bar_h_spacing
      local stash_item_max_height = 8

      local num_distinct_colors = 0
      if type(p.stash_counts) == "table" then
        for _color, count_val in pairs(p.stash_counts) do
          if count_val > 0 then -- Only count if a bar will be drawn
            num_distinct_colors = num_distinct_colors + 1
          end
        end
      end

      local total_stash_block_width
      if num_distinct_colors > 0 then
        total_stash_block_width = (num_distinct_colors * bar_width) + ((num_distinct_colors - 1) * bar_h_spacing)
      else
        total_stash_block_width = 0
      end
      
      -- Updated debug print for Player 1's stash_counts to handle map-like table
      if p.id == 1 then
        local debug_stash_text = "P1 SC: " .. type(p.stash_counts)
        if type(p.stash_counts) == "table" then
          debug_stash_text = debug_stash_text .. " {"
          local first_entry = true
          for c_key, c_val in pairs(p.stash_counts) do
            if not first_entry then debug_stash_text = debug_stash_text .. ", " end
            debug_stash_text = debug_stash_text .. tostring(c_key) .. ":" .. tostring(c_val)
            first_entry = false
          end
          debug_stash_text = debug_stash_text .. "}"
        end
        print(debug_stash_text, 1, screen_h - margin - 5, 7) 
      end

      local block_render_start_x
      if align_right then
        block_render_start_x = current_x_anchor - total_stash_block_width
      else
        block_render_start_x = current_x_anchor
      end

      if type(p.stash_counts) == "table" and num_distinct_colors > 0 then
        local bar_idx = 0
        for piece_color, count in pairs(p.stash_counts) do
          if count > 0 then
            local item_actual_color = piece_color
            
            local bar_height = min(count, stash_item_max_height)
            local current_bar_x_start_offset = bar_idx * effective_bar_step
            local current_bar_x_start = block_render_start_x + current_bar_x_start_offset
            local current_bar_x_end = current_bar_x_start + bar_width - 1

            if corner_cfg.stash_y_multiplier == 1 then
              local bar_top_y = score_print_y + line_h
              rectfill(current_bar_x_start, bar_top_y, current_bar_x_end, bar_top_y + bar_height - 1, item_actual_color)
            else
              local bar_bottom_y = score_print_y - 1
              rectfill(current_bar_x_start, bar_bottom_y - bar_height + 1, current_bar_x_end, bar_bottom_y, item_actual_color)
            end
            bar_idx = bar_idx + 1
          end
        end
      end
    end
    ::continue_loop::
  end
end
 
-- Draw the How To Play screen
function ui.draw_how_to_play() -- Keep this instance
  cls(0)
  print("HOW TO PLAY", 30, 20, 7)
  -- Placeholder instructions
  print("Use arrows to navigate menu", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
end

function ui.update_main_menu_logic() -- Renamed from _update_main_menu_logic
  -- Navigate options
  if btnp(1) then menu_option = min(5, menu_option + 1) end -- right, increased max to 5
  if btnp(0) then menu_option = max(1, menu_option - 1) end -- left
  -- Adjust values
  if menu_option == 1 then
    if btnp(2) then menu_player_count = min(4, menu_player_count + 1) end -- up
    if btnp(3) then menu_player_count = max(2, menu_player_count - 1) end -- down
  elseif menu_option == 2 then
    if btnp(2) then menu_stash_size = min(10, menu_stash_size + 1) end -- up
    if btnp(3) then menu_stash_size = max(3, menu_stash_size - 1) end -- down
  elseif menu_option == 3 then -- Adjust game timer
    if btnp(2) then game_timer = min(10, game_timer + 1) end -- up, max 10 minutes
    if btnp(3) then game_timer = max(1, game_timer - 1) end -- down, min 1 minute
  end
  -- Select option
  if btnp(5) then -- ❎ (X)
    if menu_option == 4 then -- Adjusted start game option index
      player_count = menu_player_count
      stash_count = menu_stash_size
      N_PLAYERS = menu_player_count
      STASH_SIZE = menu_stash_size
      -- game_timer is already set
      global_game_state = "in_game"
      printh("Starting game from menu with P:"..player_count.." S:"..stash_count.." T:"..game_timer)
    elseif menu_option == 5 then -- Adjusted how to play option index
      global_game_state = "how_to_play"
    end
  end
end
-->8
-- src/7.cursor.lua
--#eval player_manager=player_manager,rectfill=rectfill,circfill=circfill,line=line,cos=cos,sin=sin,print=print,create_piece=create_piece

-- Default cursor properties
local default_cursor_props = {
  control_state = 0, -- CSTATE_MOVE_SELECT (as defined in 5.controls.lua)
  pending_type = "defender",
  pending_orientation = 0,
  color_select_idx = 1,
  return_cooldown = 0,
  -- spawn_x, spawn_y will be set by create_cursor
  -- pending_color will be set based on player or selection
}

function create_cursor(player_id, initial_x, initial_y)
  local p_ghost_color = 7 -- Default color if player_manager or method is missing
  if player_manager and player_manager.get_player_ghost_color then
    local player = player_manager.get_player(player_id) -- Get the player object first
    if player and player.get_ghost_color then
      p_ghost_color = player:get_ghost_color()
    elseif player_manager.get_player_ghost_color then -- Fallback to old direct method if exists
      p_ghost_color = player_manager.get_player_ghost_color(player_id)
    else
      printh("Warning: Could not get ghost color for P"..player_id)
    end
  else
    printh("Warning: player_manager or get_player_ghost_color not available for cursor.")
  end
  
  local cur = {
    id = player_id,
    x = initial_x,
    y = initial_y,
    spawn_x = initial_x, -- Store spawn position
    spawn_y = initial_y,
    
    -- Initialize properties from defaults
    control_state = default_cursor_props.control_state,
    pending_type = default_cursor_props.pending_type,
    pending_orientation = default_cursor_props.pending_orientation,
    pending_color = p_ghost_color, -- Default to player's ghost color
    color_select_idx = default_cursor_props.color_select_idx,
    return_cooldown = default_cursor_props.return_cooldown,

    draw = function(self)
      -- Placeholder cursor drawing: a small rectangle
      -- rectfill(self.x, self.y, self.x + 1, self.y + 1, self.pending_color) -- Keep or remove as desired

      if self.pending_type == "attacker" or self.pending_type == "defender" then
        -- Draw ghost piece
        local ghost_piece_params = {
          owner_id = self.id,
          type = self.pending_type,
          position = { x = self.x + 4, y = self.y + 4 }, -- Centered on cursor
          orientation = self.pending_orientation,
          color = self.pending_color,
          is_ghost = true -- Add a flag to indicate this is a ghost piece for drawing
        }
        -- Assuming create_piece returns a piece object with a draw method
        local ghost_piece = create_piece(ghost_piece_params)
        if ghost_piece and ghost_piece.draw then
          ghost_piece:draw()
        end
      elseif self.pending_type == "capture" then
        -- Render crosshair
        local crosshair_color = self.pending_color
        if player_manager and player_manager.get_player then
            local p = player_manager.get_player(self.id)
            if p and p.get_color then
                crosshair_color = p:get_color()
            end
        end
        local cx, cy = self.x + 4, self.y + 4 -- Center of the 8x8 cursor grid
        local arm_len = 3
        -- Horizontal line
        line(cx - arm_len, cy, cx + arm_len, cy, crosshair_color)
        -- Vertical line
        line(cx, cy - arm_len, cx, cy + arm_len, crosshair_color)
        -- Optional: small circle in the middle
        -- circfill(cx, cy, 1, crosshair_color)
      end

      -- If in rotation/placement mode, show pending piece outline (simplified)
      -- This might be redundant if ghost piece is already drawn above
      -- if self.control_state == 1 then -- CSTATE_ROTATE_PLACE
      --    -- This would be more complex, showing the actual piece shape and orientation
      --    line(self.x+4, self.y+4, self.x+4 + cos(self.pending_orientation)*8, self.y+4 + sin(self.pending_orientation)*8, self.pending_color)
      -- end
    end
  }
  return cur
end

-- PICO-8 automatically makes functions global if they are not declared local
-- So, create_cursor will be global by default.
-->8
-- src/8.main.lua
-- Main game loop functions (_init, _update, _draw)

--#globals player_manager pieces cursors ui N_PLAYERS STASH_SIZE global_game_state game_timer time flr string add table
--#globals menu_option menu_player_count menu_stash_size player_count stash_count
--#globals create_player create_cursor internal_update_game_logic update_game_logic update_controls
--#globals original_update_game_logic_func original_update_controls_func update_game_state
--#globals printh all cls btnp menuitem print

-- Ensure ui_handler is assigned from the global ui table from 6.ui.lua
local ui_handler -- local to this file, assigned in _init

local game_start_time = 0
local remaining_time_seconds = 0

------------------------------------------
-- Main Pico-8 Functions
------------------------------------------
function _init()
  -- Initialize engine-level managers/tables if they aren\'t already by other files
  -- (player_manager, pieces, cursors are expected to be globals defined elsewhere or initialized here)
  -- player_manager should be globally defined by 0.init.lua
  -- pieces should be globally defined by 0.init.lua
  -- cursors should be globally defined by 0.init.lua
  
  if player_manager == nil then 
    printh("CRITICAL: player_manager is nil in _init of 7.main.lua!")
    player_manager = {} -- Fallback, but indicates load order issue
  end
  if pieces == nil then pieces = {} end
  if cursors == nil then cursors = {} end
  
  if ui then
    ui_handler = ui
  else 
    printh("Warning: global 'ui' (from 6.ui.lua) not found in _init. UI might not draw.")
    ui_handler = {
      draw_main_menu = function() print("NO UI - MAIN MENU", 40,60,8) end,
      draw_game_hud = function() print("NO UI - GAME HUD", 40,60,8) end,
      draw_how_to_play = function() print("NO UI - HOW TO PLAY", 20,60,8) end,
      update_main_menu_logic = function() printh("Warning: NO UI - update_main_menu_logic not called") end
    }
  end

  menuitem(1, "Return to Main Menu", function()
    global_game_state = "main_menu" 
    printh("Returning to main menu via pause menu...")
    _init_main_menu_state() 
  end)

  -- Add game timer to menu item
  menuitem(2, "Set Timer: " .. (game_timer or 3) .. " min", function()
    -- This is a placeholder, actual timer setting is in _update_main_menu_logic
    -- but we need a menu item for it to be visible in pause menu if desired.
    -- Or, remove this if timer is only set from main menu.
  end)

  if global_game_state == "main_menu" then
    _init_main_menu_state()
  else
    -- If starting directly in game (e.g. for testing, by changing default global_game_state)
    -- N_PLAYERS and STASH_SIZE should be their default values from 0.init.lua
    player_count = N_PLAYERS
    stash_count = STASH_SIZE
    init_game_properly()
  end
end

function _update()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    else
      printh("Warning: ui_handler.update_main_menu_logic not found!")
    end
    if global_game_state == "in_game" then
      -- N_PLAYERS and STASH_SIZE have been set by menu logic
      init_game_properly()
    elseif global_game_state == "how_to_play" then
      -- handled below
    end
  elseif global_game_state == "how_to_play" then
    -- return to menu on X
    if btnp(5) then
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  elseif global_game_state == "in_game" then
    _update_game_logic()

    -- Timer logic
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/30 -- Pico-8 runs at 30 FPS
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        global_game_state = "game_over"
        printh("Game Over! Time is up.")
        -- Determine winner(s) - can be moved to a separate function
        local max_score = -1
        local winners = {}
        for i=1, N_PLAYERS do
          local p = player_manager.get_player(i)
          if p then
            if p.score > max_score then
              max_score = p.score
              winners = {p.id}
            elseif p.score == max_score then
              add(winners, p.id)
            end
          end
        end
        printh("Winner(s): " .. table.concat(winners, ", ") .. " with score: " .. max_score)
        -- You might want to display this on screen too
      end
    end
  elseif global_game_state == "game_over" then
    -- Wait for a button press to return to main menu
    if btnp(5) then -- (X) button
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  end
end

function _draw()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    else
      cls(0) print("Error: draw_main_menu not found!", 20,60,8)
    end
  elseif global_game_state == "how_to_play" then
    if ui_handler and ui_handler.draw_how_to_play then
      ui_handler.draw_how_to_play()
    else
      cls(0) print("Error: draw_how_to_play not found!", 20,60,8)
    end
  elseif global_game_state == "in_game" then
    _draw_game_screen()
  elseif global_game_state == "game_over" then
    cls(0)
    print("GAME OVER!", 48, 50, 8)
    -- Display winner information (this is basic, enhance as needed)
    local max_score = -1
    local winner_text = "WINNER(S): "
    -- Recalculate or store winners from _update
    -- For simplicity, let's assume winners are stored in a global or passed
    -- For now, just a generic message
    -- TODO: Display actual winners and scores
    print("Time is up!", 45, 60, 7)
    print("Press (X) to return", 28, 100, 7)
  end
end

------------------------------------------
-- Menu Specific Logic (Initialization & Update)
------------------------------------------
function _init_main_menu_state()
  menu_option = 1 
  -- Use global N_PLAYERS and STASH_SIZE as defaults for the menu
  menu_player_count = N_PLAYERS 
  menu_stash_size = STASH_SIZE   
  -- game_timer is already a global, potentially set by previous menu interaction
  printh("Main menu state initialized: P=" .. menu_player_count .. " S=" .. menu_stash_size .. " T:" .. game_timer)
end

-- This function is now in 6.ui.lua, but if you need overrides or specific logic here, keep it.
-- For now, assuming 6.ui.lua handles menu updates.
-- function _update_main_menu_logic()
--   -- ... (logic moved to 6.ui.lua) ...
-- end

------------------------------------------
-- Game Specific Logic (Initialization, Update, Draw)
------------------------------------------
function init_game_properly()
  if player_manager and player_manager.init_players then
    player_manager.init_players(N_PLAYERS) 
  else
    printh("CRITICAL Error: player_manager.init_players not found! Player module likely failed.")
    -- Minimal fallback to prevent immediate crash, but game won\'t be right.
    player_manager = player_manager or {} -- Ensure it exists
    player_manager.current_players = {}
    player_manager.get_player = function(id) return player_manager.current_players[id] end
    -- This fallback won\'t have proper player objects from Player:new
  end

  pieces = {} 
  cursors = {} 
  for i = 1, N_PLAYERS do
    -- create_cursor should be a global function from its respective module
    if create_cursor then
      cursors[i] = create_cursor(i, 60 + i * 10, 60) 
    else
      printh("Error: create_cursor function not found!")
      -- Corrected dummy cursor draw function
      cursors[i] = { 
        id=i, 
        x=60+i*10, 
        y=60, 
        draw=function(self) print("C"..self.id,self.x,self.y,7) end 
      } -- Dummy cursor
    end
  end

  -- Assign control functions
  if update_controls then 
    original_update_controls_func = update_controls
    printh("Assigned original_update_controls_func from global update_controls.")
  else
    printh("Warning: global function 'update_controls' (from 5.controls.lua) not found. Controls might not work.")
    original_update_controls_func = function() end 
  end
  
  -- Assign game logic update function (example: from 2.scoring.lua or similar)
  -- Assuming the main game logic update function is named 'update_game_state' or similar from another module
  if update_game_state then -- Example name, adjust if your game logic func is different
    original_update_game_logic_func = update_game_state 
    printh("Assigned original_update_game_logic_func from global update_game_state.")
  else
    printh("Warning: global 'update_game_state' (core game logic) not found. Game logic may not run.")
    original_update_game_logic_func = function() end 
  end

  -- Initialize timer
  game_start_time = time() -- Assuming time() gives seconds or a consistent unit
  remaining_time_seconds = (game_timer or 3) * 60 -- Convert minutes to seconds
  printh("Timer started: " .. remaining_time_seconds .. " seconds.")

  printh("Game initialized with " .. N_PLAYERS .. " players and " .. STASH_SIZE .. " pieces each.")
end

function _update_game_logic()
  if original_update_game_logic_func then
    original_update_game_logic_func() 
  end
  if original_update_controls_func then
    original_update_controls_func() 
  end
end

function _draw_game_screen()
  cls(0) 

  -- Draw timer
  local minutes = flr(remaining_time_seconds / 60)
  local seconds = flr(remaining_time_seconds % 60)
  local seconds_str
  if seconds < 10 then
    seconds_str = "0" .. tostr(seconds)
  else
    seconds_str = tostr(seconds)
  end
  local timer_str = tostr(minutes) .. ":" .. seconds_str
  print(timer_str, 128 - #timer_str * 4 - 5, 5, 7) -- Top-right, adjust x as needed

  if pieces then
    for piece_obj in all(pieces) do
      if piece_obj and piece_obj.draw then
        piece_obj:draw()
      end
    end
  end

  if cursors then
    for _, cursor_obj in pairs(cursors) do -- Use pairs for sparse arrays or non-numeric keys
      if cursor_obj and cursor_obj.draw then
        cursor_obj:draw()
      end
    end
  end

  if ui_handler and ui_handler.draw_game_hud then
    ui_handler.draw_game_hud()
  else
    print("Error: ui_handler.draw_game_hud not found",0,0,7)
  end
end

-- Ensure create_player is globally available if Player:new is not directly exposed
-- and player_manager.init_players relies on a global create_player
-- This is usually defined in 1.player.lua or similar.
-- If Player:new is used directly by player_manager.init_players, this isn\'t needed here.
-- function create_player(id, stash_size_val) -- Example, ensure this matches actual create_player
--   if Player and Player.new then
--     return Player:new(id, 0, player_manager.colors[id], player_manager.ghost_colors[id])
--   end
--   printh("Error: Player or Player:new not found for create_player")
--   return {id=id, score=0, color=7, stash={}} -- Dummy
-- end
__gfx__
cccccccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccccccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccccccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccccccc000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
cccccccccc0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
ccccccccc00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888888000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888880000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

