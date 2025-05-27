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
