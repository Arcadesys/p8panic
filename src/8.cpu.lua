function update_cpu_players()
 for i=1,player_manager.get_player_count()do
  local p,c=player_manager.get_player(i),cursors[i]
  if p and p.is_cpu and c then
   p.cpu_timer-=1
   if p.cpu_timer<=0 then
    cpu_act(p,c,i)
    p.cpu_timer = p.cpu_action_delay + rnd(60) - 30
   end
   cpu_update_movement(p,c)
  end
 end
end

function cpu_update_movement(p,c)
 if not p.cpu_target_x then return end
 
 local dx,dy=p.cpu_target_x-c.x,p.cpu_target_y-c.y
 local dist=dx*dx+dy*dy
 
 if dist<4 then
  if p.cpu_action=="place" then
   c.pending_type,c.pending_color,c.pending_orientation=p.cpu_place_type,p.cpu_place_color,p.cpu_place_orientation
   if place_piece({owner_id=p.id,type=p.cpu_place_type,position={x=c.x+4,y=c.y+4},orientation=p.cpu_place_orientation,color=p.cpu_place_color},p)then
    c.control_state,c.return_cooldown=2,6
   end
  elseif p.cpu_action=="capture" then
   c.pending_type,p.capture_mode="capture",true
   if attempt_capture(p,c)then c.control_state,c.return_cooldown=2,6 end
  end
  p.cpu_target_x,p.cpu_target_y,p.cpu_action=nil,nil,nil
 else
  local spd = (cursor_speed or 2) * 0.7 + rnd(0.6) - 0.3
  if abs(dx)>abs(dy)then
   c.x=dx>0 and min(c.x+spd,120)or max(0,c.x-spd)
  else
   c.y=dy>0 and min(c.y+spd,120)or max(0,c.y-spd)
  end
 end
end

function cpu_act(p,c,id)
 -- Don't set new targets if already moving to one
 if p.cpu_target_x or p.cpu_target_y then return end
 
 local cap=cpu_cap(id)
 if cap then cpu_set_capture_target(c,cap,p) return end
 
 -- More aggressive attacker placement - place attackers more often
 local def_count = 0
 for _,piece in ipairs(pieces) do
  if piece.owner_id == id and piece.type == "defender" then
   def_count = def_count + 1
  end
 end
 
 -- If we have at least 1 defender, start placing attackers
 if def_count >= 1 then
  local thr=cpu_threat(id)
  if #thr>0 then 
   cpu_set_defend_target(c,p,id,thr) 
   return 
  end
  -- Place attackers more frequently
  if rnd(1) < 0.7 then  -- 70% chance to place attacker when we have defenders
   cpu_set_place_target(c,p,id,"attacker")
   return
  end
 end
 
 -- Default to placing defender
 cpu_set_place_target(c,p,id,"defender")
end

function cpu_def(id)
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="defender"and p.state=="successful"then return true end
 end
 return false
end

function cpu_cap(id)
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="defender"and p.state=="overcharged"then
   if p.targeting_attackers and #p.targeting_attackers>0 then return p.targeting_attackers[1]end
  end
 end
 return false
end

function cpu_set_capture_target(c,t,p)
 p.cpu_target_x,p.cpu_target_y=t.position.x-4,t.position.y-4
 p.cpu_action="capture"
end

function cpu_set_defend_target(c,p,id,t)
 local pos=cpu_safe_near(t[1].position,id)
 if pos then
  p.cpu_target_x,p.cpu_target_y=pos.x-4,pos.y-4
  p.cpu_action="place"
  p.cpu_place_type="defender"
  p.cpu_place_color=p:get_color()
  -- Add angular variance for defenders (±15 degrees)
  p.cpu_place_orientation=(rnd(0.084)-0.042)
 end
end

function cpu_set_place_target(c,p,id,piece_type)
 local pos
 if piece_type=="defender" then
  pos=cpu_safe(id)
 else
  pos=cpu_att_pos_smart(id)
 end
 
 if pos then
  p.cpu_target_x,p.cpu_target_y=pos.x-4,pos.y-4
  p.cpu_action="place"
  p.cpu_place_type=piece_type
  p.cpu_place_color=cpu_color(p)
  p.cpu_place_orientation=pos.o or (rnd(0.084)-0.042)
 end
