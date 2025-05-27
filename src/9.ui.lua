-- src/ui.lua

local ui = {}

-- Requires player.lua to be loaded first for player.get_player_data and player.get_player_color
-- Requires scoring.lua for any score-specific display logic if needed directly here

-- Function to draw the score display at the bottom of the screen
-- Assumes screen height is 128px, reserves bottom 8px (y=120 to y=127)
function ui.draw_score_display(players_table)
  local screen_width = 128
  local display_height = 8
  local start_y = 128 - display_height

  -- Clear the score display area (optional, if not cleared elsewhere)
  -- rectfill(0, start_y, screen_width -1 , start_y + display_height -1, 0) -- Black background

  if not players_table then
    print("ui.draw_score_display: players_table is nil")
    return
  end

  local num_players = #players_table
  if num_players == 0 then
    -- print("No players to display scores for.")
    return
  end
  
  local section_width = flr(screen_width / num_players)
  local current_x = 0

  for i = 1, num_players do
    local player_data = players_table[i]
    if player_data then
      local player_score = player_data.score or 0 -- Default to 0 if score is nil
      local player_color = player_data.color or 7 -- Default to white if color is nil
      
      -- Display format: "P<id>: <score>"
      -- Pico-8 print function: print(str, x, y, color)
      -- We need to make sure text fits. A simple score display for now.
      local score_text = "P"..i.." "..player_score
      
      -- Calculate text position to center it (approximately) in its section
      -- Pico-8 default font is 4px wide per char. Length of "PX S" is 4 chars.
      -- For longer scores, this might need adjustment or a smaller font.
      local text_width = #score_text * 4 -- Approximate width
      local text_x = current_x + flr((section_width - text_width) / 2)
      local text_y = start_y + 1 -- Small padding from the top of the score bar

      -- Draw a small colored rectangle for the player
      rectfill(current_x, start_y, current_x + section_width -1, start_y + display_height -1, player_color)
      -- Print score text on top, in a contrasting color (e.g., black or white depending on player_color)
      local text_color = 0 -- Black
      if player_color == 0 or player_color == 1 or player_color == 6 or player_color == 7 then -- Dark colors
          text_color = 7 -- White
      end
      print(score_text, text_x, text_y, text_color)
      
      current_x = current_x + section_width
    else
      -- print("Player data not found for player " .. i)
    end
  end
end

return ui
