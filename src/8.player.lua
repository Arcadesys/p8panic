-- src/player.lua

local player = {}

player.colors = {
  [1] = 12, -- Player 1: Light Blue
  [2] = 8,  -- Player 2: Red
  [3] = 11, -- Player 3: Green
  [4] = 10  -- Player 4: Yellow
}

player.max_players = 4
player.current_players = {} -- Table to hold active player data

-- Function to initialize players at the start of a game
function player.init_players(num_players)
  if num_players < 1 or num_players > player.max_players then
    print("Error: Invalid number of players. Must be between 1 and " .. player.max_players)
    return
  end

  player.current_players = {} -- Reset current players

  for i = 1, num_players do
    player.current_players[i] = {
      id = i,
      score = 0,
      color = player.colors[i],
      pieces_placed = 0, -- To track how many of their 6 pieces they've used
      -- Add other player-specific attributes here as needed
      -- e.g., last_defender_lost_time = 0
    }
  end
  
  print("Initialized " .. num_players .. " players.")
end

-- Function to get a player's data
function player.get_player_data(player_id)
  return player.current_players[player_id]
end

-- Function to get a player's color
function player.get_player_color(player_id)
  if player.current_players[player_id] then
    return player.current_players[player_id].color
  else
    return 7 -- Default to white if player not found, or handle error
  end
end

-- Example: Initialize for a 3-player game
-- player.init_players(3) 

-- Example: Get color for player 1
-- local p1_color = player.get_player_color(1)
-- print("Player 1 color: " .. (p1_color or "not found"))


return player
