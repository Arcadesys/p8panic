local CSTATE_MOVE_SELECT=0
local CSTATE_ROTATE_PLACE=1
local CSTATE_COOLDOWN=2
function update_controls()
  if controls_disabled then return end
  local cursor_speed=2
  local rotation_speed=0.02
  for i,cur in ipairs(cursors)do
    local current_player_obj=player_manager.get_player(i)
    if not current_player_obj then goto next_cursor_ctrl end
    if cur.control_state==CSTATE_MOVE_SELECT then
      if btn(⬅️,i-1)then cur.x=max(0,cur.x-cursor_speed)end
      if btn(➡️,i-1)then cur.x=min(cur.x+cursor_speed,128-8)end
      if btn(⬆️,i-1)then cur.y=max(0,cur.y-cursor_speed)end
      if btn(⬇️,i-1)then cur.y=min(cur.y+cursor_speed,128-8)end

      if btnp(🅾️,i-1)then
        if cur.pending_type=="defender"then
          cur.pending_type="attacker"
        elseif cur.pending_type=="attacker"then
          cur.pending_type="capture"
        elseif cur.pending_type=="capture"then
          cur.pending_type="defender"
        end
      end

      if btnp(❎,i-1)then
        if cur.pending_type=="capture"then
          if attempt_capture(current_player_obj,cur)then
            cur.control_state=CSTATE_COOLDOWN;cur.return_cooldown=6
            if original_update_game_logic_func then original_update_game_logic_func()end
          end
        else
          cur.control_state=CSTATE_ROTATE_PLACE
          cur.pending_orientation=0
        end
      end
    elseif cur.control_state==CSTATE_ROTATE_PLACE then
      local available_colors={}
      if current_player_obj and current_player_obj.stash_counts then
        for color,count in pairs(current_player_obj.stash_counts)do
          if count>0 then add(available_colors,color)end
        end
      end
      if #available_colors==0 then available_colors={current_player_obj:get_color()}end
      if cur.color_select_idx>#available_colors then cur.color_select_idx=1 end
      if cur.color_select_idx<1 then cur.color_select_idx=#available_colors end

      if btnp(⬆️,i-1)then
        cur.color_select_idx=cur.color_select_idx-1
        if cur.color_select_idx<1 then cur.color_select_idx=#available_colors end
      elseif btnp(⬇️,i-1)then
        cur.color_select_idx=cur.color_select_idx+1
        if cur.color_select_idx>#available_colors then cur.color_select_idx=1 end
      end

      if btn(⬅️,i-1)then
        cur.pending_orientation=cur.pending_orientation-rotation_speed
        if cur.pending_orientation<0 then cur.pending_orientation=cur.pending_orientation+1 end
      end
      if btn(➡️,i-1)then
        cur.pending_orientation=cur.pending_orientation+rotation_speed
        if cur.pending_orientation>=1 then cur.pending_orientation=cur.pending_orientation-1 end
      end

      cur.pending_color=available_colors[cur.color_select_idx]or current_player_obj:get_color()

      if btnp(❎,i-1)then
        local piece_params={
          owner_id=i,
          type=cur.pending_type,
          position={x=cur.x+4,y=cur.y+4},
          orientation=cur.pending_orientation,
          color=cur.pending_color
        }
        if place_piece(piece_params,current_player_obj)then
          cur.control_state=CSTATE_COOLDOWN
          cur.return_cooldown=6
          if original_update_game_logic_func then original_update_game_logic_func()end
        end
      end
      if btnp(🅾️,i-1)then
        cur.control_state=CSTATE_MOVE_SELECT
      end

    elseif cur.control_state==CSTATE_COOLDOWN then
      cur.return_cooldown=cur.return_cooldown-1
      if cur.return_cooldown<=0 then
        cur.x=cur.spawn_x
        cur.y=cur.spawn_y
        cur.control_state=CSTATE_MOVE_SELECT
        cur.pending_orientation=0
        cur.pending_type="defender"
        cur.pending_color=(current_player_obj and current_player_obj:get_ghost_color())or 7
      end
    end
    ::next_cursor_ctrl::
  end
end