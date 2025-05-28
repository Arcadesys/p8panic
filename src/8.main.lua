-- src/8.main.lua
-- Main game loop functions (_init, _update, _draw)

--#globals player_manager pieces cursors ui N_PLAYERS STASH_SIZE global_game_state game_timer time flr string add table
--#globals menu_option menu_player_count menu_stash_size player_count stash_count
--#globals create_player create_cursor internal_update_game_logic update_game_logic update_controls
--#globals original_update_game_logic_func original_update_controls_func update_game_state
--#globals printh all cls btnp menuitem print

-- Ensure ui_handler is assigned from the global ui table from 6.ui.lua
local ui_handler -- local to this file, assigned in _init

local game_start_time = 0
local remaining_time_seconds = 0

------------------------------------------
-- Main Pico-8 Functions
------------------------------------------
function _init()
  -- Initialize engine-level managers/tables if they aren\'t already by other files
  -- (player_manager, pieces, cursors are expected to be globals defined elsewhere or initialized here)
  -- player_manager should be globally defined by 0.init.lua
  -- pieces should be globally defined by 0.init.lua
  -- cursors should be globally defined by 0.init.lua
  
  if player_manager == nil then 
    printh("CRITICAL: player_manager is nil in _init of 7.main.lua!")
    player_manager = {} -- Fallback, but indicates load order issue
  end
  if pieces == nil then pieces = {} end
  if cursors == nil then cursors = {} end
  
  if ui then
    ui_handler = ui
  else 
    printh("Warning: global 'ui' (from 6.ui.lua) not found in _init. UI might not draw.")
    ui_handler = {
      draw_main_menu = function() print("NO UI - MAIN MENU", 40,60,8) end,
      draw_game_hud = function() print("NO UI - GAME HUD", 40,60,8) end,
      draw_how_to_play = function() print("NO UI - HOW TO PLAY", 20,60,8) end,
      update_main_menu_logic = function() printh("Warning: NO UI - update_main_menu_logic not called") end
    }
  end

  menuitem(1, "Return to Main Menu", function()
    global_game_state = "main_menu" 
    printh("Returning to main menu via pause menu...")
    _init_main_menu_state() 
  end)

  -- Add game timer to menu item
  menuitem(2, "Set Timer: " .. (game_timer or 3) .. " min", function()
    -- This is a placeholder, actual timer setting is in _update_main_menu_logic
    -- but we need a menu item for it to be visible in pause menu if desired.
    -- Or, remove this if timer is only set from main menu.
  end)

  if global_game_state == "main_menu" then
    _init_main_menu_state()
  else
    -- If starting directly in game (e.g. for testing, by changing default global_game_state)
    -- N_PLAYERS and STASH_SIZE should be their default values from 0.init.lua
    player_count = N_PLAYERS
    stash_count = STASH_SIZE
    init_game_properly()
  end
end

function _update()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    else
      printh("Warning: ui_handler.update_main_menu_logic not found!")
    end
    if global_game_state == "in_game" then
      -- N_PLAYERS and STASH_SIZE have been set by menu logic
      init_game_properly()
    elseif global_game_state == "how_to_play" then
      -- handled below
    end
  elseif global_game_state == "how_to_play" then
    -- return to menu on X
    if btnp(5) then
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  elseif global_game_state == "in_game" then
    _update_game_logic()

    -- Timer logic
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/30 -- Pico-8 runs at 30 FPS
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        global_game_state = "game_over"
        printh("Game Over! Time is up.")
        -- Determine winner(s) - can be moved to a separate function
        local max_score = -1
        local winners = {}
        for i=1, N_PLAYERS do
          local p = player_manager.get_player(i)
          if p then
            if p.score > max_score then
              max_score = p.score
              winners = {p.id}
            elseif p.score == max_score then
              add(winners, p.id)
            end
          end
        end
        printh("Winner(s): " .. table.concat(winners, ", ") .. " with score: " .. max_score)
        -- You might want to display this on screen too
      end
    end
  elseif global_game_state == "game_over" then
    -- Wait for a button press to return to main menu
    if btnp(5) then -- (X) button
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  end
end

function _draw()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    else
      cls(0) print("Error: draw_main_menu not found!", 20,60,8)
    end
  elseif global_game_state == "how_to_play" then
    if ui_handler and ui_handler.draw_how_to_play then
      ui_handler.draw_how_to_play()
    else
      cls(0) print("Error: draw_how_to_play not found!", 20,60,8)
    end
  elseif global_game_state == "in_game" then
    _draw_game_screen()
  elseif global_game_state == "game_over" then
    cls(0)
    print("GAME OVER!", 48, 50, 8)
    -- Display winner information (this is basic, enhance as needed)
    local max_score = -1
    local winner_text = "WINNER(S): "
    -- Recalculate or store winners from _update
    -- For simplicity, let's assume winners are stored in a global or passed
    -- For now, just a generic message
    -- TODO: Display actual winners and scores
    print("Time is up!", 45, 60, 7)
    print("Press (X) to return", 28, 100, 7)
  end
