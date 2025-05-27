--p8panic
--A game of tactical geometry.

-- luacheck: globals cls btn btnp rect rectfill add all max min
cursor_x=64-4
cursor_y=64-4
pieces={}

-- Piece dimensions (consistent with placement.lua)
local piece_width = 8
local piece_height = 8

-- Helper function to get rotated vertices for drawing
-- (Similar to the one in placement.lua, but might be adapted for drawing needs if different)
function get_piece_draw_vertices(piece)
    local w, h = piece_width, piece_height -- Or from piece.type if dynamic
    local x, y = piece.position.x, piece.position.y
    local o = piece.orientation -- PICO-8 orientation (0-1)

    -- Center of the piece for rotation
    local cx = x + w / 2
    local cy = y + h / 2

    -- Half-width and half-height
    local hw = w / 2
    local hh = h / 2

    -- Local corner coordinates (relative to center, before rotation)
    -- Order: top-left, top-right, bottom-right, bottom-left
    local local_corners = {
        {x = -hw, y = -hh}, {x = hw, y = -hh},
        {x = hw, y = hh},   {x = -hw, y = hh}
    }

    local world_corners = {}
    for lc in all(local_corners) do
        -- PICO-8 cos/sin use 0..1 for angle
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
  -- draw defenders
  for p in all(pieces) do
    if p.type=="defender" then
      local vertices = get_piece_draw_vertices(p)
      -- Draw the rotated piece by connecting its vertices
      line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, 7) -- Top edge
      line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, 7) -- Right edge
      line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, 7) -- Bottom edge
      line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, 7) -- Left edge
    end
  end

  -- draw cursor / placement preview
  -- control_state and pending_orientation are global vars from 6.controls.lua
  if control_state == 1 then -- Rotate/confirm mode
    local cursor_preview_piece = {
      position = { x = cursor_x, y = cursor_y },
      orientation = pending_orientation,
      -- type = "cursor" -- Not strictly needed for get_piece_draw_vertices if width/height are fixed
    }
    local vertices = get_piece_draw_vertices(cursor_preview_piece)
    -- Draw the rotated cursor preview (e.g., in a different color or style)
    -- Using color 13 (pink) for preview
    line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, 13)
    line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, 13)
    line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, 13)
    line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, 13)
  else -- Movement mode
    -- Draw cursor outline as a simple square
    rect(cursor_x,cursor_y,cursor_x+7,cursor_y+7,7)
  end
end
