if not N_PLAYERS then N_PLAYERS=2 end
if not table then table=table or{}end
local ui_handler
local game_start_time=0
local remaining_time_seconds=0
local game_winners={}
local game_max_score=-1
local processed_game_over=false
local controls_disabled=false
function _init()
  if player_manager==nil then 
    player_manager={}
  end
  if pieces==nil then pieces={}end
  if cursors==nil then cursors={}end
  if ui then
    ui_handler=ui
  else 
    ui_handler={
      draw_main_menu=function()print("NO UI - MAIN MENU",40,60,8)end,
      draw_game_hud=function()print("NO UI - GAME HUD",40,60,8)end,
      draw_how_to_play=function()print("NO UI - HOW TO PLAY",20,60,8)end,
      draw_winner_screen=function()cls(0)print("NO UI - WINNER SCREEN",20,60,8)end,
      update_main_menu_logic=function()end
    }
  end
  menuitem(1,false)
  menuitem(2,false)
  menuitem(3,false)
  menuitem(1,"Return to Main Menu",function()
    global_game_state="main_menu"
    _init_main_menu_state()
  end)
  menuitem(2,"finish game",function()
    if global_game_state=="in_game"then
      if player_manager and player_manager.init_players then
        player_manager.init_players(N_PLAYERS)
      end
      global_game_state="game_over"
      processed_game_over=false
    end
  end)
  
  if global_game_state=="main_menu"then
    _init_main_menu_state()
  else
    player_count=N_PLAYERS
    stash_count=STASH_SIZE
    init_game_properly()
  end
end
function start_countdown()
  global_game_state = "countdown"
  countdown_timer = 3 -- 3 seconds
  controls_disabled = true
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
  local winners_str = ""
  for i, winner_id in ipairs(game_winners) do
    winners_str = winners_str .. winner_id
    if i < #game_winners then
      winners_str = winners_str .. ", "
    end
  end
end
function _update()
  if initiate_game_start_request then -- Check the flag
    initiate_game_start_request = false -- Reset the flag
    init_game_properly() -- Call the function that starts the countdown
    return -- Exit _update early as state is changing
  end
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    end
  elseif global_game_state == "how_to_play" then
    -- return to main menu on Z
    if btnp(4) then
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  elseif global_game_state == "countdown" then
    countdown_timer -= 2/60 -- Made countdown twice as fast
    if countdown_timer <= 0 then
      global_game_state = "panic_display"
      panic_display_timer = 1.5 -- Show "Panic!" for 1.5 seconds
      controls_disabled = true -- Keep controls disabled during panic display
    end
  elseif global_game_state == "panic_display" then -- Add this new state block
    panic_display_timer -= 1/60
    if panic_display_timer <= 0 then
      global_game_state = "in_game"
      controls_disabled = false
      game_start_time = time()
      if game_timer and type(game_timer) == "number" then
          remaining_time_seconds = game_timer * 60
      else
          remaining_time_seconds = 180 -- Default to 3 minutes if game_timer is problematic
      end
    end
  elseif global_game_state == "in_game" then
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/60 -- Pico-8 runs at 60 FPS for _update
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        if update_game_state then
          update_game_state() -- Recalculate scores one last time
        end
        global_game_state = "game_over"
        processed_game_over = false -- Ensure winner calculation will run
      end
    else -- if remaining_time_seconds is already 0 or less
        if global_game_state == "in_game" then 
            global_game_state = "game_over"
            processed_game_over = false
        end
    end
    if not controls_disabled then
        if update_controls then -- Call the main controls update function
            update_controls()
        end
        if player_manager and player_manager.update_all_players then
             player_manager.update_all_players() -- This might update player state based on control input
        end
    end
  elseif global_game_state == "game_over" then
    if not processed_game_over then
      _calculate_and_store_winners()
      processed_game_over = true
    end
    if btnp(4) then -- Z (confirm)
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  end
end
function _draw()
  cls(0) 
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    end
  elseif global_game_state == "how_to_play" then
    if ui_handler and ui_handler.draw_how_to_play then
      ui_handler.draw_how_to_play()
    end
  elseif global_game_state == "countdown" then
    if ui_handler and ui_handler.draw_countdown_screen then
      ui_handler.draw_countdown_screen()
    else
      print("NO UI - COUNTDOWN", 40, 60, 8)
    end
  elseif global_game_state == "panic_display" then -- Add this block
    if ui_handler and ui_handler.draw_panic_screen then
      ui_handler.draw_panic_screen()
    else
      print("NO UI - PANIC DISPLAY", 40, 60, 8)
    end
  elseif global_game_state == "in_game" then
    -- draw game elements and HUD
    _draw_game_screen()   -- Draw timer, pieces, and cursors
    if ui_handler and ui_handler.draw_game_hud then
      ui_handler.draw_game_hud()
    end
  elseif global_game_state == "game_over" then
    if ui_handler and ui_handler.draw_winner_screen then
      ui_handler.draw_winner_screen() -- This function will use game_winners and game_max_score
    end
  end
