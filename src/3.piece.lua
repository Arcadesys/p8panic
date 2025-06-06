Piece={}Piece.__index=Piece
Attacker={}Attacker.__index=Attacker setmetatable(Attacker,{__index=Piece})
Defender={}Defender.__index=Defender setmetatable(Defender,{__index=Piece})
local cos,sin,max,min,sqrt,abs=cos,sin,max,min,sqrt,abs

function Piece:new(o)
 o=o or{}
 o.position=o.position or{x=64,y=64}
 o.orientation=o.orientation or 0
 setmetatable(o,self)
 return o
end

function Piece:get_color()
 if self.is_ghost and self.ghost_color_override then return self.ghost_color_override end
 if self.color then return self.color end
 if self.owner_id then
  local owner_player=player_manager.get_player(self.owner_id)
  if owner_player then return owner_player:get_color()end
 end
 return 7
end

function Piece:get_draw_vertices()
 local o,cx,cy,lc=self.orientation,self.position.x,self.position.y,{}
 if self.type=="attacker"then
  local h,b=8,6
  add(lc,{x=h/2,y=0})add(lc,{x=-h/2,y=b/2})add(lc,{x=-h/2,y=-b/2})
 else
  local w=4
  add(lc,{x=-w,y=-w})add(lc,{x=w,y=-w})add(lc,{x=w,y=w})add(lc,{x=-w,y=w})
 end
 local wc={}
 for c in all(lc)do
  local rx,ry=c.x*cos(o)-c.y*sin(o),c.x*sin(o)+c.y*cos(o)
  add(wc,{x=cx+rx,y=cy+ry})
 end
 return wc
end

function Piece:draw()
  local vertices = self:get_draw_vertices()
  local color = self:get_color()
  if #vertices >= 3 then
    for i=1,#vertices do
      local v1 = vertices[i]
      local v2 = vertices[(i % #vertices) + 1]
      line(v1.x, v1.y, v2.x, v2.y, color)
    end
  end
end

function Attacker:new(o)
  o = o or {}
  o.type = "attacker"
  o.hits = 0
  o.state = "neutral"
  o.targeting_attackers = {}
  return Piece.new(self, o)
end

function Attacker:draw()
 Piece.draw(self)
 local v,a=self:get_draw_vertices(),self.orientation
 if not v or #v==0 then return end
 local dx,dy,lc,ht=cos(a),sin(a),self:get_color(),200
 local hx,hy=v[1].x+dx*ht,v[1].y+dy*ht
 if pieces then
  for _,p in ipairs(pieces)do
   if p~=self then
    local pc=p:get_draw_vertices()
    for j=1,#pc do
     local k=(j%#pc)+1
     local ix,iy,t=ray_segment_intersect(v[1].x,v[1].y,dx,dy,pc[j].x,pc[j].y,pc[k].x,pc[k].y)
     if t and t>=0 and t<ht then ht,hx,hy=t,ix,iy
      if p.state=="unsuccessful"then lc=8 elseif p.state=="overcharged"then lc=10 end
     end
    end
   end
  end
 end
 local ns,nl,tf=flr(ht/4),2,time()*20
 for i=0,ns-1 do
  local st,et=(i*4+tf)%ht,nil
  et=st+nl
  if et<=ht then
   line(v[1].x+dx*st,v[1].y+dy*st,v[1].x+dx*et,v[1].y+dy*et,lc)
  else
   line(v[1].x+dx*st,v[1].y+dy*st,hx,hy,lc)
   local sl=et-ht
   if sl>0 then line(v[1].x,v[1].y,v[1].x+dx*sl,v[1].y+dy*sl,lc)end
  end
 end
end

function Defender:new(o)
  o = o or {}
  o.type = "defender"
  o.hits = 0
  o.state = "successful"
  o.targeting_attackers = {}
  return Piece.new(self, o)
end

function Defender:draw()
 local v,c=self:get_draw_vertices(),self:get_color()
 if #v==4 then
  for i=1,4 do line(v[i].x,v[i].y,v[(i%4)+1].x,v[(i%4)+1].y,c)end
 end
 local cx,cy=self.position.x,self.position.y
 if self.state=="successful"then
  if sprites and sprites.defender_successful then
   spr(sprites.defender_successful[flr(time()*8)%#sprites.defender_successful+1],cx-4,cy-4)
  end
 elseif self.state=="unsuccessful"then
  if sprites and sprites.defender_unsuccessful then
   spr(sprites.defender_unsuccessful[flr(time()*8)%#sprites.defender_unsuccessful+1],cx-4,cy-4)
  end
 elseif self.state=="overcharged"then
  if sprites and sprites.defender_overcharged then
   spr(sprites.defender_overcharged[flr(time()*8)%#sprites.defender_overcharged+1],cx-4,cy-4)
  end
 end
end

function create_piece(params)
  local piece_obj
  if params.type == "attacker" then
    piece_obj = Attacker:new(params)
  elseif params.type == "defender" then
    piece_obj = Defender:new(params)
  else
    return nil
  end
  return piece_obj
end
