---@diagnostic disable: undefined-global

player_manager = {}
STASH_SIZE = 6
create_piece = nil
pieces = {}
LASER_LEN = 60
N_PLAYERS = 4
cursors = {}
CAPTURE_RADIUS_SQUARED = 64

global_game_state = "main_menu"

player_count = N_PLAYERS
stash_count = STASH_SIZE

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

local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

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
        for attacker_idx = #def_obj.targeting_attackers, 1, -1 do
          local attacker_to_capture = def_obj.targeting_attackers[attacker_idx]
          if attacker_to_capture then
            local dist_x = (cursor.x + 4) - attacker_to_capture.position.x
            local dist_y = (cursor.y + 4) - attacker_to_capture.position.y
            
            if (dist_x*dist_x + dist_y*dist_y) < CAPTURE_RADIUS_SQUARED then
              local captured_color = attacker_to_capture:get_color()
              player_obj:add_captured_piece(captured_color)
              
              if del(pieces, attacker_to_capture) then
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

game_timer = 3

config = {
  player_options = {2, 3, 4},
  current_players_idx = 3,

  timer_options = {1, 2, 3, 5, 10},
  current_timer_idx = 3,

  get_players_value = function()
    return config.player_options[config.current_players_idx]
  end,

  set_players_idx = function(idx)
    config.current_players_idx = idx
    N_PLAYERS = config.get_players_value()
    printh("N_PLAYERS set to: " .. N_PLAYERS)
  end,

  get_timer_value = function()
    return config.timer_options[config.current_timer_idx]
  end,

  set_timer_idx = function(idx)
    config.current_timer_idx = idx
    game_timer = config.get_timer_value()
    printh("Game timer set to: " .. game_timer .. " min")
  end
}

N_PLAYERS = config.get_players_value()
game_timer = config.get_timer_value()

