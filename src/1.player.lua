local Player={}
Player.__index=Player
function Player:new(id,score0,c0,gc0)
  local instance={
    id=id,
    score=score0 or 0,
    color=c0,
    ghost_color=gc0,
    stash={},
    stash_counts={},
    captured_pieces_count=0 
  }
  instance.stash_counts[c0]=STASH_SIZE or 6

  setmetatable(instance,self)
  return instance
end
function Player:get_score()return self.score end
function Player:add_score(pts)
  self.score=self.score+(pts or 1)
end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:add_captured_piece(piece_color)
  if self.stash_counts[piece_color]==nil then
    self.stash_counts[piece_color]=0
  end
  self.stash_counts[piece_color]+=1
  if self.stash[piece_color]==nil then
    self.stash[piece_color]=0
  end
  self.stash[piece_color]+=1
end
function Player:get_piece_count(piece_color)
  return self.stash[piece_color]or 0
end
function Player:has_piece(piece_color)
  return(self.stash[piece_color]or 0)>0
end
function Player:use_piece_from_stash(piece_color_to_use)
  if self.stash_counts[piece_color_to_use]and self.stash_counts[piece_color_to_use]>0 then
    self.stash_counts[piece_color_to_use]-=1
    printh("P"..self.id.." used c:"..piece_color_to_use..". Stash: "..(self.stash_counts[piece_color_to_use]or 0))
    
    if self.stash[piece_color_to_use]and self.stash[piece_color_to_use]>0 then
      self.stash[piece_color_to_use]-=1
    end
    return true
  else
    return false
  end
end
player_manager.colors={
  [1]=12,
  [2]=8,
  [3]=11,
  [4]=10
}
player_manager.ghost_colors={
  [1]=5,
  [2]=14,
  [3]=3,
  [4]=15
}
player_manager.current_players={}

player_manager.init_players=function(n)
  player_manager.current_players={}
  for i=1,n do
    local p_color=player_manager.colors[i]
    local p_ghost_color=player_manager.ghost_colors[i]
    if Player and Player.new then
      player_manager.current_players[i]=Player:new(i,0,p_color,p_ghost_color)
    else
      player_manager.current_players[i]={id=i,score=0,color=p_color,ghost_color=p_ghost_color,stash={},stash_counts={[p_color]=STASH_SIZE or 6}} 
    end
  end
end
player_manager.get_player=function(id)
  return player_manager.current_players[id]
end

function player_manager.reset_all_players()
  for _,player_obj in ipairs(player_manager.current_players)do
    if player_obj then
      player_obj.score=0
    end
  end
end
function create_player(id,score0,c0,gc0)
  if Player and Player.new then
    return Player:new(id,score0,c0,gc0)
  else
    return{
      id=id,
      score=score0 or 0,
      color=c0 or 7,
      ghost_color=gc0 or 7,
      stash={},
      stash_counts={[c0 or 7]=STASH_SIZE or 6}
    }
  end
end
