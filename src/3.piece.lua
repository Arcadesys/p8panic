Piece = {}
Piece.__index = Piece

Attacker = {}
Attacker.__index = Attacker
setmetatable(Attacker, {__index = Piece})

Defender = {}
Defender.__index = Defender
setmetatable(Defender, {__index = Piece})

DEFENDER_WIDTH = 8
DEFENDER_HEIGHT = 8
local ATTACKER_TRIANGLE_HEIGHT = 8
local ATTACKER_TRIANGLE_BASE = 6

local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

function Piece:new(o)
  o = o or {}
  o.position = o.position or {x=64, y=64}
  o.orientation = o.orientation or 0
  setmetatable(o, self)
  return o
end

function Piece:get_color()
  if self.is_ghost and self.ghost_color_override then
    return self.ghost_color_override
  end
  if self.color then
    return self.color
  end
  if self.owner_id then
    local owner_player = player_manager.get_player(self.owner_id)
    if owner_player then
      return owner_player:get_color()
    end
  end
  return 7
end

function Piece:get_draw_vertices()
  local o = self.orientation
  local cx = self.position.x
  local cy = self.position.y
  local local_corners = {}

  if self.type == "attacker" then
    local h = ATTACKER_TRIANGLE_HEIGHT
    local b = ATTACKER_TRIANGLE_BASE
    add(local_corners, {x = h/2, y = 0})
    add(local_corners, {x = -h/2, y = b/2})
    add(local_corners, {x = -h/2, y = -b/2})
  else
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

function Attacker:new(o)
  o = o or {}
  o.type = "attacker"
  o.hits = 0
  o.state = "neutral"
  o.targeting_attackers = {}
  return Piece.new(self, o)
end

function Attacker:draw()
  Piece.draw(self)

  local vertices = self:get_draw_vertices()
  if not vertices or #vertices == 0 then return end
  local apex = vertices[1]

  local dir_x = cos(self.orientation)
  local dir_y = sin(self.orientation)
  local laser_color = self:get_color()
  local laser_end_x = apex.x + dir_x * LASER_LEN
  local laser_end_y = apex.y + dir_y * LASER_LEN
  local closest_hit_t = LASER_LEN

  local hit_piece_state = nil
  local hit_piece_type = nil

  if pieces then
    for _, other_piece in ipairs(pieces) do
      if other_piece ~= self then
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
            hit_piece_state = other_piece.state
            hit_piece_type = other_piece.type
          end
        end
      end
    end
  end

  if hit_piece_state == "unsuccessful" then
    laser_color = 8
  elseif hit_piece_state == "overcharged" then
    laser_color = 10
  end

  local ant_spacing = 4
  local ant_length = 2
  local num_ants = flr(closest_hit_t / ant_spacing)
  local time_factor = time() * 20

  for i = 0, num_ants - 1 do
    local ant_start_t = (i * ant_spacing + time_factor) % closest_hit_t
    local ant_end_t = ant_start_t + ant_length
    
    if ant_end_t <= closest_hit_t then
      local ant_start_x = apex.x + dir_x * ant_start_t
      local ant_start_y = apex.y + dir_y * ant_start_t
      local ant_end_x = apex.x + dir_x * ant_end_t
      local ant_end_y = apex.y + dir_y * ant_end_t
      line(ant_start_x, ant_start_y, ant_end_x, ant_end_y, laser_color)
    else
      local segment1_end_t = closest_hit_t
      local segment1_start_x = apex.x + dir_x * ant_start_t
      local segment1_start_y = apex.y + dir_y * ant_start_t
      local segment1_end_x = apex.x + dir_x * segment1_end_t
      local segment1_end_y = apex.y + dir_y * segment1_end_t
      line(segment1_start_x, segment1_start_y, segment1_end_x, segment1_end_y, laser_color)
      
      local segment2_len = ant_end_t - closest_hit_t
      if segment2_len > 0 then
        local segment2_start_x = apex.x
        local segment2_start_y = apex.y
        local segment2_end_x = apex.x + dir_x * segment2_len
        local segment2_end_y = apex.y + dir_y * segment2_len
        line(segment2_start_x, segment2_start_y, segment2_end_x, segment2_end_y, laser_color)
      end
    end
  end
end

function Defender:new(o)
  o = o or {}
  o.type = "defender"
  o.hits = 0
  o.state = "successful"
  o.targeting_attackers = {}
  return Piece.new(self, o)
end

function Defender:draw()
  local vertices = self:get_draw_vertices()
  local color = self:get_color()
  if #vertices == 4 then
    line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, color)
    line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, color)
    line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, color)
    line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, color)
  end

  -- draw status indicator in the center
  local cx = self.position.x
  local cy = self.position.y
  
  if self.state == "successful" then
    -- draw animated check mark sprite
    if sprites and sprites.defender_successful then
      local frame_idx = flr(time() * 8) % #sprites.defender_successful + 1
      local sprite_id = sprites.defender_successful[frame_idx]
      spr(sprite_id, cx - 4, cy - 4)
    end
  elseif self.state == "unsuccessful" then
    -- draw animated X sprite
    if sprites and sprites.defender_unsuccessful then
      local frame_idx = flr(time() * 8) % #sprites.defender_unsuccessful + 1
      local sprite_id = sprites.defender_unsuccessful[frame_idx]
      spr(sprite_id, cx - 4, cy - 4)
    end
  elseif self.state == "overcharged" then
    -- draw animated purple orb
    if sprites and sprites.defender_overcharged then
      local frame_idx = flr(time() * 8) % #sprites.defender_overcharged + 1
      local sprite_id = sprites.defender_overcharged[frame_idx]
      spr(sprite_id, cx - 4, cy - 4)
    end
  end
end

function create_piece(params)
  local piece_obj
  if params.type == "attacker" then
    piece_obj = Attacker:new(params)
  elseif params.type == "defender" then
    piece_obj = Defender:new(params)
  else
    return nil
  end
  return piece_obj
end
