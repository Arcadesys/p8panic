-- src/1.player.lua (Corrected filename in comment)
--#globals player_manager STASH_SIZE create_player Player -- Added STASH_SIZE, create_player, Player to globals for clarity if used by other files directly.
-- Ensure player_manager is treated as the global table defined in 0.init.lua

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
    stash_counts = {STASH_SIZE or 6, 0, 0, 0}, -- Initialize stash_counts with STASH_SIZE in the first slot
    captured_pieces_count = 0 -- Initialize captured_pieces_count
  }
  -- Initialize stash with configurable number of pieces (STASH_SIZE) of the player's own color
  -- This line might be for a different piece tracking mechanism, HUD uses stash_counts.
  instance.stash[color] = STASH_SIZE or 6 -- Access global STASH_SIZE explicitly
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
function Player:use_piece_from_stash(piece_color_to_use)
  -- Assumption: The piece_color_to_use is the player's own primary color,
  -- and this corresponds to the first slot in stash_counts.
  if piece_color_to_use == self.color then
    if self.stash_counts[1] > 0 then
      self.stash_counts[1] = self.stash_counts[1] - 1
      -- Also update the old self.stash table for consistency, though HUD uses stash_counts
      if self.stash[piece_color_to_use] and self.stash[piece_color_to_use] > 0 then
        self.stash[piece_color_to_use] = self.stash[piece_color_to_use] - 1
      end
      printh("P"..self.id.." used piece. Stash counts[1]: "..self.stash_counts[1]) -- DEBUG
      return true
    else
      printh("P"..self.id.." has no pieces of type 1 (color "..piece_color_to_use..") in stash_counts.") -- DEBUG
      return false
    end
  else
    -- If trying to use a piece of a different color (e.g., captured pieces of other types)
    -- This part needs more complex logic if players can place other colored pieces from stash_counts[2-4]
    -- For now, we only allow placing the primary piece type from stash_counts[1]
    printh("P"..self.id.." tried to use non-primary color "..piece_color_to_use..". Not implemented for stash_counts.") -- DEBUG
    
    -- Fallback to old logic for other colors, though this won't affect HUD
    if self:has_piece_in_stash(piece_color_to_use) then
      self.stash[piece_color_to_use] = self.stash[piece_color_to_use] - 1
      return true -- This won't update HUD correctly for these pieces
    end
    return false
  end
end

-- Module-level table player_manager is already defined globally in 0.init.lua
-- We are adding functions to it.
-- REMOVED: player_manager = {} -- This was overwriting the global instance.

player_manager.colors = {
  [1] = 12, -- Player 1: Light Blue
  [2] = 8,  -- Player 2: Red (Pico-8 color 8 is red)
  [3] = 11, -- Player 3: Green
  [4] = 10  -- Player 4: Yellow
}

-- Ghost/Cursor colors
player_manager.ghost_colors = {
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
    local ghost_color = player_manager.ghost_colors[i]
    if not color then
      printh("Warning: No color defined for player " .. i .. ". Defaulting to white (7).")
      color = 7
    end
    if not ghost_color then
      printh("Warning: No ghost color defined for player " .. i .. ". Defaulting to dark blue (1).")
      ghost_color = 1
    end
    -- Player:new uses global STASH_SIZE, which should be set before this by menu/game init
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color)
  end
end

-- Function to get a player's instance
function player_manager.get_player(player_id)
  if not player_manager.current_players then
     printh("Accessing player_manager.current_players before init_players?")
     return nil
  end
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
  if not player_manager.current_players then return 0 end
  return #player_manager.current_players
end

-- Expose Player class if other modules need to create players or check type (optional)
-- Player = Player
