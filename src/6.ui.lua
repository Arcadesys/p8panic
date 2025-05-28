-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count menu_option menu_player_count menu_stash_size game_timer tostring rectfill min type pairs ipairs btnp max STASH_SIZE
ui = {}
-- Removed local caching of N_PLAYERS and player_manager (NP, PM)
-- Functions will use global N_PLAYERS and player_manager directly for up-to-date values.

-- 3D wireframe pyramid for menu background
local pyr_vertices = {
  {0, -0.8, 0},    -- top
  {-1, 0.8, -1},   -- base 1
  {1, 0.8, -1},    -- base 2
  {1, 0.8, 1},     -- base 3
  {-1, 0.8, 1}     -- base 4
}
local pyr_edges = {
  {1,2},{1,3},{1,4},{1,5}, -- sides
  {2,3},{3,4},{4,5},{5,2} -- base
}
local pyr_angle_x = 0
local pyr_angle_y = 0
local pyr_angle_z = 0

function pyr_rotate_point(v, ax, ay, az)
  -- Rotate around x, y, z (Euler)
  local x, y, z = v[1], v[2], v[3]
  -- X
  local cy, sy = cos(ax), sin(ax)
  y, z = y*cy-z*sy, y*sy+z*cy
  -- Y
  local cx, sx = cos(ay), sin(ay)
  x, z = x*cx+z*sx, -x*sx+z*cx
  -- Z
  local cz, sz = cos(az), sin(az)
  x, y = x*cz-y*sz, x*sz+y*cz
  return {x, y, z}
end

function pyr_project_point(v, projection_scale)
  -- Simple perspective projection
  local viewer_z = 3
  local px = v[1] / (viewer_z - v[3])
  local py = v[2] / (viewer_z - v[3])
  return 64 + px*projection_scale, 64 + py*projection_scale
end

function draw_pyramid(size, color)
  -- Animate angles
  pyr_angle_x += 0.01
  pyr_angle_y += 0.013
  pyr_angle_z += 0.008
  -- Transform and project
  local pts2d = {}
  local current_projection_scale = size or 48 -- Default size if not provided
  for i,v in ipairs(pyr_vertices) do
    local v3 = pyr_rotate_point(v, pyr_angle_x, pyr_angle_y, pyr_angle_z)
    local sx, sy = pyr_project_point(v3, current_projection_scale)
    pts2d[i] = {sx, sy}
  end
  -- Draw edges
  local edge_color = color or 6 -- Default color if not provided
  for e in all(pyr_edges) do
    local a, b = pts2d[e[1]], pts2d[e[2]]
    line(a[1], a[2], b[1], b[2], edge_color)
  end
end

function ui.draw_main_menu()
  cls(0)
  draw_pyramid(48, 6) -- Call with default size 48 and color 6
  print("P8PANIC", 48, 20, 7)
  local options = {
    "Players: " .. (menu_player_count or N_PLAYERS or 2),
    "Stash Size: " .. (menu_stash_size or STASH_SIZE or 3),
    "Game Timer: " .. (game_timer or 3) .. " min",
    "Start Game",
    "Finish Game", -- New option
    "How To Play"
  }
  for i, opt in ipairs(options) do
    local y = 38 + i * 9 -- Adjusted y spacing slightly for more options
    local col = (menu_option == i and 11) or 7
    print(opt, 20, y, col)
    if menu_option == i then
      print("\136", 10, y, 11)
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

  for i = 1, (N_PLAYERS or 1) do -- Use global N_PLAYERS
    local p = player_manager and player_manager.current_players and player_manager.current_players[i] -- Use global player_manager
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

function ui.draw_winner_screen()
  cls(0)
  calculate_final_scores() -- Calculate final scores before displaying
  print("GAME OVER!", 44, 25, 8)

  -- Gather player scores
  local player_scores = {}
  if player_manager and player_manager.get_player and N_PLAYERS then
    for i=1,N_PLAYERS do
      local p = player_manager.get_player(i)
      if p and p.score then
        add(player_scores, {id=i, score=p.score})
      end
    end
  end

  -- Sort by score descending
  for i=1,#player_scores-1 do
    for j=i+1,#player_scores do
      if player_scores[j].score > player_scores[i].score then
        local tmp = player_scores[i]
        player_scores[i] = player_scores[j]
        player_scores[j] = tmp
      end
    end
  end

  -- Print four key/value pairs: 1st, 2nd, 3rd, 4th
  local places = {"1st", "2nd", "3rd", "4th"}
  for i=1,4 do
    local ps = player_scores[i]
    local y = 40 + i*12
    if ps then
      print(places[i]..": Player "..ps.id.."  Score: "..ps.score, 20, y, 7)
    else
      print(places[i]..": ---", 20, y, 7)
    end
  end

  print("Press (X) to return", 28, 100, 7)
