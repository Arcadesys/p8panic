local Player={}Player.__index=Player
function Player:new(id,s,c,gc,cpu)
 local base_delay = cpu and (120 + rnd(60)) or 0  -- 120-180 frames for CPU, 0 for humans
 local i={id=id,score=s or 0,color=c,ghost_color=gc,stash={},capture_mode=false,is_cpu=cpu or false,cpu_timer=rnd(base_delay),cpu_action_delay=base_delay}
 i.stash[c]=STASH_SIZE or 6
 setmetatable(i,self)return i
end
function Player:get_score()return self.score end
function Player:add_score(p)self.score=self.score+(p or 1)end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:is_in_capture_mode()return self.capture_mode end
function Player:toggle_capture_mode()self.capture_mode=not self.capture_mode end
function Player:add_captured_piece(pc)
 if self.stash[pc]==nil then self.stash[pc]=0 end
 self.stash[pc]+=1
end
function Player:get_captured_count(pc)return self.stash[pc]or 0 end
function Player:has_piece_in_stash(pc)return(self.stash[pc]or 0)>0 end
function Player:use_piece_from_stash(pc)
 if self:has_piece_in_stash(pc)then self.stash[pc]=self.stash[pc]-1 return true end
 return false
end
player_manager.colors={[1]=12,[2]=8,[3]=11,[4]=10}
player_manager.ghost_colors={[1]=1,[2]=9,[3]=3,[4]=4}
player_manager.max_players,player_manager.current_players=4,{}
function player_manager.init_players(np)
 if np<1 or np>player_manager.max_players then return end
 player_manager.current_players={}
 for i=1,np do
  local c,gc=player_manager.colors[i]or 7,player_manager.ghost_colors[i]or 1
  local cpu=(i>np-CPU_PLAYERS)
  player_manager.current_players[i]=Player:new(i,0,c,gc,cpu)
 end
end
function player_manager.get_player(pid)return player_manager.current_players[pid]end
function player_manager.get_player_color(pid)
 local p=player_manager.get_player(pid)
 return p and p:get_color()or 7
end
function player_manager.get_player_ghost_color(pid)
 local p=player_manager.get_player(pid)
 return p and p:get_ghost_color()or 1
end
function player_manager.get_player_count()return #player_manager.current_players end
