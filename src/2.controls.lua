-- controls.lua: handles cursor movement, rotation, and placement/cancel logic
-- luacheck: globals btn btnp max min add cursor_x cursor_y pieces current_player

-- state: 0 = move, 1 = rotate/confirm
control_state = 0
pending_orientation = 0
pending_color = 1 -- Default to player 1's color, or current_player

function update_controls()
  if control_state == 0 then
    if btn(0) then cursor_x = max(cursor_x-1, 0) end
    if btn(1) then cursor_x = min(cursor_x+1, 128-8) end
    if btn(2) then cursor_y = max(cursor_y-1, 0) end
    if btn(3) then cursor_y = min(cursor_y+1, 128-8) end
    -- enter rotation/confirmation mode with primary (❎/Z/4)
    if btnp(4) then
      control_state = 1
      -- pending_orientation is kept from previous rotation or defaults if not set
      pending_color = current_player or 1 -- Start with current player's color
    end
  elseif control_state == 1 then
    -- Rotate with left/right
    if btnp(0) then pending_orientation = (pending_orientation - 1 + 4) % 4 end -- Ensure positive result for modulo
    if btnp(1) then pending_orientation = (pending_orientation + 1) % 4 end

    -- Select color with up/down (cycles through 1-4 for now)
    -- TODO: Integrate stash availability check
    if btnp(2) then pending_color = (pending_color - 1 -1 + 4) % 4 + 1 end -- Cycle P4->P3->P2->P1 then P4
    if btnp(3) then pending_color = (pending_color % 4) + 1 end -- Cycle P1->P2->P3->P4 then P1

    -- Place with primary
    if btnp(4) then
      add(pieces, {
        owner = pending_color, -- Use selected color
        type = "defender", -- Assuming defender for now, will need to adapt for attackers
        position = { x = cursor_x, y = cursor_y },
        orientation = pending_orientation
      })
      control_state = 0 -- Return to movement mode
      -- pending_orientation is kept for next placement attempt
    end

    -- Cancel (exit placement mode) with secondary (🅾️/X/5), keep orientation
    if btnp(5) then
      control_state = 0
      -- pending_orientation is already preserved
    end
  end
end
