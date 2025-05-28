-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count tostring rectfill min type pairs

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
        print_x_score = current_x_anchor - (#score_text_full * 4)
      else
        print_x_score = current_x_anchor
      end
      print(score_text_full, print_x_score, score_print_y, p.color or 7)

      -- 2. Print Stash Bars
      local bar_width = 4
      local bar_h_spacing = 1 -- Horizontal space between bars
      local effective_bar_step = bar_width + bar_h_spacing
      local stash_item_max_height = 8
      local num_stash_types = 4 -- Assuming 4 types/slots for stash items
      local total_stash_block_width = (num_stash_types * bar_width) + ((num_stash_types - 1) * bar_h_spacing)

      -- Debug print for Player 1's stash_counts
      if p.id == 1 then
        local debug_stash_text = "P1 SC: " .. type(p.stash_counts)
        if type(p.stash_counts) == "table" then
          debug_stash_text = debug_stash_text .. " #" .. #p.stash_counts .. "{"
          for si=1, #p.stash_counts do -- Iterate up to actual length if less than 4
            debug_stash_text = debug_stash_text .. (p.stash_counts[si] or "nil") .. (si < #p.stash_counts and "," or "")
          end
          debug_stash_text = debug_stash_text .. "}"
        end
        print(debug_stash_text, 1, screen_h - margin - 5, 7) -- Print at bottom-left
      end

      local block_render_start_x
      if align_right then
        block_render_start_x = current_x_anchor - total_stash_block_width
      else
        block_render_start_x = current_x_anchor
      end

      for k = 1, num_stash_types do
        local count = (p.stash_counts and p.stash_counts[k]) or 0
        local item_color = stash_slot_colors[k] or 7
        
        if count > 0 then
          local bar_height = min(count, stash_item_max_height)
          local current_bar_x_start = block_render_start_x + (k-1) * effective_bar_step
          local current_bar_x_end = current_bar_x_start + bar_width - 1

          if corner_cfg.stash_y_multiplier == 1 then -- Bars go down from score line
            local bar_top_y = score_print_y + line_h -- Start Y for the bar (below score text's allocated line_h)
            rectfill(current_bar_x_start, bar_top_y, current_bar_x_end, bar_top_y + bar_height - 1, item_color)
          else -- Bars go up from score line (stash_y_multiplier == -1)
            local bar_bottom_y = score_print_y - 1 -- End Y for the bar (above score text's allocated line_h)
            rectfill(current_bar_x_start, bar_bottom_y - bar_height + 1, current_bar_x_end, bar_bottom_y, item_color)
          end
        end
      end
    end
    ::continue_loop::
  end
end
