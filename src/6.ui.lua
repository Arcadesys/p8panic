-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count tostring

ui = {}

function ui.draw_main_menu()
  cls(0) -- Clear screen with black
  
  -- Simple title and instruction
  print("P8PANIC", 48, 40, 7) -- White text
  print("PRESS (X) TO START", 30, 60, 7) -- White text
  
  -- Placeholder for future menu options
  -- print("Players: " .. player_count, 10, 80, 7)
  -- print("Stash: " .. stash_count, 10, 90, 7)
end

function ui.draw_game_hud()
  -- DEBUG: Check N_PLAYERS and player_manager status (commented out)
  -- local pm_text = "PM_T: " .. type(player_manager)
  -- if type(player_manager) == "table" then
  --   local key_count = 0
  --   for _ in pairs(player_manager) do key_count = key_count + 1 end
  --   pm_text = pm_text .. " PM_KEYS: " .. key_count
  --   if type(player_manager.current_players) == "table" then
  --     pm_text = pm_text .. " CUR_P_T: table CUR_P_#: " .. #player_manager.current_players
  --   else
  --     pm_text = pm_text .. " CUR_P_T: " .. type(player_manager.current_players)
  --   end
  -- end
  -- print("N_P:"..tostring(N_PLAYERS).." " .. pm_text, 1, 1, 13) -- Print debug info at top-left

  local screen_w = 128
  local screen_h = 128
  local margin = 5
  local line_h = 6 -- Standard Pico-8 font height (5px char + 1px spacing)

  local corners = {
    -- P1: Top-Left (score at y, stash below)
    { x = margin, y = margin, align_right = false, stash_y_multiplier = 1 },
    -- P2: Top-Right (score at y, stash below)
    { x = screen_w - margin, y = margin, align_right = true, stash_y_multiplier = 1 },
    -- P3: Bottom-Left (score at y, stash above)
    { x = margin, y = screen_h - margin - line_h, align_right = false, stash_y_multiplier = -1 },
    -- P4: Bottom-Right (score at y, stash above)
    { x = screen_w - margin, y = screen_h - margin - line_h, align_right = true, stash_y_multiplier = -1 }
  }

  -- Configuration for stash item display colors
  local stash_slot_colors = {
    7,  -- Slot 1: White
    12, -- Slot 2: Dark Blue
    7,  -- Slot 3: Default to White
    7   -- Slot 4: Default to White
  }

  for i = 1, N_PLAYERS do
    local p = player_manager.current_players and player_manager.current_players[i]
    if p then
      local corner_cfg = corners[i]
      if not corner_cfg then goto continue_loop end

      local current_x_anchor = corner_cfg.x
      local score_print_y = corner_cfg.y
      local align_right = corner_cfg.align_right

      -- 1. Print Score
      local score_val = p.score or 0
      local score_text_prefix = "SCORE "
      local score_text_full = score_text_prefix .. score_val
      
      local print_x_score
      if align_right then
        print_x_score = current_x_anchor - (#score_text_full * 4) -- Approx char width 4px
      else
        print_x_score = current_x_anchor
      end
      -- Print score with player's color, fallback to white (7)
      print(score_text_full, print_x_score, score_print_y, p.color or 7)

      -- 2. Print Stash (up to 4 items/counts)
      for k = 1, 4 do
        local stash_item_y = score_print_y + (k * line_h * corner_cfg.stash_y_multiplier)
        local count = (p.stash_counts and p.stash_counts[k]) or 0
        
        if count > 0 then -- Only display if count is positive
          local item_text = tostring(count)
          local item_color = stash_slot_colors[k] or 7 -- Fallback to white
          
          local print_x_item
          if align_right then
            print_x_item = current_x_anchor - (#item_text * 4)
          else
            print_x_item = current_x_anchor
          end
          print(item_text, print_x_item, stash_item_y, item_color)
        end
      end
    end
    ::continue_loop::
  end
end