end
function _init_main_menu_state()
  global_game_state = "main_menu"
  menu_option = 1 -- Default to first menu item
  -- Reset player/stash counts to current config or defaults
  if config and config.get_players_value then menu_player_count = config.get_players_value() else menu_player_count = N_PLAYERS end
  menu_stash_size = STASH_SIZE -- Assuming STASH_SIZE is the relevant config for menu
  if config and config.timer_options and config.current_timer_idx then game_timer = config.timer_options[config.current_timer_idx] else game_timer = 3 end -- Default game_timer
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
_start_game = function()
  if not menu_player_count or menu_player_count < 1 then
    return
  end
  if not menu_stash_size or menu_stash_size < 1 then
    return
  end
  N_PLAYERS = menu_player_count
  STASH_SIZE = menu_stash_size
  global_game_state = "in_game"
  player_count = N_PLAYERS
  stash_count = STASH_SIZE
  if game_state_changed then
    game_state_changed(global_game_state)
  end
  init_game_properly() -- initialize players, cursors, pieces and start countdown
end
function init_game_properly()
  player_count = N_PLAYERS
  stash_count = STASH_SIZE
  if player_manager and player_manager.init_players then
    player_manager.init_players(N_PLAYERS)
  else
    return -- Exit if critical function is missing
  end
  pieces = {} -- Clear any existing pieces
  cursors = {} -- Clear existing cursors
  -- spawn cursors at default positions: near each corner
  local spawn_positions = {
    {x=8, y=8},
    {x=120-8, y=8},
    {x=8, y=120-8},
    {x=120-8, y=120-8}
  }
  for i = 1, N_PLAYERS do
    if create_cursor then
      local pos = spawn_positions[i] or {x=64, y=64}
      add(cursors, create_cursor(i, pos.x, pos.y))
    end
  end
  
  -- Initialize player stashes (if not already handled by init_players)
  for i=1, N_PLAYERS do
    local p = player_manager.get_player(i)
    if p and p.initialize_stash then 
      p.initialize_stash(STASH_SIZE) 
    end
  end
  start_countdown()
  processed_game_over = false
  game_winners = {} 
  game_max_score = -1
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
  local minutes = flr(remaining_time_seconds / 60)
  local seconds = flr(remaining_time_seconds % 60)
  local seconds_str
  if seconds < 10 then
    seconds_str = "0" .. (""..seconds)
  else
    seconds_str = ""..seconds
  end
  local timer_str = (""..minutes) .. ":" .. seconds_str
  print(timer_str, 64 - #timer_str * 2, 5, 7) -- Top-center
  if pieces then
    for piece_obj in all(pieces) do
      if piece_obj and piece_obj.draw then
        piece_obj:draw()
      end
    end
  end
  if cursors then
    for _, cursor_obj in pairs(cursors) do
      if cursor_obj and cursor_obj.draw then
        cursor_obj:draw()
      end
    end
  end
  -- Removed fallback cursor drawing since we have the X-shape implementation
  if ui_handler and ui_handler.draw_game_hud then
    ui_handler.draw_game_hud()
  end
end