end

------------------------------------------
-- Menu Specific Logic (Initialization & Update)
------------------------------------------
function _init_main_menu_state()
  menu_option = 1 
  -- Use global N_PLAYERS and STASH_SIZE as defaults for the menu
  menu_player_count = N_PLAYERS 
  menu_stash_size = STASH_SIZE   
  -- game_timer is already a global, potentially set by previous menu interaction
  printh("Main menu state initialized: P=" .. menu_player_count .. " S=" .. menu_stash_size .. " T:" .. game_timer)
end

-- This function is now in 6.ui.lua, but if you need overrides or specific logic here, keep it.
-- For now, assuming 6.ui.lua handles menu updates.
-- function _update_main_menu_logic()
--   -- ... (logic moved to 6.ui.lua) ...
-- end

------------------------------------------
-- Game Specific Logic (Initialization, Update, Draw)
------------------------------------------
function init_game_properly()
  if player_manager and player_manager.init_players then
    player_manager.init_players(N_PLAYERS) 
  else
    printh("CRITICAL Error: player_manager.init_players not found! Player module likely failed.")
    -- Minimal fallback to prevent immediate crash, but game won\'t be right.
    player_manager = player_manager or {} -- Ensure it exists
    player_manager.current_players = {}
    player_manager.get_player = function(id) return player_manager.current_players[id] end
    -- This fallback won\'t have proper player objects from Player:new
  end

  pieces = {} 
  cursors = {} 
  for i = 1, N_PLAYERS do
    -- create_cursor should be a global function from its respective module
    if create_cursor then
      cursors[i] = create_cursor(i, 60 + i * 10, 60) 
    else
      printh("Error: create_cursor function not found!")
      -- Corrected dummy cursor draw function
      cursors[i] = { 
        id=i, 
        x=60+i*10, 
        y=60, 
        draw=function(self) print("C"..self.id,self.x,self.y,7) end 
      } -- Dummy cursor
    end
  end

  -- Assign control functions
  if update_controls then 
    original_update_controls_func = update_controls
    printh("Assigned original_update_controls_func from global update_controls.")
  else
    printh("Warning: global function 'update_controls' (from 5.controls.lua) not found. Controls might not work.")
    original_update_controls_func = function() end 
  end
  
  -- Assign game logic update function (example: from 2.scoring.lua or similar)
  -- Assuming the main game logic update function is named 'update_game_state' or similar from another module
  if update_game_state then -- Example name, adjust if your game logic func is different
    original_update_game_logic_func = update_game_state 
    printh("Assigned original_update_game_logic_func from global update_game_state.")
  else
    printh("Warning: global 'update_game_state' (core game logic) not found. Game logic may not run.")
    original_update_game_logic_func = function() end 
  end

  -- Initialize timer
  game_start_time = time() -- Assuming time() gives seconds or a consistent unit
  remaining_time_seconds = (game_timer or 3) * 60 -- Convert minutes to seconds
  printh("Timer started: " .. remaining_time_seconds .. " seconds.")

  printh("Game initialized with " .. N_PLAYERS .. " players and " .. STASH_SIZE .. " pieces each.")
end

function _update_game_logic()
  if original_update_game_logic_func then
    original_update_game_logic_func() 
  end
  if original_update_controls_func then
    original_update_controls_func() 
  end
end

function _draw_game_screen()
  cls(0) 

  -- Draw timer
  local minutes = flr(remaining_time_seconds / 60)
  local seconds = flr(remaining_time_seconds % 60)
  local seconds_str
  if seconds < 10 then
    seconds_str = "0" .. tostr(seconds)
  else
    seconds_str = tostr(seconds)
  end
  local timer_str = tostr(minutes) .. ":" .. seconds_str
  print(timer_str, 64 - #timer_str * 2, 5, 7) -- Top-center

  if pieces then
    for piece_obj in all(pieces) do
      if piece_obj and piece_obj.draw then
        piece_obj:draw()
      end
    end
  end

  if cursors then
    for _, cursor_obj in pairs(cursors) do -- Use pairs for sparse arrays or non-numeric keys
      if cursor_obj and cursor_obj.draw then
        cursor_obj:draw()
      end
    end
  end

  if ui_handler and ui_handler.draw_game_hud then
    ui_handler.draw_game_hud()
  else
    print("Error: ui_handler.draw_game_hud not found",0,0,7)
  end
end

-- Ensure create_player is globally available if Player:new is not directly exposed
-- and player_manager.init_players relies on a global create_player
-- This is usually defined in 1.player.lua or similar.
-- If Player:new is used directly by player_manager.init_players, this isn\'t needed here.
-- function create_player(id, stash_size_val) -- Example, ensure this matches actual create_player
--   if Player and Player.new then
--     return Player:new(id, 0, player_manager.colors[id], player_manager.ghost_colors[id])
--   end
--   printh("Error: Player or Player:new not found for create_player")
--   return {id=id, score=0, color=7, stash={}} -- Dummy
-- end
