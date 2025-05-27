pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
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
-->8
--cursor.lua

--handles cursor movement, mode changes, and piece selection
local cursor = {
    position = { x = 0, y = 0 },
    mode = "defender", -- "attacker", "defender", or "capture"
    selected_piece = nil
}
-->8
-- src/6.collision.lua
-- Handles collision detection and finding safe spots.
-- luacheck: globals all min max abs flr

-- Checks if two rectangles overlap
-- rect = {x, y, w, h}
function check_rect_overlap(r1, r2)
  if not r1 or not r2 or not r1.x or not r1.y or not r1.w or not r1.h or not r2.x or not r2.y or not r2.w or not r2.h then
    -- print("invalid rect in check_rect_overlap") -- Optional debug
    return false
  end
  return r1.x < r2.x + r2.w and
         r1.x + r1.w > r2.x and
         r1.y < r2.y + r2.h and
         r1.y + r1.h > r2.y
end

-- Checks if a given area is occupied by any piece in the list
-- x, y, w, h: define the area to check (e.g., cursor)
-- all_pieces_list: table of piece objects
function is_area_occupied(x, y, w, h, all_pieces_list)
  local check_rect = {x=x, y=y, w=w, h=h}
  if not all_pieces_list then return false end

  for piece_to_check in all(all_pieces_list) do
    if piece_to_check and piece_to_check.position then
      local piece_rect = {
        x = piece_to_check.position.x,
        y = piece_to_check.position.y,
        w = 8, -- Assuming all pieces are 8x8
        h = 8
      }
      if check_rect_overlap(check_rect, piece_rect) then
        return true -- Area is occupied
      end
    end
  end
  return false -- Area is clear
end

-- Finds a safe teleport location for the cursor
-- placed_x, placed_y: coordinates of the piece just placed
-- item_w, item_h: width/height of pieces and cursor (e.g., 8x8)
-- all_pieces_list: table of all pieces on the board
-- board_w, board_h: dimensions of the game board (e.g., 128x128)
function find_safe_teleport_location(placed_x, placed_y, item_w, item_h, all_pieces_list, board_w, board_h)
  local max_search_radius_grid = max(flr(board_w/item_w), flr(board_h/item_h))
  local placed_gx = flr(placed_x / item_w)
  local placed_gy = flr(placed_y / item_h)

  for r = 1, max_search_radius_grid do
    local unique_points_grid = {}
    local visited_coords = {} -- To store "gx_gy" strings to ensure uniqueness

    local function add_unique_grid_point(gx, gy)
      local key = gx .. "_" .. gy
      if not visited_coords[key] then
        -- Check if the grid point is within board grid boundaries
        if gx >= 0 and gx < flr(board_w/item_w) and gy >= 0 and gy < flr(board_h/item_h) then
          add(unique_points_grid, {gx=gx, gy=gy})
          visited_coords[key] = true
        end
      end
    end

    -- Iterate points on the perimeter of a square of radius r (in grid cells)
    for i = -r, r do
      add_unique_grid_point(placed_gx + i, placed_gy - r) -- Top edge
      add_unique_grid_point(placed_gx + i, placed_gy + r) -- Bottom edge
    end
    for i = -r + 1, r - 1 do -- Sides, excluding corners already covered
      add_unique_grid_point(placed_gx - r, placed_gy + i) -- Left edge
      add_unique_grid_point(placed_gx + r, placed_gy + i) -- Right edge
    end

    for pt_grid in all(unique_points_grid) do
      local cand_cx = pt_grid.gx * item_w
      local cand_cy = pt_grid.gy * item_h
      
      -- This check is implicitly handled by add_unique_grid_point's boundary check for gx,gy
      -- if cand_cx >= 0 and cand_cx <= board_w - item_w and
      --    cand_cy >= 0 and cand_cy <= board_h - item_h then
      if not is_area_occupied(cand_cx, cand_cy, item_w, item_h, all_pieces_list) then
        return cand_cx, cand_cy -- Found a safe spot
      end
      -- end
    end
  end

  -- Fallback: if spiral search fails, try a simple scan of the whole board
  for gy_grid = 0, flr(board_h/item_h) - 1 do
    for gx_grid = 0, flr(board_w/item_w) - 1 do
      local cx = gx_grid * item_w
      local cy = gy_grid * item_h
      if not (cx == placed_x and cy == placed_y) then -- Ensure it's not the exact spot just placed
        if not is_area_occupied(cx, cy, item_w, item_h, all_pieces_list) then
          return cx, cy
        end
      end
    end
  end
  
  -- If still no spot (board is completely full, or only placed_piece spot left),
  -- it's problematic. Return nil, or current cursor pos to not move.
  return nil, nil 
