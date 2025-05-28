local Player = {}
Player.__index = Player

function Player:new(id, initial_score, color, ghost_color)
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {},
    stash_counts = {},
    captured_pieces_count = 0 
  }
  instance.stash_counts[color] = STASH_SIZE or 6

  setmetatable(instance, self)
  return instance
end

function Player:get_score()
  return self.score
end

function Player:add_score(points)
  self.score = self.score + (points or 1)
end

function Player:get_color()
  return self.color
end

function Player:get_ghost_color()
  return self.ghost_color
end

function Player:add_captured_piece(piece_color)
  if self.stash_counts[piece_color] == nil then
    self.stash_counts[piece_color] = 0
  end
  self.stash_counts[piece_color] += 1

  if self.stash[piece_color] == nil then
    self.stash[piece_color] = 0
  end
  self.stash[piece_color] += 1
end

function Player:get_captured_count(piece_color)
  return self.stash[piece_color] or 0
end

function Player:has_piece_in_stash(piece_color)
  return (self.stash[piece_color] or 0) > 0
end

function Player:use_piece_from_stash(piece_color_to_use)
  if self.stash_counts[piece_color_to_use] and self.stash_counts[piece_color_to_use] > 0 then
    self.stash_counts[piece_color_to_use] -= 1
    printh("P"..self.id.." used piece color "..piece_color_to_use..". Stash count: "..(self.stash_counts[piece_color_to_use] or 0))
    
    if self.stash[piece_color_to_use] and self.stash[piece_color_to_use] > 0 then
      self.stash[piece_color_to_use] -= 1
    end
    return true
  else
    printh("P"..self.id.." has no pieces of color "..piece_color_to_use.." in stash_counts.")
    return false
  end
end

player_manager.colors = {
  [1] = 12,
  [2] = 8,
  [3] = 11,
  [4] = 10
}

player_manager.ghost_colors = {
  [1] = 5,
  [2] = 14,
  [3] = 3,
  [4] = 15
}

player_manager.current_players = {}

function player_manager.init_players(num_players)
  player_manager.current_players = {}
  for i = 1, num_players do
    local p_color = player_manager.colors[i]
    local p_ghost_color = player_manager.ghost_colors[i]
    if Player and Player.new then
      player_manager.current_players[i] = Player:new(i, 0, p_color, p_ghost_color)
    else
      printh("Error: Player or Player:new not found during init_players!")
      player_manager.current_players[i] = {id=i, score=0, color=p_color, ghost_color=p_ghost_color, stash={}, stash_counts={[p_color]=STASH_SIZE or 6}} 
    end
  end
  printh("Initialized " .. num_players .. " players.")
end

function player_manager.get_player(id)
  return player_manager.current_players[id]
end

function player_manager.reset_all_scores()
  for _, player_obj in ipairs(player_manager.current_players) do
    if player_obj then
      player_obj.score = 0
    end
  end
end

function create_player(id, initial_score, color, ghost_color)
  if Player and Player.new then
    return Player:new(id, initial_score, color, ghost_color)
  else
    printh("Error: Player or Player.new is not defined when calling create_player.")
    return { 
      id = id, 
      score = initial_score or 0, 
      color = color or 7, 
      ghost_color = ghost_color or 7, 
      stash = {}, 
      stash_counts = {[color or 7] = STASH_SIZE or 6} 
    }
  end
end
