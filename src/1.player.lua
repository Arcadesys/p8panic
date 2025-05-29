-- src/4.player.lua
--#globals player_manager STASH_SIZE
--#globals player_manager

local Player = {}
Player.__index = Player -- For metatable inheritance

-- Constructor for a new player object
function Player:new(id, initial_score, color, ghost_color) -- Added initial_score
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {}, -- Initialize stash as an empty table
    capture_mode = false -- Added capture_mode
  }
  -- Initialize stash with configurable number of pieces (STASH_SIZE) of the player's own color
  instance.stash[color] = STASH_SIZE or 6
  setmetatable(instance, self)
  return instance
end

-- Method to get player's score (example of a method)
function Player:get_score()
  return self.score
end

-- Method to increment player's score (example of a method)
function Player:add_score(points)
  self.score = self.score + (points or 1)
end

-- Method to get player's color
function Player:get_color()
  return self.color
end

-- Method to get player's ghost color
function Player:get_ghost_color()
  return self.ghost_color
end

-- Method to check if player is in capture mode
function Player:is_in_capture_mode()
  return self.capture_mode
end

-- Method to toggle capture mode
function Player:toggle_capture_mode()
  self.capture_mode = not self.capture_mode
end

-- Method to add a captured piece to the stash
function Player:add_captured_piece(piece_color)
  if self.stash[piece_color] == nil then
    self.stash[piece_color] = 0
  end
  self.stash[piece_color] += 1
end

-- Method to get the count of captured pieces of a specific color
function Player:get_captured_count(piece_color)
  return self.stash[piece_color] or 0
end

-- Method to check if a player has a piece of a certain color in their stash
function Player:has_piece_in_stash(piece_color)
  return (self.stash[piece_color] or 0) > 0
end

-- Method to use a piece from the stash
-- Returns true if successful, false otherwise
function Player:use_piece_from_stash(piece_color)
  if self:has_piece_in_stash(piece_color) then
    self.stash[piece_color] = self.stash[piece_color] - 1
    return true
  end
  return false
end

player_manager.colors = { -- Changed : to .
  [1] = 12, -- Player 1: Light Blue
  [2] = 8,  -- Player 2: Red (Pico-8 color 8 is red)
  [3] = 11, -- Player 3: Green
  [4] = 10  -- Player 4: Yellow
}

-- Ghost/Cursor colors
player_manager.ghost_colors = { -- Added ghost_colors table
  [1] = 1,  -- Player 1: Dark Blue (Pico-8 color 1)
  [2] = 9,  -- Player 2: Orange (Pico-8 color 9)
  [3] = 3,  -- Player 3: Dark Green (Pico-8 color 3)
  [4] = 4   -- Player 4: Brown (Pico-8 color 4)
}

player_manager.max_players = 4
player_manager.current_players = {} -- Table to hold active player instances

-- Function to initialize players at the start of a game
function player_manager.init_players(num_players)
  if num_players < 1 or num_players > player_manager.max_players then
    printh("Error: Invalid number of players. Must be between 1 and " .. player_manager.max_players)
    return
  end

  player_manager.current_players = {} -- Reset current players

  for i = 1, num_players do
    local color = player_manager.colors[i]
    local ghost_color = player_manager.ghost_colors[i] -- Get ghost_color
    if not color then
      printh("Warning: No color defined for player " .. i .. ". Defaulting to white (7).")
      color = 7 -- Default to white if color not found
    end
    if not ghost_color then -- Check for ghost_color
      printh("Warning: No ghost color defined for player " .. i .. ". Defaulting to dark blue (1).")
      ghost_color = 1 -- Default ghost_color
    end
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color) -- Pass ghost_color to constructor
  end
  
  printh("Initialized " .. num_players .. " players.")
end

-- Function to get a player's instance
function player_manager.get_player(player_id)
  return player_manager.current_players[player_id]
end

-- Function to get a player's color (can still be useful as a direct utility)
function player_manager.get_player_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_color()
  else
    return 7 -- Default to white if player not found, or handle error
  end
end

-- Function to get a player's ghost color
function player_manager.get_player_ghost_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_ghost_color()
  else
    return 1 -- Default to dark blue if player not found
  end
end

-- Function to get the current number of initialized players
function player_manager.get_player_count()
  return #player_manager.current_players
end

-- Example Usage (for testing within this file, remove or comment out for production)
-- player_manager.init_players(2)
-- local p1 = player_manager.get_player(1)
-- if p1 then
--   printh("Player 1 ID: " .. p1.id)
--   printh("Player 1 Color: " .. p1:get_color())
--   printh("Player 1 Ghost Color: " .. p1:get_ghost_color()) -- Test ghost color
--   p1:add_score(10)
--   printh("Player 1 Score: " .. p1:get_score())
-- end

-- local p2_color = player_manager.get_player_color(2)
-- printh("Player 2 Color (direct): " .. (p2_color or "not found"))
-- local p2_ghost_color = player_manager.get_player_ghost_color(2)
-- printh("Player 2 Ghost Color (direct): " .. (p2_ghost_color or "not found"))


-- return player_manager -- Old return statement
-- player_manager is global by default via the above declaration
