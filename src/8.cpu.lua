function update_cpu_players()
 for i=1,player_manager.get_player_count()do
  local p,c=player_manager.get_player(i),cursors[i]
  if p and p.is_cpu and c then
   p.cpu_timer-=1
   if p.cpu_timer<=0 then
    cpu_act(p,c,i)
    -- Randomize next action delay for more natural behavior
    p.cpu_timer = p.cpu_action_delay + rnd(60) - 30  -- ±30 frame variance
   end
   -- Update CPU movement towards target
   cpu_update_movement(p,c)
  end
 end
end

function cpu_update_movement(p,c)
 if not p.cpu_target_x or not p.cpu_target_y then return end
 
 local dx,dy=p.cpu_target_x-c.x,p.cpu_target_y-c.y
 local dist=sqrt(dx*dx+dy*dy)
 
 if dist<2 then
  -- Reached target, execute action
  if p.cpu_action=="place" then
   c.pending_type,c.pending_color,c.pending_orientation=p.cpu_place_type,p.cpu_place_color,p.cpu_place_orientation
   if place_piece({owner_id=p.id,type=p.cpu_place_type,position={x=c.x+4,y=c.y+4},orientation=p.cpu_place_orientation,color=p.cpu_place_color},p)then
    c.control_state,c.return_cooldown=2,6
   end
  elseif p.cpu_action=="capture" then
   c.pending_type="capture"
   p.capture_mode=true
   if attempt_capture(p,c)then c.control_state,c.return_cooldown=2,6 end
  end
  -- Clear target and action
  p.cpu_target_x,p.cpu_target_y,p.cpu_action=nil,nil,nil
 else
  -- Move towards target at slower CPU speed with some randomness
  local base_speed = (cursor_speed or 2) * 0.7  -- 30% slower than humans
  local move_speed = base_speed + rnd(0.6) - 0.3  -- ±0.3 speed variance
  
  if abs(dx)>abs(dy)then
   if dx>0 then c.x=min(c.x+move_speed,128-8)
   else c.x=max(0,c.x-move_speed)end
  else
   if dy>0 then c.y=min(c.y+move_speed,128-8)
   else c.y=max(0,c.y-move_speed)end
  end
 end
end

function cpu_act(p,c,id)
 -- Don't set new targets if already moving to one
 if p.cpu_target_x or p.cpu_target_y then return end
 
 local cap=cpu_cap(id)
 if cap then cpu_set_capture_target(c,cap,p) return end
 if not cpu_def(id)then cpu_set_place_target(c,p,id,"defender") return end
 local thr=cpu_threat(id)
 if #thr>0 then cpu_set_defend_target(c,p,id,thr) return end
 cpu_set_place_target(c,p,id,"attacker")
end

function cpu_def(id)
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="defender"and p.state=="successful"then return true end
 end
end

function cpu_cap(id)
 for _,p in ipairs(pieces)do
  if p.owner_id==id and p.type=="defender"and p.state=="overcharged"then
   if p.targeting_attackers and #p.targeting_attackers>0 then return p.targeting_attackers[1]end
  end
 end
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
  p.cpu_place_orientation=0
 end
end

function cpu_set_place_target(c,p,id,piece_type)
 local pos
 if piece_type=="defender" then
  pos=cpu_safe(id)
 else
  pos=cpu_att_pos(id)
 end
 
 if pos then
  p.cpu_target_x,p.cpu_target_y=pos.x-4,pos.y-4
  p.cpu_action="place"
  p.cpu_place_type=piece_type
  p.cpu_place_color=cpu_color(p)
  p.cpu_place_orientation=pos.o or 0
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
 for i=1,10 do
  local x,y=32+rnd(64),32+rnd(64)
  if cpu_ok(x,y,id)then return{x=x,y=y}end
 end
 return{x=64,y=64}
end

function cpu_safe_near(pos,id)
 for dx=-16,16,8 do for dy=-16,16,8 do
  local x,y=pos.x+dx,pos.y+dy
  if x>16 and x<112 and y>24 and y<104 and cpu_ok(x,y,id)then return{x=x,y=y}end
 end end
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

function cpu_target(pos,id)
 for i=1,8 do
  local a,d=i/8,30+rnd(20)
  local x,y=pos.x+cos(a)*d,pos.y+sin(a)*d
  if x>16 and x<112 and y>24 and y<104 and cpu_ok(x,y,id)then return{x=x,y=y,o=a+0.5}end
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
