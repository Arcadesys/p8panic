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

-- luacheck: globals cls btn btnp rect rectfill add all max min pieces cursor_x cursor_y pending_type control_state pending_color pending_orientation current_player
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

    -- Draw the piece (triangle or rectangle)
    local color_to_use = p.owner or 7 -- Default to white if no owner
    if p.type == "attacker" then
      -- Draw filled triangle
      -- PICO-8 doesn't have a direct filled polygon function.
      -- We can draw 3 lines for the outline, or use a small trick for filled.
      -- For simplicity, let's use line drawing for the triangle outline.
      -- For a filled look, one might use multiple `line` calls or `circfill` if shape allows.
      -- A common way is to sort vertices by y and fill scanlines, but that's complex.
      -- Simplest for now: draw lines connecting vertices.
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, color_to_use)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, color_to_use)
      line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, color_to_use)

      -- If in capture mode, draw a purple circle around attackers
      if pending_type == "capture" then
        circ(p.position.x, p.position.y, attacker_triangle_height / 2 + 2, 13) -- Purple circle (color 13)
      end
    else -- Defender (rectangle)
      -- rectfill(p.position.x - defender_width/2, p.position.y - defender_height/2, p.position.x + defender_width/2, p.position.y + defender_height/2, color_to_use)
      -- Use polygon drawing for consistency, even for squares
      -- This requires get_piece_draw_vertices to return 4 vertices for a square
      -- For a filled quad, we can draw two triangles or use a rectfill if axis-aligned.
      -- Since it can be rotated, we draw lines for the outline.
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, color_to_use)
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, color_to_use)
      line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, color_to_use)
      line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, color_to_use)
    end

    ::continue_loop::
  end

  -- Draw cursor based on mode
  if control_state == 0 then -- Movement mode
    if pending_type == "defender" then
      rect(cursor_x, cursor_y, cursor_x + 7, cursor_y + 7, 7) -- White square for defender
    elseif pending_type == "attacker" then
      -- Draw a small triangle preview for attacker (simplified)
      local cx, cy = cursor_x + 4, cursor_y + 4 -- Center of cursor cell
      line(cx + 4, cy, cx - 2, cy - 3, 7)
      line(cx - 2, cy - 3, cx - 2, cy + 3, 7)
      line(cx - 2, cy + 3, cx + 4, cy, 7)
    elseif pending_type == "capture" then
      -- Draw a small crosshair for capture mode
      local cx, cy = cursor_x + 4, cursor_y + 4 -- Center of cursor cell
      line(cx - 2, cy, cx + 2, cy, 7) -- Horizontal line
      line(cx, cy - 2, cx, cy + 2, 7) -- Vertical line
    end
  elseif control_state == 1 then -- Rotation/Confirmation mode
    -- Draw pending piece with orientation and color
    local temp_piece = {
      owner = pending_color,
      type = pending_type,
      position = { x = cursor_x + 4, y = cursor_y + 4 },
      orientation = pending_orientation
    }
    local vertices = get_piece_draw_vertices(temp_piece)
    if vertices and #vertices >=3 then
      if temp_piece.type == "attacker" then
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, pending_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, pending_color)
        line(vertices[3].x, vertices[3].y, vertices[1].x, vertices[1].y, pending_color)
      else -- Defender
        line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, pending_color)
        line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, pending_color)
        line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, pending_color)
        line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, pending_color)
      end
    end
  end
end
