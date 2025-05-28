-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count menu_option menu_player_count menu_stash_size game_timer tostring rectfill min type pairs ipairs btnp max STASH_SIZE

ui = {}
-- NP and PM can remain cached if N_PLAYERS and player_manager are set before this file loads
local NP, PM = N_PLAYERS, player_manager

function ui.draw_main_menu()
  cls(0)
  print("P8PANIC", 48, 20, 7)
  local options = {
    "Players: " .. (menu_player_count or N_PLAYERS or 2), -- Use global menu_player_count
    "Stash Size: " .. (menu_stash_size or STASH_SIZE or 3), -- Use global menu_stash_size
    "Game Timer: " .. (game_timer or 3) .. " min", -- Add game timer option
    "Start Game",
    "How To Play"
  }
  for i, opt in ipairs(options) do
    local y = 40 + i * 10
    local col = (menu_option == i and 11) or 7 -- Use global menu_option
    print(opt, 20, y, col)
    if menu_option == i then -- Use global menu_option
      print("\136", 10, y, 11) -- draw a yellow arrow (character 136)
    end
  end
end

-- Draw how-to-play screen
function ui.draw_how_to_play()
  cls(0)
  print("HOW TO PLAY", 30, 20, 7)
  print("Use arrows to navigate", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
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

  for i = 1, NP or 1 do
    local p = PM and PM.current_players and PM.current_players[i]
    if p then
      local corner_cfg = corners[i]
      if not corner_cfg then goto continue_loop end

      local current_x_anchor = corner_cfg.x
      local score_print_y = corner_cfg.y
      local align_right = corner_cfg.align_right

      -- 1. Print Score
      local score_val = p.score or 0
      local score_text_prefix = "" -- "SCORE " removed
      local score_text_full = score_text_prefix .. score_val
      local print_x_score
      if align_right then
        print_x_score = current_x_anchor - (#score_text_full * 4)
      else
        print_x_score = current_x_anchor
      end
      print(score_text_full, print_x_score, score_print_y, p.color or 7)

      -- 2. Print Stash Bars
      local bar_width = 2 -- Remains 2, as per previous modification
      local bar_h_spacing = 1 
      local effective_bar_step = bar_width + bar_h_spacing
      local stash_item_max_height = 8

      local num_distinct_colors = 0
      if type(p.stash_counts) == "table" then
        for _color, count_val in pairs(p.stash_counts) do
          if count_val > 0 then -- Only count if a bar will be drawn
            num_distinct_colors = num_distinct_colors + 1
          end
        end
      end

      local total_stash_block_width
      if num_distinct_colors > 0 then
        total_stash_block_width = (num_distinct_colors * bar_width) + ((num_distinct_colors - 1) * bar_h_spacing)
      else
        total_stash_block_width = 0
      end
      
      local block_render_start_x
      if align_right then
        block_render_start_x = current_x_anchor - total_stash_block_width
      else
        block_render_start_x = current_x_anchor
      end

      if type(p.stash_counts) == "table" and num_distinct_colors > 0 then
        local bar_idx = 0
        for piece_color, count in pairs(p.stash_counts) do
          if count > 0 then
            local item_actual_color = piece_color
            
            local bar_height = min(count, stash_item_max_height)
            local current_bar_x_start_offset = bar_idx * effective_bar_step
            local current_bar_x_start = block_render_start_x + current_bar_x_start_offset
            local current_bar_x_end = current_bar_x_start + bar_width - 1

            if corner_cfg.stash_y_multiplier == 1 then
              local bar_top_y = score_print_y + line_h
              rectfill(current_bar_x_start, bar_top_y, current_bar_x_end, bar_top_y + bar_height - 1, item_actual_color)
            else
              local bar_bottom_y = score_print_y - 1
              rectfill(current_bar_x_start, bar_bottom_y - bar_height + 1, current_bar_x_end, bar_bottom_y, item_actual_color)
            end
            bar_idx = bar_idx + 1
          end
        end
      end
    end
    ::continue_loop::
  end
end
 
-- Draw the How To Play screen
function ui.draw_how_to_play() -- Keep this instance
  cls(0)
  print("HOW TO PLAY", 30, 20, 7)
  -- Placeholder instructions
  print("Use arrows to navigate menu", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
end

function ui.update_main_menu_logic() -- Renamed from _update_main_menu_logic
  -- Navigate options
  if btnp(1) then menu_option = min(5, menu_option + 1) end -- right, increased max to 5
  if btnp(0) then menu_option = max(1, menu_option - 1) end -- left
  -- Adjust values
  if menu_option == 1 then
    if btnp(2) then menu_player_count = min(4, menu_player_count + 1) end -- up
    if btnp(3) then menu_player_count = max(2, menu_player_count - 1) end -- down
  elseif menu_option == 2 then
    if btnp(2) then menu_stash_size = min(10, menu_stash_size + 1) end -- up
    if btnp(3) then menu_stash_size = max(3, menu_stash_size - 1) end -- down
  elseif menu_option == 3 then -- Adjust game timer
    if btnp(2) then game_timer = min(10, game_timer + 1) end -- up, max 10 minutes
    if btnp(3) then game_timer = max(1, game_timer - 1) end -- down, min 1 minute
  end
  -- Select option
  if btnp(5) then -- ❎ (X)
    if menu_option == 4 then -- Adjusted start game option index
      player_count = menu_player_count
      stash_count = menu_stash_size
      N_PLAYERS = menu_player_count
      STASH_SIZE = menu_stash_size
      -- game_timer is already set
      global_game_state = "in_game"
      printh("Starting game from menu with P:"..player_count.." S:"..stash_count.." T:"..game_timer)
    elseif menu_option == 5 then -- Adjusted how to play option index
      global_game_state = "how_to_play"
    end
  end
end
