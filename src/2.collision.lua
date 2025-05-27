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
