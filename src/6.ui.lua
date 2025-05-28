-- src/6.ui.lua
-- This file will contain functions for drawing UI elements,
-- including the main menu and in-game HUD.

--#globals cls print N_PLAYERS player_manager cursors global_game_state player_count stash_count

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
  -- Draw player info/scores
  for i = 1, N_PLAYERS do
    local p = player_manager[i]
    if p then
      local status_text = "P" .. i .. ": " .. p.score .. " pts"
      if p.captured_pieces_count > 0 then
        status_text = status_text .. " Cap: " .. p.captured_pieces_count
      end
      if p.stash == 0 and p.captured_pieces_count == 0 then
         status_text = status_text .. " (EMPTY)"
      end
      print(status_text, 5, 5 + (i-1)*8, p.color_id)

      -- Indicate current cursor mode for player 1 (P0 in btnp) for debugging/testing
      if i == 1 and cursors[1] then
          print("P1 Mode: "..cursors[1].mode, 60, 118, 7)
      end
    end
  end
  
  -- Display game timer or other global info (example)
  -- print("Time: " .. flr(game_timer), 90, 5, 7)
end
