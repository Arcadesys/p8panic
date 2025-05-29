-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.
--#globals player_manager cursors place_piece attempt_capture original_update_game_logic_func pieces
--#globals max min btn btnp
-- Constants for control states (optional)
local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2        -- pixels per frame; adjust as needed
  local rotation_speed = 0.02   -- rotation amount per frame; adjust

  -- Iterate through each player's cursor in the global 'cursors' table.
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)
    printh("P"..i.." CTRL: P_OBJ IS ".. (current_player_obj and "OK" or "NIL")) -- DEBUG
    if current_player_obj and current_player_obj.stash then -- DEBUG
      for k,v in pairs(current_player_obj.stash) do -- DEBUG
        printh("P"..i.." STASH: K="..k.." V="..v) -- DEBUG, no tostring
      end
    elseif current_player_obj then -- DEBUG
        printh("P"..i.." STASH IS NIL") -- DEBUG
    end -- DEBUG

    if not current_player_obj then goto next_cursor_ctrl end

    -- Determine Player Status
    local player_has_empty_stash = true
    if current_player_obj and current_player_obj.stash then
      for _color_id, count in pairs(current_player_obj.stash) do
        if count > 0 then
          player_has_empty_stash = false
          break -- Found a piece, stash is not empty
        end
      end
    else
      -- If current_player_obj is nil or stash is nil, it's effectively empty for this check
      player_has_empty_stash = true
    end

    local player_has_successful_defender = false
    if pieces then -- Ensure pieces table exists
      for piece_idx, p_obj in pairs(pieces) do -- Changed to pairs to get index for print
        -- DEBUG: Print properties of pieces being checked
        if p_obj.type == "defender" then -- Only print for defenders to reduce log spam
          printh("P"..i.." CHK_DEF: ID="..piece_idx.." OWNER="..p_obj.owner_id.." TYPE="..p_obj.type.." STATE="..p_obj.state)
        end
        if p_obj.owner_id == i and p_obj.type == "defender" and p_obj.state == "successful" then
          player_has_successful_defender = true
          printh("P"..i.." FOUND SUCCESSFUL DEFENDER: ID="..piece_idx) -- DEBUG
          break
        end
      end
    end

    local forced_action_state = "normal" -- "normal", "capture_only", "must_place_defender"

    if player_has_empty_stash then
      cur.pending_type = "capture"
      forced_action_state = "capture_only"
    elseif not player_has_successful_defender then
      cur.pending_type = "defender"
      cur.pending_color = current_player_obj:get_color()
      forced_action_state = "must_place_defender"
    end
    printh("P"..i.." FLAGS: EMPTY="..(player_has_empty_stash and "T" or "F").." HAS_DEF="..(player_has_successful_defender and "T" or "F").." FORCE_STATE="..forced_action_state) -- DEBUG

    if cur.control_state == CSTATE_MOVE_SELECT then
      -- Continuous movement with the d-pad.
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      -- Cycle piece/action type (using Button O)
      if btnp(🅾️, i - 1) and forced_action_state == "normal" then
        -- Store the current orientation to maintain it when switching types
        local current_orientation = cur.pending_orientation
        
        if cur.pending_type == "defender" then
          cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
          cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
          cur.pending_type = "defender"
        end
        
        -- Keep the same orientation when switching types
        cur.pending_orientation = current_orientation
      end

      -- Initiate placement/rotation with Button X.
      if btnp(❎, i - 1) then
        if forced_action_state == "capture_only" or cur.pending_type == "capture" then
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate immediately
          else
            printh("P" .. i .. ": Capture failed.")
          end
        elseif forced_action_state == "must_place_defender" then
          cur.control_state = CSTATE_ROTATE_PLACE
          -- pending_type and pending_color are already set
        else -- Normal state
          cur.control_state = CSTATE_ROTATE_PLACE
          -- No longer resetting orientation when starting placement
        end
      end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if forced_action_state == "must_place_defender" then
        -- Only player's own color is available
        add(available_colors, current_player_obj:get_color())
        cur.color_select_idx = 1 -- Ensure it's selected
      else
        -- Gather available colors in stash
        for color, count in pairs(current_player_obj.stash) do
          if count > 0 then add(available_colors, color) end
        end
      end
      -- If no color, fallback to player's own color
      if #available_colors == 0 then available_colors = {current_player_obj:get_color()} end
      -- Clamp color_select_idx
      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      -- Cycle color selection with up/down
      if forced_action_state ~= "must_place_defender" then
        if btnp(⬆️, i - 1) then
          cur.color_select_idx = cur.color_select_idx - 1
          if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end
        elseif btnp(⬇️, i - 1) then
          cur.color_select_idx = cur.color_select_idx + 1
          if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
        end
      end

      -- Rotate pending piece using left/right
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end

      -- Set pending_color to selected color
      if forced_action_state == "must_place_defender" then
        cur.pending_color = current_player_obj:get_color()
      else
        cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_color()
      end

      -- Confirm placement with Button X.
      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i, -- Use player index as owner_id
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation,
          color = cur.pending_color -- Add the selected color to piece_params
        }
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = CSTATE_COOLDOWN
          cur.return_cooldown = 6  -- 6-frame cooldown after placement
          if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate board state
        else
          printh("Placement failed for P" .. i)
        end
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
        -- The status checks at the start of CSTATE_MOVE_SELECT will handle pending_type and pending_color
        -- So, we can reset to a sensible default or leave as is,
        -- as it will be overridden if a forced state is active.
        cur.pending_type = "defender" -- Default, will be overridden if needed
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end