end
 
-- Draw the How To Play screen
function ui.draw_how_to_play() -- Keep this instance
  cls(0)
  print("HOW TO PLAY", 40, 20, 7)
  -- Placeholder instructions
  print("Use arrows to navigate menu", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
end

function ui.update_main_menu_logic() -- Renamed from _update_main_menu_logic
  -- Navigate options
  if btnp(3) then menu_option = min(6, menu_option + 1) end -- down, max option is 6
  if btnp(2) then menu_option = max(1, menu_option - 1) end -- up
  
  -- Adjust values
  if menu_option == 1 then -- Players
    if btnp(1) then menu_player_count = min(4, menu_player_count + 1) end -- right (increase)
    if btnp(0) then menu_player_count = max(2, menu_player_count - 1) end -- left (decrease)
  elseif menu_option == 2 then -- Stash Size
    if btnp(1) then menu_stash_size = min(10, menu_stash_size + 1) end -- right (increase)
    if btnp(0) then menu_stash_size = max(3, menu_stash_size - 1) end -- left (decrease)
  elseif menu_option == 3 then -- Game Timer
    if btnp(1) then game_timer = min(10, game_timer + 1) end -- right (increase)
    if btnp(0) then game_timer = max(1, game_timer - 1) end -- left (decrease)
  end
  -- Select option
  if btnp(5) then -- ❎ (X)
    if menu_option == 4 then -- Start Game
      player_count = menu_player_count
      stash_count = menu_stash_size
      N_PLAYERS = menu_player_count
      STASH_SIZE = menu_stash_size
      -- game_timer is already set
      global_game_state = "in_game"
      printh("Menu: Start Game. P:"..player_count.." S:"..stash_count.." T:"..game_timer)
    elseif menu_option == 5 then -- Finish Game (New Option)
      N_PLAYERS = menu_player_count -- Set N_PLAYERS from current menu selection
      STASH_SIZE = menu_stash_size -- Set STASH_SIZE for consistency

      -- Ensure player_manager is initialized for the current N_PLAYERS setting.
      -- This is important if "Finish Game" is hit before "Start Game" or after changing player count.
      -- player_manager.init_players should create players with score 0 if they don't exist.
      local needs_player_init = true -- Assume init is needed by default
      if player_manager and player_manager.get_player then
        local players_seem_correctly_initialized = true
        for i=1, N_PLAYERS do
          if not player_manager.get_player(i) then
            players_seem_correctly_initialized = false
            break
          end
        end
        -- This check is simplified; init_players should handle making it correct for N_PLAYERS.
        -- If player_manager.init_players is robust, we can call it to ensure state.
      end
      
      if player_manager and player_manager.init_players then
        printh("Finish Game: Ensuring players are initialized for P:"..N_PLAYERS)
        player_manager.init_players(N_PLAYERS)
      end
      global_game_state = "game_over"
      printh("Menu: Finish Game selected. Set state to game_over. Configured P:"..N_PLAYERS)
    elseif menu_option == 6 then -- How To Play (old option index 5)
      global_game_state = "how_to_play"
    end
  end
end

local SPRITES = {
  HEART_ICON = 208 -- Example sprite number for heart
  -- ... other sprites
}

-- Define menu items
ui.menu_items = {
  {text="CONTINUE", action=function() gs.set_state("in_game") end, visible = function() return gs.current_state_name == "paused" end},
  {text="FINISH GAME", action=function() gs.set_state("game_over") end, visible = function() return gs.current_state_name == "paused" end}, -- New item
  {text="RETURN TO MAIN MENU", action=function() gs.set_state("main_menu") end, visible = function() return gs.current_state_name == "paused" end},
  {text="START GAME", action=function() gs.set_state("in_game") end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="PLAYERS:", type="selector", options=config.player_options, current_idx_func=function() return config.current_players_idx end, action=function(idx) config.set_players_idx(idx) end, value_text_func=function() return config.get_players_value() end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="SET TIMER:", type="selector", options=config.timer_options, current_idx_func=function() return config.current_timer_idx end, action=function(idx) config.set_timer_idx(idx) end, value_text_func=function() return config.get_timer_value().." MIN" end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="HOW TO PLAY", action=function() gs.set_state("how_to_play") end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="FAVOURITE", action=function() favourite_current_game() end, icon=SPRITES.HEART_ICON, visible = function() return gs.current_state_name == "main_menu" end},
  {text="RESET CART", action=function() reset_cart() end}, -- Remains visible in all menus
  {text="SHUTDOWN", action=function() shutdown() end} -- Remains visible in all menus
  -- Add other menu items here
}
