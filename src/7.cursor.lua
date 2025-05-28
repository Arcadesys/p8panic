-- src/7.cursor.lua
--#eval player_manager=player_manager,rectfill=rectfill,circfill=circfill,line=line,cos=cos,sin=sin,print=print,create_piece=create_piece

-- Default cursor properties
local default_cursor_props = {
  control_state = 0, -- CSTATE_MOVE_SELECT (as defined in 5.controls.lua)
  pending_type = "defender",
  pending_orientation = 0,
  color_select_idx = 1,
  return_cooldown = 0,
  -- spawn_x, spawn_y will be set by create_cursor
  -- pending_color will be set based on player or selection
}

function create_cursor(player_id, initial_x, initial_y)
  local p_ghost_color = 7 -- Default color if player_manager or method is missing
  if player_manager and player_manager.get_player_ghost_color then
    local player = player_manager.get_player(player_id) -- Get the player object first
    if player and player.get_ghost_color then
      p_ghost_color = player:get_ghost_color()
    elseif player_manager.get_player_ghost_color then -- Fallback to old direct method if exists
      p_ghost_color = player_manager.get_player_ghost_color(player_id)
    else
      printh("Warning: Could not get ghost color for P"..player_id)
    end
  else
    printh("Warning: player_manager or get_player_ghost_color not available for cursor.")
  end
  
  local cur = {
    id = player_id,
    x = initial_x,
    y = initial_y,
    spawn_x = initial_x, -- Store spawn position
    spawn_y = initial_y,
    
    -- Initialize properties from defaults
    control_state = default_cursor_props.control_state,
    pending_type = default_cursor_props.pending_type,
    pending_orientation = default_cursor_props.pending_orientation,
    pending_color = p_ghost_color, -- Default to player's ghost color
    color_select_idx = default_cursor_props.color_select_idx,
    return_cooldown = default_cursor_props.return_cooldown,

    draw = function(self)
      -- Placeholder cursor drawing: a small rectangle
      -- rectfill(self.x, self.y, self.x + 1, self.y + 1, self.pending_color) -- Keep or remove as desired

      if self.pending_type == "attacker" or self.pending_type == "defender" then
        -- Draw ghost piece
        local ghost_piece_params = {
          owner_id = self.id,
          type = self.pending_type,
          position = { x = self.x + 4, y = self.y + 4 }, -- Centered on cursor
          orientation = self.pending_orientation,
          color = self.pending_color,
          is_ghost = true -- Add a flag to indicate this is a ghost piece for drawing
        }
        -- Assuming create_piece returns a piece object with a draw method
        local ghost_piece = create_piece(ghost_piece_params)
        if ghost_piece and ghost_piece.draw then
          ghost_piece:draw()
        end
      elseif self.pending_type == "capture" then
        -- Render crosshair
        local crosshair_color = self.pending_color
        if player_manager and player_manager.get_player then
            local p = player_manager.get_player(self.id)
            if p and p.get_color then
                crosshair_color = p:get_color()
            end
        end
        local cx, cy = self.x + 4, self.y + 4 -- Center of the 8x8 cursor grid
        local arm_len = 3
        -- Horizontal line
        line(cx - arm_len, cy, cx + arm_len, cy, crosshair_color)
        -- Vertical line
        line(cx, cy - arm_len, cx, cy + arm_len, crosshair_color)
        -- Optional: small circle in the middle
        -- circfill(cx, cy, 1, crosshair_color)
      end

      -- If in rotation/placement mode, show pending piece outline (simplified)
      -- This might be redundant if ghost piece is already drawn above
      -- if self.control_state == 1 then -- CSTATE_ROTATE_PLACE
      --    -- This would be more complex, showing the actual piece shape and orientation
      --    line(self.x+4, self.y+4, self.x+4 + cos(self.pending_orientation)*8, self.y+4 + sin(self.pending_orientation)*8, self.pending_color)
      -- end
    end
  }
  return cur
end

-- PICO-8 automatically makes functions global if they are not declared local
-- So, create_cursor will be global by default.
