-- /Users/arcades/Code/p8panic/src/3.controls.lua
-- Handles player input and updates control-related game state.

-- luacheck: globals btn btnp cursor_x cursor_y control_state pending_type pending_color pending_orientation current_player pieces
-- luacheck: globals place_piece LASER_LEN player get_piece_draw_vertices ray_segment_intersect -- Add other globals if needed by controls

-- Constants for control states (optional, but can make code clearer)
-- local CSTATE_MOVE_SELECT = 0
-- local CSTATE_ROTATE_PLACE = 1
-- local CSTATE_COOLDOWN = 2 -- Example for a post-action cooldown

function update_controls()
  -- Cursor movement speed
  local cursor_speed = 2 -- pixels per frame; adjust as needed
  local rotation_speed = 0.02 -- rotation amount per frame; adjust

  -- --- Player Input Handling ---
  -- This example assumes 'current_player' (0-indexed) determines which player's input is read.
  -- You might have a more complex player turn system.

  -- Movement State (control_state == 0)
  if control_state == 0 then
    -- Cursor Movement (D-pad)
    if btn(⬅️, current_player) then cursor_x -= cursor_speed end -- Using btn for continuous movement
    if btn(➡️, current_player) then cursor_x += cursor_speed end
    if btn(⬆️, current_player) then cursor_y -= cursor_speed end
    if btn(⬇️, current_player) then cursor_y += cursor_speed end

    -- Clamp cursor to screen boundaries (assuming 8x8 cursor, 128x128 screen)
    cursor_x = max(0, min(cursor_x, 128 - 8))
    cursor_y = max(0, min(cursor_y, 128 - 8))

    -- Cycle piece/action type (e.g., Button 🅾️ - O)
    if btnp(🅾️, current_player) then
      if pending_type == "defender" then
        pending_type = "attacker"
      elseif pending_type == "attacker" then
        pending_type = "capture" -- Or cycle back to defender if no capture mode
      elseif pending_type == "capture" then
        pending_type = "defender"
      end
      -- Potentially update pending_color based on current_player if not already set
      -- pending_color = player.colors[current_player+1] or 7 -- Assuming player.colors is 1-indexed
    end

    -- Initiate placement/rotation (e.g., Button ❎ - X)
    if btnp(❎, current_player) then
      if pending_type == "capture" then
        -- Handle capture logic here
        -- e.g., find piece at cursor_x, cursor_y and attempt to capture it
        -- For now, let's assume capture mode switches back or does something else
        -- print("Capture attempt at: "..cursor_x..","..cursor_y)
      else
        -- Switch to rotation/placement state for defender or attacker
        control_state = 1
        pending_orientation = 0 -- Reset orientation when starting placement
        -- Set pending_color based on current_player if you have player colors
        -- pending_color = player.colors[current_player+1] or 7 -- Assuming player.colors is 1-indexed
      end
    end

  -- Rotation/Placement State (control_state == 1)
  elseif control_state == 1 then
    -- Rotate pending piece (e.g., D-pad left/right)
    if btn(⬅️, current_player) then -- Using btn for continuous rotation if held
      pending_orientation -= rotation_speed
      if pending_orientation < 0 then pending_orientation += 1 end
    end
    if btn(➡️, current_player) then
      pending_orientation += rotation_speed
      if pending_orientation >= 1 then pending_orientation -= 1 end
    end

    -- Confirm placement (e.g., Button ❎ - X)
    if btnp(❎, current_player) then
      local piece_to_place = {
        owner = pending_color, -- Should be set to current player's color
        type = pending_type,
        position = { x = cursor_x + 4, y = cursor_y + 4 }, -- Center of the 8x8 cursor
        orientation = pending_orientation
      }
      -- place_piece() is defined in 1.placement.lua and will handle legality checks
      place_piece(piece_to_place)
      
      control_state = 0 -- Return to movement/selection mode
      -- Optionally, switch to a cooldown state: control_state = CSTATE_COOLDOWN
      -- Optionally, switch player: current_player = (current_player + 1) % num_players
    end

    -- Cancel placement (e.g., Button 🅾️ - O)
    if btnp(🅾️, current_player) then
      control_state = 0 -- Return to movement/selection mode
    end
  
  -- Cooldown State (optional, example: control_state == 2)
  -- elseif control_state == CSTATE_COOLDOWN then
    -- Handle cooldown timer, then switch back to CSTATE_MOVE_SELECT
    -- cooldown_timer -= 1
    -- if cooldown_timer <= 0 then
    --   control_state = CSTATE_MOVE_SELECT
    --   -- Potentially switch player here if turns are involved
    -- end
  end
end