local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2
  local rotation_speed = 0.02
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)


    if not current_player_obj then goto next_cursor_ctrl end

    local player_has_empty_stash = true
    if current_player_obj and current_player_obj.stash then
      for _color_id, count in pairs(current_player_obj.stash) do
        if count > 0 then
          player_has_empty_stash = false
        end
      end
    else
      player_has_empty_stash = true
    end

    local player_has_successful_defender = false
    if pieces then
      for piece_idx, p_obj in pairs(pieces) do

        if p_obj.owner_id == i and p_obj.type == "defender" and p_obj.state == "successful" then
          player_has_successful_defender = true
          break
        end
      end
    end

    local forced_action_state = "normal"

    if player_has_empty_stash then
      cur.pending_type = "capture"
      forced_action_state = "capture_only"
    elseif not player_has_successful_defender then
      cur.pending_type = "defender"
      cur.pending_color = current_player_obj:get_color()
      forced_action_state = "must_place_defender"
    end

    if cur.control_state == CSTATE_MOVE_SELECT and btnp(🅾️, i - 1) and forced_action_state == "normal" then
        local current_orientation = cur.pending_orientation
        if cur.pending_type == "defender" then
            cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
            cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
            cur.pending_type = "defender"
        end
        cur.pending_orientation = current_orientation
        if effects and effects.switch_mode then
          sfx(effects.switch_mode)
        end
    end

    if current_player_obj then
        current_player_obj.capture_mode = (cur.pending_type == "capture")
    end

    if cur.control_state == CSTATE_MOVE_SELECT then
      if btn(⬅️, i - 1) then 
        cur.x = max(0, cur.x - cursor_speed) 
      elseif btnp(⬅️, i - 1) then 
        cur.x = max(0, cur.x - 1) 
      end
      
      if btn(➡️, i - 1) then 
        cur.x = min(cur.x + cursor_speed, 128 - 8) 
      elseif btnp(➡️, i - 1) then 
        cur.x = min(cur.x + 1, 128 - 8) 
      end
      
      if btn(⬆️, i - 1) then 
        cur.y = max(0, cur.y - cursor_speed) 
      elseif btnp(⬆️, i - 1) then 
        cur.y = max(0, cur.y - 1) 
      end
      
      if btn(⬇️, i - 1) then 
        cur.y = min(cur.y + cursor_speed, 128 - 8) 
      elseif btnp(⬇️, i - 1) then 
        cur.y = min(cur.y + 1, 128 - 8) 
      end

      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end
          end
        else
          cur.control_state = CSTATE_ROTATE_PLACE
          if effects and effects.enter_placement then
            sfx(effects.enter_placement)
          end
        end
      end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if forced_action_state == "must_place_defender" then
        add(available_colors, current_player_obj:get_color())
        cur.color_select_idx = 1
      else
        if current_player_obj and current_player_obj.stash then
          for color, count in pairs(current_player_obj.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      if #available_colors == 0 and current_player_obj and current_player_obj:has_piece_in_stash(current_player_obj:get_color()) then
         add(available_colors, current_player_obj:get_color())
      elseif #available_colors == 0 then
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl
      end

      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

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

      if forced_action_state == "must_place_defender" then
        cur.pending_color = current_player_obj:get_color()
      else
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_ghost_color()
        else
            cur.pending_color = current_player_obj:get_ghost_color() 
        end
      end

      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i,
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation,
          color = cur.pending_color
        }
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = CSTATE_COOLDOWN
          cur.return_cooldown = 6
          if original_update_game_logic_func then original_update_game_logic_func() end
        end
      end

      if btnp(🅾️, i - 1) then
        cur.control_state = CSTATE_MOVE_SELECT
        if effects and effects.exit_placement then
          sfx(effects.exit_placement)
        end
      end

    elseif cur.control_state == CSTATE_COOLDOWN then
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = CSTATE_MOVE_SELECT
        cur.pending_type = "defender"
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end