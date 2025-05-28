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