end
-->8
--placement
function legal_placement(piece_to_place)
    -- Configuration for placement logic
    local defender_width = 8
    local defender_height = 8
    local attacker_triangle_height = 8
    local attacker_triangle_base = 6
    local board_w = 128
    local board_h = 128

    -- Helper: Vector subtraction v1 - v2
    function vec_sub(v1, v2)
        return {x = v1.x - v2.x, y = v1.y - v2.y}
    end

    -- Helper: Vector dot product
    function vec_dot(v1, v2)
        return v1.x * v2.x + v1.y * v2.y
    end

    -- Helper: Get the world-space coordinates of a piece's corners
    function get_rotated_vertices(piece)
        local o = piece.orientation
        -- For placement, piece.position is the intended center of the piece.
        local cx = piece.position.x
        local cy = piece.position.y

        local local_corners = {}

        if piece.type == "attacker" then
            local h = attacker_triangle_height
            local b = attacker_triangle_base
            -- Apex: (h/2, 0) relative to center, along orientation
            -- Base 1: (-h/2, b/2)
            -- Base 2: (-h/2, -b/2)
            add(local_corners, {x = h/2, y = 0})
            add(local_corners, {x = -h/2, y = b/2})
            add(local_corners, {x = -h/2, y = -b/2})
        else -- Defender (square)
            local w, h = defender_width, defender_height
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

    -- Helper: Project vertices onto an axis and return min/max projection
    function project_vertices(vertices, axis)
        local min_proj = vec_dot(vertices[1], axis)
        local max_proj = min_proj
        for i = 2, #vertices do
            local proj = vec_dot(vertices[i], axis)
            if proj < min_proj then min_proj = proj
            elseif proj > max_proj then max_proj = proj
            end
        end
        return min_proj, max_proj
    end

    -- Helper: Check for Oriented Bounding Box (OBB) collision using Separating Axis Theorem (SAT)
    function check_obb_collision(piece1, piece2)
        local vertices1 = get_rotated_vertices(piece1)
        local vertices2 = get_rotated_vertices(piece2)

        local axes = {}
        -- Axes from piece1 (normals to edges)
        -- Edge from v1 to v2: (v2.x - v1.x, v2.y - v1.y)
        -- Normal: (-(v2.y - v1.y), v2.x - v1.x)
        local edge1_1 = vec_sub(vertices1[2], vertices1[1])
        add(axes, {x = -edge1_1.y, y = edge1_1.x}) -- Normal to first edge
        local edge1_2 = vec_sub(vertices1[4], vertices1[1]) -- Use adjacent edge for the other normal
        add(axes, {x = -edge1_2.y, y = edge1_2.x}) -- Normal to second edge

        -- Axes from piece2
        local edge2_1 = vec_sub(vertices2[2], vertices2[1])
        add(axes, {x = -edge2_1.y, y = edge2_1.x})
        local edge2_2 = vec_sub(vertices2[4], vertices2[1])
        add(axes, {x = -edge2_2.y, y = edge2_2.x})

        for axis in all(axes) do
            -- Normalize axis (optional for SAT, but good for consistency if using penetration depth)
            -- local len = sqrt(axis.x^2 + axis.y^2)
            -- if len > 0 then axis.x /= len; axis.y /= len end

            local min1, max1 = project_vertices(vertices1, axis)
            local min2, max2 = project_vertices(vertices2, axis)

            -- Check for non-overlap
            if max1 < min2 or max2 < min1 then
                return false -- Separating axis found, no collision
            end
        end
        return true -- No separating axis found, collision
    end

    -- 1. Boundary Check: Ensure all corners of the piece are within board limits
    local world_corners = get_rotated_vertices(piece_to_place)
    if not world_corners or #world_corners < 3 then return false end -- Not enough vertices

    for corner in all(world_corners) do
        if corner.x < 0 or corner.x > board_w or
           corner.y < 0 or corner.y > board_h then
            -- flr.print("Boundary fail: x="..corner.x.." y="..corner.y,0,0,7) -- Debug
            return false -- Piece is out of bounds
        end
    end

    -- 2. Intersection Check: Ensure the piece doesn't collide with existing pieces
    -- 'pieces' is assumed to be a global table of already placed pieces
    if pieces then -- Check if the 'pieces' table exists and has items
        for existing_piece in all(pieces) do
            -- No need to check piece_to_place against itself if it were already in 'pieces',
            -- but for a new placement, it won't be.
            if check_obb_collision(piece_to_place, existing_piece) then
                -- flr.print("Collision fail",0,8,7) -- Debug
                return false -- Collides with an existing piece
            end
        end
    end

    return true -- Placement is legal
