-- controls.lua: handles cursor movement, rotation, and placement/cancel logic
-- luacheck: globals btn btnp max min add del pieces cursor_x cursor_y current_player find_safe_teleport_location board_w board_h all

-- state: 0 = move, 1 = rotate/confirm
control_state = 0
pending_orientation = 0.75 -- Default to Up
pending_color = 1 -- Default to player 1's color
pending_type = "defender" -- "defender", "attacker", or "capture"

-- Helper function to wrap angle between 0 and 1
function wrap_angle(angle)
  return (angle % 1 + 1) % 1
end

local rotation_speed = 0.02 -- Adjust for faster/slower rotation

-- New function for capture logic
local function attempt_capture_at_cursor()
  local captured_anything = false
  for i = #pieces, 1, -1 do -- Iterate backwards for safe removal
    local p = pieces[i]
    if p.type == "attacker" then
      local dist_sq = (cursor_x + 4 - p.position.x)^2 + (cursor_y + 4 - p.position.y)^2
      if dist_sq < (8*8) then -- Arbitrary capture radius (e.g., within 8 pixels)
        -- TODO: Add to player's stash
        del(pieces, p)
        captured_anything = true
        -- print("captured attacker!") -- Debug
        -- No need to change control_state here, stays in movement mode
        break -- Capture one piece at a time
      end
    end
  end
  if not captured_anything then
    -- print("nothing to capture here") -- Debug
    -- Potentially play a 'fail' sound
  end
  -- After an attempt, whether successful or not, remain in movement mode.
  -- control_state remains 0.
end

function update_controls()
  if control_state == 0 then -- Movement mode
    if btn(0) then cursor_x = max(cursor_x-1, 0) end
    if btn(1) then cursor_x = min(cursor_x+1, 128-8) end
    if btn(2) then cursor_y = max(cursor_y-1, 0) end
    if btn(3) then cursor_y = min(cursor_y+1, 128-8) end

    -- Toggle piece type with secondary (🅾️/X/5)
    if btnp(5) then
      if pending_type == "defender" then
        pending_type = "attacker"
      elseif pending_type == "attacker" then
        pending_type = "capture"
      else -- pending_type == "capture"
        pending_type = "defender"
      end
    end

    -- Primary action (❎/Z/4)
    if btnp(4) then
      if pending_type == "capture" then
        attempt_capture_at_cursor() -- Directly attempt capture
      else -- "defender" or "attacker"
        control_state = 1 -- Enter rotation/confirmation mode
        -- pending_orientation is kept from previous rotation
        pending_color = current_player or 1 -- Start with current player's color
      end
    end

  elseif control_state == 1 then -- Rotation/Confirmation mode (only for defender/attacker)
    -- Rotate with left/right
    if btn(0) then pending_orientation = wrap_angle(pending_orientation - rotation_speed) end
    if btn(1) then pending_orientation = wrap_angle(pending_orientation + rotation_speed) end

    -- Select color with up/down
    if btnp(2) then pending_color = (pending_color - 1 -1 + 4) % 4 + 1 end
    if btnp(3) then pending_color = (pending_color % 4) + 1 end

    -- Place with primary (❎/Z/4)
    if btnp(4) then
      local placed_piece_x = cursor_x
      local placed_piece_y = cursor_y
      add(pieces, {
        owner = pending_color,
        type = pending_type,
        position = { x = placed_piece_x + 4, y = placed_piece_y + 4 },
        orientation = pending_orientation
      })
      control_state = 0 -- Return to movement mode

      local new_cursor_x, new_cursor_y = find_safe_teleport_location(placed_piece_x, placed_piece_y, 8, 8, pieces, 128, 128)
      if new_cursor_x and new_cursor_y then
        cursor_x = new_cursor_x
        cursor_y = new_cursor_y
      end
    end

    -- Cancel (exit placement mode) with secondary (🅾️/X/5)
    if btnp(5) then
      control_state = 0
      -- pending_orientation is preserved
    end
  end
end
