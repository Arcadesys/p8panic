-- src/8.main.lua
-- Main game loop functions (_init, _update, _draw)

--#globals player_manager pieces cursors ui N_PLAYERS STASH_SIZE global_game_state game_timer time flr string add table
--#globals menu_option menu_player_count menu_stash_size player_count stash_count
--#globals create_player create_cursor internal_update_game_logic update_game_logic update_controls
--#globals original_update_game_logic_func original_update_controls_func update_game_state
--#globals printh all cls btnp menuitem print

-- Ensure global variables are accessible in this file
if not N_PLAYERS then N_PLAYERS = 2 end  -- Default fallback
if not table then table = table or {} end  -- Ensure table is available

-- Ensure ui_handler is assigned from the global ui table from 6.ui.lua
local ui_handler -- local to this file, assigned in _init

local game_start_time = 0
local remaining_time_seconds = 0

local game_winners = {} -- Stores list of winner IDs
local game_max_score = -1 -- Stores the max score achieved
local processed_game_over = false -- Flag to ensure winner calculation runs once per game_over state entry

------------------------------------------
-- Main Pico-8 Functions
------------------------------------------
function _init()
  
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
      draw_winner_screen = function() cls(0) print("NO UI - WINNER SCREEN", 20,60,8) end,
      update_main_menu_logic = function() printh("Warning: NO UI - update_main_menu_logic not called") end
    }
  end

  -- Configure pause menu items for in-game state

  menuitem(1, false) -- Clear item at index 1 (e.g., default "SOUND")
  menuitem(2, false) -- Clear item at index 2 (e.g., default "MUSIC")
  menuitem(3, false) -- Clear item at index 3 (e.g., default "EXIT")

  -- Add "Return to Main Menu" at index 1
  menuitem(1, "Return to Main Menu", function()
    global_game_state = "main_menu" 
    printh("Returning to main menu via pause menu...")
    _init_main_menu_state() 
  end)

  -- Add "Finish Game" option at index 2
  menuitem(2, "finish game", function() -- Capitalized label for consistency
    -- Only allow finishing game if we're currently in a game
    if global_game_state == "in_game" then
      printh("Finishing game early via pause menu...")
      -- Ensure players are properly initialized before calculating winners
      if player_manager and player_manager.init_players then
        player_manager.init_players(N_PLAYERS)
      end
      global_game_state = "game_over"
      -- Reset the processed flag so winner calculation will run
      processed_game_over = false
    else
      printh("Cannot finish game - not currently in game state")
    end
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

function _calculate_and_store_winners()
  local current_max_score = -1
  local current_winners = {}
  if player_manager and player_manager.get_player and N_PLAYERS then
    for i=1, N_PLAYERS do
      local p = player_manager.get_player(i)
      if p and type(p.score) == "number" then
        if p.score > current_max_score then
          current_max_score = p.score
          current_winners = {p.id}
        elseif p.score == current_max_score then
          add(current_winners, p.id)
        end
      end
    end
  end
  game_winners = current_winners
  game_max_score = current_max_score
  -- printh(\"Winners calculated: \" .. table.concat(game_winners, \", \") .. \" with score: \" .. game_max_score)
  local winners_str = ""
  for i, winner_id in ipairs(game_winners) do
    winners_str = winners_str .. winner_id
    if i < #game_winners then
      winners_str = winners_str .. ", "
    end
  end
  printh("Winners calculated: " .. winners_str .. " with score: " .. game_max_score)
end

function _update()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    else
      printh("Warning: ui_handler.update_main_menu_logic not found!")
    end
    processed_game_over = false -- Reset when returning to menu
    if global_game_state == "in_game" then
      -- N_PLAYERS and STASH_SIZE have been set by menu logic
      init_game_properly()
    elseif global_game_state == "how_to_play" then
      -- handled below
    end
  elseif global_game_state == "how_to_play" then
    processed_game_over = false -- Reset if coming from game_over
    -- return to menu on X
    if btnp(5) then
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  elseif global_game_state == "in_game" then
    _update_game_logic()
    processed_game_over = false -- Reset flag

    -- Timer logic
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/30 -- Pico-8 runs at 30 FPS
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        printh("Game Over! Time is up.")
        if update_game_state then
          update_game_state() -- Recalculate scores one last time
        end
        global_game_state = "game_over"
        -- Winner calculation will be handled by the "game_over" state block below
      end
    end
  elseif global_game_state == "game_over" then
    if not processed_game_over then
      -- This block ensures player data is consistent if "Finish Game" was selected from menu
      -- The menu logic in 6.ui.lua already attempts to call player_manager.init_players(N_PLAYERS)
      -- before setting this state.
      _calculate_and_store_winners()
      processed_game_over = true
    end
    -- Wait for a button press to return to main menu
    if btnp(5) or btnp(4) then -- (X) or (O) button
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
    if ui_handler and ui_handler.draw_winner_screen then
      ui_handler.draw_winner_screen() -- This function will use game_winners and game_max_score
    else
      -- Fallback minimal display if ui_handler or function is missing
      cls(0) 
      print("GAME OVER (NO UI)", 30, 50, 8)
      print("Winner data not shown.", 20, 60, 7)
      print("Press (X) to return", 28, 100, 7)
    end
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
