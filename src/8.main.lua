-- src/8.main.lua
-- Main game loop functions (_init, _update, _draw)

--#globals player_manager pieces cursors ui N_PLAYERS STASH_SIZE global_game_state game_timer time flr string add table countdown_timer controls_disabled config create_cursor
--#globals menu_option menu_player_count menu_stash_size player_count stash_count
--#globals internal_update_game_logic update_game_logic update_controls original_update_game_logic_func original_update_controls_func update_game_state game_state_changed
--#globals printh all cls btnp menuitem print rectfill tostr initiate_game_start_request panic_display_timer

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
local controls_disabled = false -- Add this line

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

function start_countdown()
  global_game_state = "countdown"
  countdown_timer = 3 -- 3 seconds
  controls_disabled = true
  printh("EVENT: Countdown started! Initial CD: " .. tostr(countdown_timer)) -- Added detail
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
  printh("UPDATE START State: " .. tostr(global_game_state) .. " CD: " .. tostr(countdown_timer) .. " Panic: " .. tostr(panic_display_timer) .. " CtrlDisabled: " .. tostr(controls_disabled))

  if initiate_game_start_request then -- Check the flag
    initiate_game_start_request = false -- Reset the flag
    init_game_properly() -- Call the function that starts the countdown
    printh("UPDATE: init_game_properly done by request. New state: " .. tostr(global_game_state))
    return -- Exit _update early as state is changing
  end

  if global_game_state == "countdown" then
    countdown_timer -= 2/60 -- Made countdown twice as fast
    if countdown_timer <= 0 then
      printh("UPDATE: Countdown timer <= 0. Old CD: " .. tostr(countdown_timer) .. ". Changing to panic_display.")
      global_game_state = "panic_display"
      panic_display_timer = 1.5 -- Show "Panic!" for 1.5 seconds
      controls_disabled = true -- Keep controls disabled during panic display
      printh("UPDATE: State IS NOW panic_display. Panic Timer: " .. tostr(panic_display_timer))
    end
  elseif global_game_state == "panic_display" then -- Add this new state block
    panic_display_timer -= 1/60
    if panic_display_timer <= 0 then
      printh("UPDATE: Panic timer <= 0. Old Panic: " .. tostr(panic_display_timer) .. ". Changing to in_game.")
      global_game_state = "in_game"
      controls_disabled = false
      game_start_time = time()
      if game_timer and type(game_timer) == "number" then
          remaining_time_seconds = game_timer * 60
      else
          printh("UPDATE: game_timer not valid for setting remaining_time_seconds. Value: " .. tostr(game_timer))
          remaining_time_seconds = 180 -- Default to 3 minutes if game_timer is problematic
      end
      printh("UPDATE: State IS NOW in_game. Start: " .. tostr(game_start_time) .. " Rem: " .. tostr(remaining_time_seconds))
    end
  elseif global_game_state == "in_game" then
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/60 -- Pico-8 runs at 60 FPS for _update
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        printh("UPDATE: Game Over! Time is up.")
        if update_game_state then
          update_game_state() -- Recalculate scores one last time
        end
        global_game_state = "game_over"
        processed_game_over = false -- Ensure winner calculation will run
        printh("UPDATE: State IS NOW game_over (time up).")
      end
    else -- if remaining_time_seconds is already 0 or less
        if global_game_state == "in_game" then 
            printh("UPDATE: Game Over! Remaining time was already zero.")
            global_game_state = "game_over"
            processed_game_over = false
            printh("UPDATE: State IS NOW game_over (remaining time zero).")
        end
    end
    -- Actual game logic updates (player input, piece movement, scoring)
    if not controls_disabled then
        if update_controls then -- Call the main controls update function
            update_controls()
        end
        if player_manager and player_manager.update_all_players then
             player_manager.update_all_players() -- This might update player state based on control input
        end
        -- Add other game logic calls if they exist, e.g., for pieces
        -- if pieces and pieces.update_all then pieces.update_all() end
    end
  elseif global_game_state == "game_over" then
    if not processed_game_over then
      _calculate_and_store_winners()
      processed_game_over = true
      printh("UPDATE: Winners calculated for game_over.")
    end
    -- Wait for a button press to return to main menu
    if btnp(5) or btnp(4) then -- (X) or (O) button
      global_game_state = "main_menu"
      _init_main_menu_state()
      printh("UPDATE: Returning to main_menu from game_over.")
    end
  end

  if global_game_state == "main_menu" then
    printh("UPDATE: In main_menu state. ui_handler type: " .. tostr(type(ui_handler)) .. ", update_main_menu_logic type: " .. tostr(type(ui_handler and ui_handler.update_main_menu_logic)))
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    else
      printh("UPDATE: ERROR - ui_handler.update_main_menu_logic not callable or ui_handler is nil.")
    end
  elseif global_game_state == "countdown" then
    countdown_timer -= 2/60 -- Made countdown twice as fast
    if countdown_timer <= 0 then
      printh("UPDATE: Countdown timer <= 0. Old CD: " .. tostr(countdown_timer) .. ". Changing to panic_display.")
      global_game_state = "panic_display"
      panic_display_timer = 1.5 -- Show "Panic!" for 1.5 seconds
      controls_disabled = true -- Keep controls disabled during panic display
      printh("UPDATE: State IS NOW panic_display. Panic Timer: " .. tostr(panic_display_timer))
    end
  elseif global_game_state == "panic_display" then -- Add this new state block
    panic_display_timer -= 1/60
    if panic_display_timer <= 0 then
      printh("UPDATE: Panic timer <= 0. Old Panic: " .. tostr(panic_display_timer) .. ". Changing to in_game.")
      global_game_state = "in_game"
      controls_disabled = false
      game_start_time = time()
      if game_timer and type(game_timer) == "number" then
          remaining_time_seconds = game_timer * 60
      else
          printh("UPDATE: game_timer not valid for setting remaining_time_seconds. Value: " .. tostr(game_timer))
          remaining_time_seconds = 180 -- Default to 3 minutes if game_timer is problematic
      end
      printh("UPDATE: State IS NOW in_game. Start: " .. tostr(game_start_time) .. " Rem: " .. tostr(remaining_time_seconds))
    end
  elseif global_game_state == "in_game" then
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/60 -- Pico-8 runs at 60 FPS for _update
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        printh("UPDATE: Game Over! Time is up.")
        if update_game_state then
          update_game_state() -- Recalculate scores one last time
        end
        global_game_state = "game_over"
        processed_game_over = false -- Ensure winner calculation will run
        printh("UPDATE: State IS NOW game_over (time up).")
      end
    else -- if remaining_time_seconds is already 0 or less
        if global_game_state == "in_game" then 
            printh("UPDATE: Game Over! Remaining time was already zero.")
            global_game_state = "game_over"
            processed_game_over = false
            printh("UPDATE: State IS NOW game_over (remaining time zero).")
        end
    end
    -- Actual game logic updates (player input, piece movement, scoring)
    if not controls_disabled then
        if update_controls then -- Call the main controls update function
            update_controls()
        end
        if player_manager and player_manager.update_all_players then
             player_manager.update_all_players() -- This might update player state based on control input
        end
        -- Add other game logic calls if they exist, e.g., for pieces
        -- if pieces and pieces.update_all then pieces.update_all() end
    end
  elseif global_game_state == "game_over" then
    if not processed_game_over then
      _calculate_and_store_winners()
      processed_game_over = true
      printh("UPDATE: Winners calculated for game_over.")
    end
    -- Wait for a button press to return to main menu
    if btnp(5) or btnp(4) then -- (X) or (O) button
      global_game_state = "main_menu"
      _init_main_menu_state()
      printh("UPDATE: Returning to main_menu from game_over.")
    end
  end