end

function redraw_lasers()
    --when we place a new piece, we need to recalculate the score.
end

function place_piece(piece)
    if legal_placement(piece) then
        add(pieces, piece)
        redraw_lasers()
    end
end
-->8
--ui
-->8
-- src/5.menu.lua

menu_active = true
selected_players = 3 -- Default to 3 players
min_players = 3
max_players = 4

selected_stash_size = 6 -- Default to 6
min_stash_size = 3
max_stash_size = 10

menu_options = {
  {text = "Players", value_key = "selected_players", min_val = min_players, max_val = max_players},
  {text = "Stash Size", value_key = "selected_stash_size", min_val = min_stash_size, max_val = max_stash_size},
  {text = "Start Game"}
}
current_menu_selection_index = 1 -- 1-based index

function _update_menu_controls()
  if not menu_active then return end

  local option_changed = false

  -- Navigate menu options (using player 0 controls: d-pad buttons 2 for up, 3 for down)
  if btnp(2) then -- Up
    current_menu_selection_index = current_menu_selection_index - 1
    if current_menu_selection_index < 1 then
      current_menu_selection_index = #menu_options
    end
  elseif btnp(3) then -- Down
    current_menu_selection_index = current_menu_selection_index + 1
    if current_menu_selection_index > #menu_options then
      current_menu_selection_index = 1
    end
  end

  local current_option = menu_options[current_menu_selection_index]

  -- Change option values or start game
  if current_option.value_key then -- This option has a value to change (Players or Stash Size)
    local current_value_for_option
    if current_option.value_key == "selected_players" then
      current_value_for_option = selected_players
    elseif current_option.value_key == "selected_stash_size" then
      current_value_for_option = selected_stash_size
    end

    -- Use d-pad buttons 0 for left, 1 for right
    if btnp(0) then -- Left
      current_value_for_option = current_value_for_option - 1
      if current_value_for_option < current_option.min_val then
        current_value_for_option = current_option.min_val
      end
      option_changed = true
    elseif btnp(1) then -- Right
      current_value_for_option = current_value_for_option + 1
      if current_value_for_option > current_option.max_val then
        current_value_for_option = current_option.max_val
      end
      option_changed = true
    end

    if option_changed then
      if current_option.value_key == "selected_players" then
        selected_players = current_value_for_option
      elseif current_option.value_key == "selected_stash_size" then
        selected_stash_size = current_value_for_option
      end
    end
  elseif current_option.text == "Start Game" then -- This is the "Start Game" option
    -- Use action buttons 4 (O) or 5 (X)
    if btnp(4) or btnp(5) then
      menu_active = false
      -- Game will start on the next frame because menu_active is false.
      -- Game initialization logic (e.g. creating cursors)
      -- will need to read selected_players and selected_stash_size.
    end
  end
end

function _draw_main_menu()
  if not menu_active then return end

  cls(1) -- Dark blue background (PICO-8 color 1)

  -- Title
  print("p8panic", 48, 10, 7) -- White text (PICO-8 color 7)

  local menu_start_y = 30
  local line_height = 10

  for i, option in ipairs(menu_options) do
    local color = 7 -- Default color: White
    local prefix = "  "
    if i == current_menu_selection_index then
      color = 8 -- Highlight color: Red (PICO-8 color 8)
      prefix = "> "
    end

    local text_to_draw = prefix .. option.text
    if option.value_key then
      local value_display
      if option.value_key == "selected_players" then
        value_display = selected_players
      elseif option.value_key == "selected_stash_size" then
        value_display = selected_stash_size
      end
      text_to_draw = text_to_draw .. ": < " .. value_display .. " >"
    end

    print(text_to_draw, 20, menu_start_y + (i-1)*line_height, color)
  end

  -- Instructions
  local instruction_y = 100
  print("use d-pad to navigate", 10, instruction_y, 6)       -- Light grey (PICO-8 color 6)
  print("left/right to change", 10, instruction_y + 8, 6)
  print("o/x to start", 10, instruction_y + 16, 6)
