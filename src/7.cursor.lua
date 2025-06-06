local dcp={control_state=0,pending_type="defender",pending_orientation=0.25,color_select_idx=1,return_cooldown=0}
function create_cursor(player_id,initial_x,initial_y)
 local pc,pgc=7,7
 if player_manager and player_manager.get_player then
  local p=player_manager.get_player(player_id)
  if p then
   if p.get_color then pc=p:get_color()end
   if p.get_ghost_color then
    local gcv=p:get_ghost_color()
    if gcv then pgc=gcv end
   end
  end
 end
 local cur={
  id=player_id,x=initial_x,y=initial_y,spawn_x=initial_x,spawn_y=initial_y,
  control_state=dcp.control_state,pending_type=dcp.pending_type,
  pending_orientation=dcp.pending_orientation,pending_color=pgc,
  color_select_idx=dcp.color_select_idx,return_cooldown=dcp.return_cooldown,
  draw=function(self)
   local cc,cp
   if player_manager and player_manager.get_player then
    cp=player_manager.get_player(self.id)
    if cp and cp.get_color then cc=cp:get_color()end
   end
   if not cc then cc=self.pending_color end
   local cx,cy=self.x+4,self.y+4
   line(cx-2,cy-2,cx+2,cy+2,cc)line(cx-2,cy+2,cx+2,cy-2,cc)
   if self.pending_type=="attacker"or self.pending_type=="defender"then
    local gpp={owner_id=self.id,type=self.pending_type,position={x=self.x+4,y=self.y+4},
     orientation=self.pending_orientation,color=self.pending_color,is_ghost=true}
    local gp=create_piece(gpp)
    if gp and gp.draw then gp:draw()end
   end
   if cp and cp:is_in_capture_mode()then
    if pieces then
     for _,mp in ipairs(pieces)do
      if mp.owner_id==self.id and mp.type=="defender"and mp.state=="overcharged"then
       if mp.targeting_attackers and #mp.targeting_attackers>0 then
        for _,atc in ipairs(mp.targeting_attackers)do
         if atc and atc.position and atc.type=="attacker"then
          circ(atc.position.x,atc.position.y,5,14)
         end
        end
       end
      end
     end
    end
   end
  end
 }
 return cur
end
