-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.

-- Constants for control states (optional)
local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2        -- pixels per frame; adjust as needed
  local rotation_speed = 0.02   -- rotation amount per frame; adjust

  -- Iterate through each player's cursor in the global 'cursors' table.
  for i, cur in ipairs(cursors) do
    -- Pico-8 controller index is (i - 1).
    if cur.control_state == CSTATE_MOVE_SELECT then
      -- Continuous movement with the d-pad.
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      -- Cycle piece/action type (using Button O)
      if btnp(🅾️, i - 1) then
        if cur.pending_type == "defender" then
          cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
          cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
          cur.pending_type = "defender"
        end
      end

      -- Initiate placement/rotation with Button X.
      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          -- (Capture logic placeholder)
        else
          cur.control_state = CSTATE_ROTATE_PLACE
          cur.pending_orientation = 0 -- Reset orientation when starting placement
        end
      end

    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      -- Rotate pending piece using d-pad.
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end

      -- Confirm placement with Button X.
      if btnp(❎, i - 1) then
        local piece_to_place = {
          owner = (player and player.colors and player.colors[i]) or 7,
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation
        }
        place_piece(piece_to_place)
        cur.control_state = CSTATE_COOLDOWN
        cur.return_cooldown = 6  -- 6-frame cooldown after placement
      end

      -- Cancel placement with Button O.
      if btnp(🅾️, i - 1) then
        cur.control_state = CSTATE_MOVE_SELECT
      end

    elseif cur.control_state == CSTATE_COOLDOWN then
      -- Decrement cooldown timer and snap cursor back to spawn when done.
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = CSTATE_MOVE_SELECT
        cur.pending_orientation = 0
        cur.pending_type = "defender"
        cur.pending_color = (player and player.ghost_colors and player.ghost_colors[i]) or 7
      end
    end
  end
end