end

function cpu_threat(id)
 local t={}
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="defender"then
   if p.hits>=2 or(p.targeting_attackers and #p.targeting_attackers>=2)then add(t,p)end
  end
 end
 return t
end

function cpu_safe(id)
 -- Reduce iteration count for better performance
 for i=1,10 do  -- Reduced from 15
  local x,y=28+rnd(72),28+rnd(72)
  if cpu_ok(x,y,id)then return{x=x,y=y,o=rnd(0.042)-0.021}end
 end
 return{x=64,y=64,o=rnd(0.084)-0.042}
end

function cpu_safe_near(pos,id)
 -- Reduce iteration for better performance
 for radius=8,20,4 do  -- Reduced max radius from 24 to 20
  for angle=0,5 do  -- Reduced from 7 to 5
   local a=(angle/6)+rnd(0.125)-0.063  -- Adjusted for 6 angles
   local x,y=pos.x+cos(a)*radius,pos.y+sin(a)*radius
   if x>16 and x<112 and y>24 and y<104 and cpu_ok(x,y,id)then 
    return{x=x,y=y,o=rnd(0.084)-0.042}
   end
  end
 end
 return cpu_safe(id)
end

function cpu_att_pos(id)
 local eds={}
 for _,p in ipairs(pieces)do
  if p.owner_id~=id and p.type=="defender"then add(eds,p)end
 end
 if #eds>0 then
  local t=eds[flr(rnd(#eds))+1]
  return cpu_target(t.position,id)
 end
 return cpu_safe(id)
end

function cpu_att_pos_smart(id)
 local eds={}
 for _,p in ipairs(pieces)do
  if p.owner_id~=id and p.type=="defender"then add(eds,p)end
 end
 if #eds>0 then
  local t=eds[flr(rnd(#eds))+1]
  return cpu_target_smart(t.position,id)
 end
 return cpu_safe(id)
end

function cpu_target_smart(pos,id)
 -- Try more attempts for attacker placement reliability
 for attempt=1,12 do  -- Restored to original for reliability
  local a=(attempt/12)+rnd(0.083)-0.042
  local d=25+rnd(30)
  local x,y=pos.x+cos(a)*d,pos.y+sin(a)*d
  
  if x>16 and x<112 and y>24 and y<104 and cpu_ok(x,y,id) then
   -- Simplify friendly blocking check for more reliable placement
   if attempt <= 6 or not cpu_blocks_friendly(x,y,a+0.5,id) then
    return{x=x,y=y,o=a+0.5+rnd(0.042)-0.021}
   end
  end
 end
 return cpu_target(pos,id)
end

function cpu_blocks_friendly(x,y,orientation,id)
 local dx,dy=cos(orientation),sin(orientation)
 -- Check if laser path would intersect friendly pieces
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="attacker" then
   local pv=p:get_draw_vertices()
   if pv and #pv>0 then
    for j=1,#pv do
     local k=(j%#pv)+1
     local ix,iy,t=ray_segment_intersect(x,y,dx,dy,pv[j].x,pv[j].y,pv[k].x,pv[k].y)
     if t and t>=0 and t<=30 then return true end  -- Would block within 30 pixels
    end
   end
  end
 end
 return false
end

function cpu_target(pos,id)
 for i=1,10 do  -- Increased from 6 for better reliability
  local a=(i/10)+rnd(0.125)-0.063
  local d=30+rnd(20)
  local x,y=pos.x+cos(a)*d,pos.y+sin(a)*d
  if x>16 and x<112 and y>24 and y<104 and cpu_ok(x,y,id)then 
   return{x=x,y=y,o=a+0.5+rnd(0.084)-0.042}
  end
 end
 return cpu_safe(id)
end

function cpu_ok(x,y,id)
 if(x<16 or x>111 or y<24 or y>103)or(x<16 and y<24)or(x>111 and y<24)or(x<16 and y>103)or(x>111 and y>103)then return false end
 for _,p in ipairs(pieces)do
  local dx,dy=x-p.position.x,y-p.position.y
  if dx*dx+dy*dy<100 then return false end
 end
 return true
end

function cpu_color(p)
 for c,n in pairs(p.stash)do if n>0 then return c end end
 return p:get_color()
end