end
-->8
-- controls.lua: handles cursor movement, rotation, and placement/cancel logic
-- luacheck: globals btn btnp max min add cursor_x cursor_y pieces current_player find_safe_teleport_location board_w board_h all

-- state: 0 = move, 1 = rotate/confirm
control_state = 0
pending_orientation = 0 -- Angle in PICO-8 format (0-1 for 0-360 degrees, 0 is right/east)
-- To make 0 = Up for easier visual start, we can initialize to 0.75 (270 degrees)
pending_orientation = 0.75
pending_color = 1 -- Default to player 1\'s color, or current_player
pending_type = "defender" -- "defender" or "attacker"

-- Helper function to wrap angle between 0 and 1
function wrap_angle(angle)
  return (angle % 1 + 1) % 1
end

local rotation_speed = 0.02 -- Adjust for faster/slower rotation

function update_controls()
  if control_state == 0 then
    if btn(0) then cursor_x = max(cursor_x-1, 0) end
    if btn(1) then cursor_x = min(cursor_x+1, 128-8) end
    if btn(2) then cursor_y = max(cursor_y-1, 0) end
    if btn(3) then cursor_y = min(cursor_y+1, 128-8) end

    -- Toggle piece type with secondary (🅾️/X/5) in movement mode
    if btnp(5) then
      if pending_type == "defender" then
        pending_type = "attacker"
      else
        pending_type = "defender"
      end
      -- Optionally, add some feedback like a sound or visual cue for type change
    end

    -- enter rotation/confirmation mode with primary (❎/Z/4)
    if btnp(4) then
      control_state = 1
      -- pending_orientation is kept from previous rotation
      pending_color = current_player or 1 -- Start with current player's color
    end
  elseif control_state == 1 then
    -- Rotate with left/right (continuous rotation)
    if btn(0) then -- Holding left
      pending_orientation = wrap_angle(pending_orientation - rotation_speed)
    end
    if btn(1) then -- Holding right
      pending_orientation = wrap_angle(pending_orientation + rotation_speed)
    end

    -- Select color with up/down (cycles through 1-4 for now)
    -- TODO: Integrate stash availability check
    if btnp(2) then pending_color = (pending_color - 1 -1 + 4) % 4 + 1 end -- Cycle P4->P3->P2->P1 then P4
    if btnp(3) then pending_color = (pending_color % 4) + 1 end -- Cycle P1->P2->P3->P4 then P1

    -- Place with primary
    if btnp(4) then
      local placed_piece_x = cursor_x
      local placed_piece_y = cursor_y
      -- Place at the center of the cell (assuming 8x8 grid)
      add(pieces, {
        owner = pending_color, -- Use selected color
        type = pending_type, -- Use selected type
        position = { x = placed_piece_x + 4, y = placed_piece_y + 4 },
        orientation = pending_orientation -- Store the angle
      })
      control_state = 0 -- Return to movement mode
      -- pending_orientation is kept for next placement attempt

      -- Teleport cursor to a safe spot
      -- Assuming board_w and board_h are available globally or passed appropriately
      -- For now, let's assume 128x128 board and 8x8 pieces/cursor
      local new_cursor_x, new_cursor_y = find_safe_teleport_location(placed_piece_x, placed_piece_y, 8, 8, pieces, 128, 128)
      if new_cursor_x and new_cursor_y then
        cursor_x = new_cursor_x
        cursor_y = new_cursor_y
      else
        -- Handle case where no safe spot is found (e.g., log or keep cursor)
        -- print("no safe spot found!")
      end
    end

    -- Cancel (exit placement mode) with secondary (🅾️/X/5), keep orientation
    if btnp(5) then
      control_state = 0
      -- pending_orientation is already preserved
    end
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
2122222222222222222222222222222300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