end

function _draw()
  cls(0) 
  printh("DRAW START State: " .. tostr(global_game_state))

  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    end
  elseif global_game_state == "how_to_play" then
    if ui_handler and ui_handler.draw_how_to_play then
      ui_handler.draw_how_to_play()
    end
  elseif global_game_state == "countdown" then
    -- printh("Draw: Countdown state") -- DEBUG -- Covered by DRAW START
    if ui_handler and ui_handler.draw_countdown_screen then
      ui_handler.draw_countdown_screen()
    else
      print("NO UI - COUNTDOWN", 40, 60, 8)
    end
  elseif global_game_state == "panic_display" then -- Add this block
    -- printh("Draw: Panic Display state") -- DEBUG -- Covered by DRAW START
    if ui_handler and ui_handler.draw_panic_screen then
      ui_handler.draw_panic_screen()
    else
      print("NO UI - PANIC DISPLAY", 40, 60, 8)
    end
  elseif global_game_state == "in_game" then
    -- if ui_handler and ui_handler.draw_game_hud then -- This was replaced by _draw_game_screen
    --   ui_handler.draw_game_hud()
    -- end
    _draw_game_screen() -- Draws timer, pieces, cursors, and HUD
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
  global_game_state = "main_menu"
  menu_option = 1 -- Default to first menu item
  -- Reset player/stash counts to current config or defaults
  if config and config.get_players_value then menu_player_count = config.get_players_value() else menu_player_count = N_PLAYERS end
  menu_stash_size = STASH_SIZE -- Assuming STASH_SIZE is the relevant config for menu
  if config and config.timer_options and config.current_timer_idx then game_timer = config.timer_options[config.current_timer_idx] else game_timer = 3 end -- Default game_timer

  -- Reset game-specific variables if any were set
  pieces = {}
  cursors = {}
  if player_manager and player_manager.reset_all_players then
    player_manager.reset_all_players()
  end
  game_winners = {}
  game_max_score = -1
  processed_game_over = false
  controls_disabled = false -- Ensure controls are enabled in menu
