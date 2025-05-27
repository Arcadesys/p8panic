-- Helper: Point-in-polygon (works for convex polygons, including triangles and quads)
function point_in_polygon(px, py, vertices)
  local inside = false
  local n = #vertices
  for i=1,n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end
--p8panic
--A game of tactical geometry.

-- luacheck: globals cls btn btnp rect rectfill add all max min
cursor_x=64-4
cursor_y=64-4
pieces={}

-- Piece dimensions
local defender_width = 8
local defender_height = 8
local attacker_triangle_height = 8 -- Height along orientation axis
local attacker_triangle_base = 6   -- Base perpendicular to orientation

-- Helper function to get rotated vertices for drawing
function get_piece_draw_vertices(piece)
    local o = piece.orientation -- PICO-8 orientation (0-1)
    -- Rotation center is piece.position
    local cx = piece.position.x
    local cy = piece.position.y

    local local_corners = {}

    if piece.type == "attacker" then
        -- Attacker is a triangle: height 8 (along orientation), base 6
        -- Apex points along the orientation vector
        -- Local coords relative to (cx,cy) which is piece.position
        -- Apex: (height/2, 0)
        -- Base 1: (-height/2, base_width/2)
        -- Base 2: (-height/2, -base_width/2)
        local h = attacker_triangle_height
        local b = attacker_triangle_base
        add(local_corners, {x = h/2, y = 0})      -- Apex
        add(local_corners, {x = -h/2, y = b/2})   -- Base corner 1
        add(local_corners, {x = -h/2, y = -b/2})  -- Base corner 2
    else -- Default to defender (square)
        local w, h = defender_width, defender_height
        -- Local corner coordinates (relative to center piece.position)
        -- For a square centered at (0,0) local_pos:
        -- Top-left, top-right, bottom-right, bottom-left
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

-- delegate all input/interaction to controls.lua
function _update()
  update_controls()
end

function _draw()
  cls(0)
  -- print("#pieces: "..#pieces, 0, 0, 7) -- Debug: show number of pieces

  -- draw placed pieces
  for i=1,#pieces do
    local p = pieces[i]
    -- Debug: Print piece properties
    -- local debug_y = (i-1)*6
    -- print("p"..i.." t:"..(p.type or "NIL").." c:"..(p.owner or "NIL").." o:"..(p.orientation or "NIL"), 0, debug_y, 7)
    -- if p.position then
    --   print("x:"..(p.position.x or "NIL").." y:"..(p.position.y or "NIL"), 60, debug_y, 7)
    -- else
    --   print("pos:NIL", 60, debug_y, 7)
    -- end

    if not p or not p.position or p.orientation == nil then
      -- print("Skipping draw for invalid piece "..i, 0, 50, 8) -- Debug
      goto continue_loop -- Skip drawing this piece if essential data is missing
    end

    local vertices = get_piece_draw_vertices(p)
    if not vertices or #vertices < 3 then -- Need at least 3 for triangle
      -- print("Skipping draw for invalid vertices for piece "..i, 0, 56, 8) -- Debug
      goto continue_loop
    end

    local piece_color = 7 -- Default for defender
    if p.type == "attacker" then
      piece_color = 8 -- Red for attacker
    elseif p.type == nil then
      -- print("Warning: Piece type is nil for piece "..i, 0, 40, 13)
      piece_color = 2 -- Dark blue for nil type, to make it visible
    end

    if piece_color == 0 then
      -- print("Warning: piece_color is 0 for piece "..i.." type: "..(p.type or "nil"), 0, 48, 8)
      piece_color = 7 -- Fallback to white if color somehow became 0
    end

    -- Draw the piece by connecting its vertices
    if #vertices == 3 then -- Triangle (attacker)
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, piece_color)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, piece_color)
      line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, piece_color)

      -- Draw animated (dancing ants) laser from apex, stopping at first collision
      local nose_x = vertices[1].x
      local nose_y = vertices[1].y
      local laser_length = 64
      local o = p.orientation
      local laser_dx = cos(o)
      local laser_dy = sin(o)
      local phase = flr(time()*8)%8 -- Animate the pattern
      local hit = false
      for i=0,laser_length-1 do
        local lx = nose_x + i*laser_dx
        local ly = nose_y + i*laser_dy
        -- Check collision with all pieces except self
        for j=1,#pieces do
          local op = pieces[j]
          if op ~= p then
            local op_vertices = get_piece_draw_vertices(op)
            if point_in_polygon(lx, ly, op_vertices) then
              hit = true
              break
            end
          end
        end
        if hit then break end
        -- Reverse the flow: subtract phase instead of add
        if ((i-phase+8)%8)<4 then -- 4 on, 4 off, reversed
          pset(lx, ly, 9) -- Orange for laser
        end
      end
-- Helper: Point-in-polygon (works for convex polygons, including triangles and quads)
point_in_polygon = function(px, py, vertices)
  local inside = false
  local n = #vertices
  for i=1,n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end
    elseif #vertices == 4 then -- Square (defender)
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, piece_color)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, piece_color)
      line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, piece_color)
      line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, piece_color)
    end
    ::continue_loop::
  end

  -- Always render the ghost piece (placement preview) at the cursor, regardless of mode
  local preview_piece_type = pending_type or "defender"
  local preview_center_x = cursor_x + defender_width/2
  local preview_center_y = cursor_y + defender_height/2
  local cursor_preview_piece = {
    position = { x = preview_center_x, y = preview_center_y },
    orientation = pending_orientation,
    type = preview_piece_type
  }
  local vertices = get_piece_draw_vertices(cursor_preview_piece)
  local preview_shape_color = 13 -- Pink for defender preview
  if preview_piece_type == "attacker" then
    preview_shape_color = 10 -- Light blue for attacker preview
  end
  if #vertices == 3 then -- Triangle
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, preview_shape_color)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, preview_shape_color)
      line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, preview_shape_color)
  elseif #vertices == 4 then -- Square
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, preview_shape_color)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, preview_shape_color)
      line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, preview_shape_color)
      line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, preview_shape_color)
  end
  if preview_piece_type == "attacker" then
    -- Laser originates from the apex of the triangle (vertices[1])
    local nose_x = vertices[1].x
    local nose_y = vertices[1].y
    local laser_length = 64
    local o = cursor_preview_piece.orientation
    local laser_end_x = nose_x + laser_length * cos(o)
    local laser_end_y = nose_y + laser_length * sin(o)
    line(nose_x, nose_y, laser_end_x, laser_end_y, 9)
  end
end
