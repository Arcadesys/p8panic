local default_cursor_props={
  control_state=0,
  pending_type="defender",
  pending_orientation=0.25, -- Start with a useful default angle
  color_select_idx=1,
  return_cooldown=0,
}
function create_cursor(player_id,initial_x,initial_y)
  local p_color=7
  local p_ghost_color=7
  if player_manager and player_manager.get_player then
    local player=player_manager.get_player(player_id)
    if player then
      if player.get_color then
        p_color=player:get_color()
      end
      if player.get_ghost_color then
        local ghost_color_val=player:get_ghost_color()
        if ghost_color_val then
          p_ghost_color=ghost_color_val
        end
      end
    end
  end
  local cur={
    id=player_id,
    x=initial_x,
    y=initial_y,
    spawn_x=initial_x,
    spawn_y=initial_y,
    control_state=default_cursor_props.control_state,
    pending_type=default_cursor_props.pending_type,
    pending_orientation=default_cursor_props.pending_orientation,
    pending_color=p_ghost_color,
    color_select_idx=default_cursor_props.color_select_idx,
    return_cooldown=default_cursor_props.return_cooldown,
    draw=function(self)
      local cursor_color
      local current_player
      if player_manager and player_manager.get_player then
        current_player = player_manager.get_player(self.id)
        if current_player and current_player.get_color then
          cursor_color=current_player:get_color()
        end
      end
      if not cursor_color then
        cursor_color=self.pending_color
      end
      
      local cx,cy=self.x+4,self.y+4
      -- Draw X-shaped crosshair with 5-pixel size
      line(cx-2,cy-2,cx+2,cy+2,cursor_color)
      line(cx-2,cy+2,cx+2,cy-2,cursor_color)
      
      -- Show ghost piece only when applicable
      if self.pending_type=="attacker" or self.pending_type=="defender" then
        local ghost_piece_params={
          owner_id=self.id,
          type=self.pending_type,
          position={x=self.x+4,y=self.y+4},
          orientation=self.pending_orientation,
          color=self.pending_color,
          is_ghost=true
        }
        local ghost_piece=create_piece(ghost_piece_params)
        if ghost_piece and ghost_piece.draw then
          ghost_piece:draw()
        end
      end

      -- Draw purple circles around capturable ships if in capture mode
      if current_player and current_player:is_in_capture_mode() then
        if pieces then
          local found_overcharged_defender_for_player = false
          for _, my_piece in ipairs(pieces) do
            -- Condition 1: Is it MY piece, is it a DEFENDER, and is it OVERCHARGED?
            if my_piece.owner_id == self.id and my_piece.type == "defender" and my_piece.state == "overcharged" then
              found_overcharged_defender_for_player = true
              
              if my_piece.targeting_attackers and #my_piece.targeting_attackers > 0 then
                for _, attacker_to_capture in ipairs(my_piece.targeting_attackers) do
                  if attacker_to_capture and attacker_to_capture.position then
                    -- Condition 2: Is the targeting piece an ATTACKER? (Owner doesn't matter for highlighting)
                    if attacker_to_capture.type == "attacker" then -- Removed owner check attacker_to_capture.owner_id ~= self.id
                      local piece_pos = attacker_to_capture.position
                      local radius = 5 -- Attackers are triangles, 5 should be a decent radius
                      circ(piece_pos.x, piece_pos.y, radius, 14) -- Pico-8 color 14 is purple
                    end
                  end
                end
              end
            end
          end
        end
      else
        if current_player and not current_player:is_in_capture_mode() then
           -- This log can be very spammy, enable if specifically debugging capture mode toggle
        end
      end
    end
  }
  return cur
end