end

-- This function is called when "Start Game" is selected from the menu
function _start_game()
  -- Validate player and stash settings
  if not menu_player_count or menu_player_count < 1 then
    printh("Invalid player count: " .. tostring(menu_player_count) .. ". Cannot start game.")
    return
  end
  if not menu_stash_size or menu_stash_size < 1 then
    printh("Invalid stash size: " .. tostring(menu_stash_size) .. ". Cannot start game.")
    return
  end

  N_PLAYERS = menu_player_count
  STASH_SIZE = menu_stash_size

  -- Initialize game state variables
  global_game_state = "in_game"
  player_count = N_PLAYERS
  stash_count = STASH_SIZE

  -- Notify other modules or systems of the new game state
  if game_state_changed then
    game_state_changed(global_game_state)
  end

  printh("Game starting with " .. N_PLAYERS .. " players and stash size " .. STASH_SIZE)

  -- Start the countdown before actual game begins
  start_countdown()
end

------------------------------------------
-- Game Specific Logic (Initialization, Update, Draw)
------------------------------------------
function init_game_properly()
  printh("EVENT: init_game_properly called. N_PLAYERS: " .. tostr(N_PLAYERS) .. ", STASH_SIZE: " .. tostr(STASH_SIZE))
  
  player_count = N_PLAYERS
  stash_count = STASH_SIZE

  if player_manager and player_manager.init_players then
    player_manager.init_players(N_PLAYERS)
  else
    printh("Error: player_manager.init_players is not defined!")
    return -- Exit if critical function is missing
  end

  pieces = {} -- Clear any existing pieces
  cursors = {} -- Clear existing cursors

  -- Create cursors for each player
  for i = 1, N_PLAYERS do
    if create_cursor then -- Check if create_cursor exists
      add(cursors, create_cursor(i)) -- create_cursor should handle player-specific setup
    else
      printh("Error: create_cursor function not found!")
    end
  end
  
  -- Initialize player stashes (if not already handled by init_players)
  for i=1, N_PLAYERS do
    local p = player_manager.get_player(i)
    if p and p.initialize_stash then 
      p.initialize_stash(STASH_SIZE) 
    end
  end

  -- Set the game state to start the countdown
  start_countdown()

  -- printh("Countdown started!") -- This is in start_countdown(), remove from here if redundant or keep for specific context
  -- This specific printh is in start_countdown(), so it's removed from here to avoid duplication.
  -- If it was meant to be here specifically, it can be re-added.

  -- Reset game over processing flag
  processed_game_over = false
  game_winners = {} 
  game_max_score = -1
  
  printh("EVENT: Game initialized for " .. tostr(N_PLAYERS) .. " players. Countdown initiated.")
end


-- Original game logic update function (if needed for complex interactions)
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
