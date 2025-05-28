-- src/7.main.lua
-- Main game loop functions (_init, _update, _draw)

--#globals player_manager pieces cursors ui N_PLAYERS STASH_SIZE global_game_state
--#globals menu_option menu_player_count menu_stash_size player_count stash_count
--#globals create_player create_cursor internal_update_game_logic update_game_logic update_controls
--#globals original_update_game_logic_func original_update_controls_func
--#globals printh all cls btnp menuitem print

-- Ensure ui_handler is assigned from the global ui table from 6.ui.lua
local ui_handler -- local to this file, assigned in _init

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
      draw_game_hud = function() print("NO UI - GAME HUD", 40,60,8) end
    }
  end

  menuitem(1, "Return to Main Menu", function()
    global_game_state = "main_menu" 
    printh("Returning to main menu via pause menu...")
    _init_main_menu_state() 
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
    _update_main_menu_logic()
    if global_game_state == "in_game" then
        -- N_PLAYERS and STASH_SIZE are set by _update_main_menu_logic
        init_game_properly() 
    end
  elseif global_game_state == "in_game" then
    _update_game_logic()
  end
end

function _draw()
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    else
      cls(0) print("Error: draw_main_menu not found!", 20,60,8)
    end
  elseif global_game_state == "in_game" then
    _draw_game_screen()
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
  printh("Main menu state initialized: P=" .. menu_player_count .. " S=" .. menu_stash_size)
end

function _update_main_menu_logic()
  if btnp(5) then -- Player 0, Button 5 (X button / keyboard X or V)
    -- Set game settings from menu choices
    player_count = menu_player_count 
    stash_count = menu_stash_size     
    N_PLAYERS = menu_player_count -- Update global N_PLAYERS for game init
    STASH_SIZE = menu_stash_size -- Update global STASH_SIZE for game init
    
    global_game_state = "in_game" 
    printh("Starting game from menu with P:"..player_count.." S:"..stash_count)
  end
  -- Add d-pad logic to change menu_player_count and menu_stash_size here
  -- For example:
  if menu_option == 1 then -- Editing player count
    if btnp(⬆️) then menu_player_count = min(4, menu_player_count + 1) end
    if btnp(⬇️) then menu_player_count = max(1, menu_player_count - 1) end
    if btnp(➡️) or btnp(🅾️) then menu_option = 2 end -- Cycle to stash size
  elseif menu_option == 2 then -- Editing stash size
    if btnp(⬆️) then menu_stash_size = min(10, menu_stash_size + 1) end
    if btnp(⬇️) then menu_stash_size = max(3, menu_stash_size - 1) end
    if btnp(⬅️) then menu_option = 1 end -- Cycle back to player count
    if btnp(🅾️) then menu_option = 1 end -- Cycle to player count (or a "Start" option if added)
  end

  -- Update what ui.draw_main_menu will show (it reads player_count, stash_count directly)
  -- Or, pass menu_player_count, menu_stash_size, menu_option to draw_main_menu
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
