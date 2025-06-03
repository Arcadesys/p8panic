local Player = {}
Player.__index = Player

function Player:new(id, initial_score, color, ghost_color)
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {},
    capture_mode = false
  }
  instance.stash[color] = STASH_SIZE or 6
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

function Player:is_in_capture_mode()
  return self.capture_mode
end

function Player:toggle_capture_mode()
  self.capture_mode = not self.capture_mode
end

function Player:add_captured_piece(piece_color)
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

function Player:use_piece_from_stash(piece_color)
  if self:has_piece_in_stash(piece_color) then
    self.stash[piece_color] = self.stash[piece_color] - 1
    return true
  end
  return false
end

player_manager.colors = {
  [1] = 12,
  [2] = 8,
  [3] = 11,
  [4] = 10
}

player_manager.ghost_colors = {
  [1] = 1,
  [2] = 9,
  [3] = 3,
  [4] = 4
}

player_manager.max_players = 4
player_manager.current_players = {}

function player_manager.init_players(num_players)
  if num_players < 1 or num_players > player_manager.max_players then
    return
  end

  player_manager.current_players = {}
  for i = 1, num_players do
    local color = player_manager.colors[i]
    local ghost_color = player_manager.ghost_colors[i]
    if not color then
      color = 7
    end
    if not ghost_color then
      ghost_color = 1
    end
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color)
  end
end

function player_manager.get_player(player_id)
  return player_manager.current_players[player_id]
end

function player_manager.get_player_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_color()
  else
    return 7
  end
end

function player_manager.get_player_ghost_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_ghost_color()
  else
    return 1
  end
end

function player_manager.get_player_count()
  return #player_manager.current_players
end
