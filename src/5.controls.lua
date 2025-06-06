local CSTATE_MOVE_SELECT,CSTATE_ROTATE_PLACE,CSTATE_COOLDOWN=0,1,2

function update_controls()
 for i,cur in ipairs(cursors)do
  local p=player_manager.get_player(i)
  if not p or p.is_cpu then goto next_cursor_ctrl end
  
  local es=true
  if p and p.stash then
   for _,cnt in pairs(p.stash)do if cnt>0 then es=false break end end
  end
  local hd=false
  if pieces then
   for _,po in pairs(pieces)do
    if po.owner_id==i and po.type=="defender"and po.state=="successful"then hd=true break end
   end
  end
  local fa="normal"
  if es then
   cur.pending_type="capture"
   fa="capture_only"
  elseif not hd then
   cur.pending_type="defender"
   cur.pending_color=p:get_color()
   fa="must_place_defender"
  end
  if cur.control_state==0 and btnp(🅾️,i-1)and fa=="normal"then
   cur.pending_type=cur.pending_type=="defender"and"attacker"or cur.pending_type=="attacker"and"capture"or"defender"
   cur.pending_orientation = 0
   if effects and effects.switch_mode then sfx(effects.switch_mode)end
  end

  p.capture_mode = (cur.pending_type == "capture")

  if cur.control_state == 0 then
   local spd=cursor_speed
   if btn(⬅️,i-1)then cur.x=max(0,cur.x-spd)
   elseif btnp(⬅️,i-1)then cur.x=max(0,cur.x-1)end
   if btn(➡️,i-1)then cur.x=min(cur.x+spd,120)
   elseif btnp(➡️,i-1)then cur.x=min(cur.x+1,120)end
   if btn(⬆️,i-1)then cur.y=max(0,cur.y-spd)
   elseif btnp(⬆️,i-1)then cur.y=max(0,cur.y-1)end
   if btn(⬇️,i-1)then cur.y=min(cur.y+spd,120)
   elseif btnp(⬇️,i-1)then cur.y=min(cur.y+1,120)end

   if btnp(❎,i-1)then
    if cur.pending_type=="capture"then
     if attempt_capture(p,cur)then
      cur.control_state,cur.return_cooldown=2,6
      if original_update_game_logic_func then original_update_game_logic_func()end
     end
    else
     cur.control_state=1
     if effects and effects.enter_placement then sfx(effects.enter_placement)end
    end
   end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if fa == "must_place_defender" then
        add(available_colors, p:get_color())
        cur.color_select_idx = 1
      else
        if p and p.stash then
          for color, count in pairs(p.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      if #available_colors == 0 and p and p:has_piece_in_stash(p:get_color()) then
         add(available_colors, p:get_color())
      elseif #available_colors == 0 then
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl
      end

      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      if fa ~= "must_place_defender" then
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

      if fa == "must_place_defender" then
        cur.pending_color = p:get_color()
      else
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or p:get_ghost_color()
        else
            cur.pending_color = p:get_ghost_color() 
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
        if place_piece(piece_params, p) then
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
        cur.pending_color = (p and p:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end