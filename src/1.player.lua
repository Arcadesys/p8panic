local Player={}Player.__index=Player
local colors={12,8,11,10}
local ghost_colors={1,9,3,4}
function Player:new(id,s,c,gc,cpu)
 local bd = cpu and (120 + rnd(60)) or 0
 local i={id=id,score=s or 0,color=c,ghost_color=gc,stash={},capture_mode=false,is_cpu=cpu or false,cpu_timer=rnd(bd),cpu_action_delay=bd}
 i.stash[c]=STASH_SIZE or 6
 setmetatable(i,self)return i
end
function Player:get_score()return self.score end
function Player:add_score(p)self.score+=p or 1 end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:is_in_capture_mode()return self.capture_mode end
function Player:toggle_capture_mode()self.capture_mode=not self.capture_mode end
function Player:add_captured_piece(pc)
 self.stash[pc]=(self.stash[pc]or 0)+1
end
function Player:get_captured_count(pc)return self.stash[pc]or 0 end
function Player:has_piece_in_stash(pc)return(self.stash[pc]or 0)>0 end
function Player:use_piece_from_stash(pc)
 if self:has_piece_in_stash(pc)then self.stash[pc]-=1 return true end
 return false
end
player_manager.colors,player_manager.ghost_colors=colors,ghost_colors
player_manager.max_players,player_manager.current_players=4,{}
function player_manager.init_players(np)
 if np<1 or np>4 then return end
 player_manager.current_players={}
 for i=1,np do
  local c,gc=colors[i]or 7,ghost_colors[i]or 1
  local cpu=(i>np-CPU_PLAYERS)
  player_manager.current_players[i]=Player:new(i,0,c,gc,cpu)
 end
end
function player_manager.get_player(pid)return player_manager.current_players[pid]end
function player_manager.get_player_color(pid)
 local p=player_manager.current_players[pid]
 return p and p.color or 7
end
function player_manager.get_player_ghost_color(pid)
 local p=player_manager.current_players[pid]
 return p and p.ghost_color or 1
end
function player_manager.get_player_count()return #player_manager.current_players end
