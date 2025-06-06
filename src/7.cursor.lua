local dcp={control_state=0,pending_type="defender",pending_orientation=0.25,color_select_idx=1,return_cooldown=0}
function create_cursor(player_id,initial_x,initial_y)
 local p=player_manager and player_manager.get_player and player_manager.get_player(player_id)
 local pc,pgc=p and p.color or 7,p and p.ghost_color or 7
 local cur={
  id=player_id,x=initial_x,y=initial_y,spawn_x=initial_x,spawn_y=initial_y,
  control_state=0,pending_type="defender",pending_orientation=0.25,pending_color=pgc,
  color_select_idx=1,return_cooldown=0,
  draw=function(self)
   local cp=player_manager and player_manager.get_player(self.id)
   local cc=cp and cp.color or self.pending_color
   local cx,cy=self.x+4,self.y+4
   line(cx-2,cy-2,cx+2,cy+2,cc)line(cx-2,cy+2,cx+2,cy-2,cc)
   if self.pending_type~="capture"then
    local gp=create_piece({owner_id=self.id,type=self.pending_type,position={x=cx,y=cy},
     orientation=self.pending_orientation,color=self.pending_color,is_ghost=true})
    if gp and gp.draw then gp:draw()end
   end
   if cp and cp.capture_mode and pieces then
    for _,mp in ipairs(pieces)do
     if mp.owner_id==self.id and mp.type=="defender"and mp.state=="overcharged"and mp.targeting_attackers then
      for _,atc in ipairs(mp.targeting_attackers)do
       if atc and atc.position and atc.type=="attacker"then
        circ(atc.position.x,atc.position.y,5,14)
       end
      end
     end
    end
   end
  end
 }
 return cur
end
