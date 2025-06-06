--#globals effects sfx create_piece add pieces score_pieces ray_segment_intersect LASER_LEN
function legal_placement(piece_params)
 local uz={{0,0,15,23},{112,0,127,23},{0,104,15,127},{112,104,127,127}}
 local tp=create_piece(piece_params)
 if not tp then return false end
 local function vd(a,b)return a.x*b.x+a.y*b.y end
 local function pr(vertices,ax)
  local mn,mx=vd(vertices[1],ax),vd(vertices[1],ax)
  for i=2,#vertices do local p=vd(vertices[i],ax)mn,mx=min(mn,p),max(mx,p)end
  return mn,mx
 end
 local cs=tp:get_draw_vertices()
 if not cs or #cs==0 then return false end
 for c in all(cs)do
  if c.x<0 or c.x>128 or c.y<0 or c.y>128 then return false end
  for z in all(uz)do if c.x>=z[1] and c.x<=z[3] and c.y>=z[2] and c.y<=z[4] then return false end end
 end
 for _,ep in ipairs(pieces)do
  local ec=ep:get_draw_vertices()
  if ec and #ec>0 then
   local mn1,mx1,my1,my2=128,0,128,0
   for c in all(cs)do mn1,mx1,my1,my2=min(mn1,c.x),max(mx1,c.x),min(my1,c.y),max(my2,c.y)end
   local mn2,mx2,my3,my4=128,0,128,0
   for c in all(ec)do mn2,mx2,my3,my4=min(mn2,c.x),max(mx2,c.x),min(my3,c.y),max(my4,c.y)end
   if not(mx1<mn2 or mx2<mn1 or my2<my3 or my4<my1)then return false end
  end
 end
 if piece_params.type=="attacker"then
  local ap,dx,dy=cs[1],cos(piece_params.orientation),sin(piece_params.orientation)
  for _,ep in ipairs(pieces)do
   if ep.type=="defender"then
    local dc=ep:get_draw_vertices()
    if dc and #dc>0 then
     for j=1,#dc do
      local k=(j%#dc)+1
      local ix,iy,t=ray_segment_intersect(ap.x,ap.y,dx,dy,dc[j].x,dc[j].y,dc[k].x,dc[k].y)
      if t and t>=0 and t<=200 then return true end
     end
    end
   end
  end
  return false
 end
 return true
end

function place_piece(piece_params,player_obj)
 if legal_placement(piece_params)then
  local pc=piece_params.color
  if pc==nil then return false end
  if player_obj:use_piece_from_stash(pc)then
   local np=create_piece(piece_params)
   if np then
    add(pieces,np)
    if piece_params.type=="defender"and effects and effects.defender_placement then sfx(effects.defender_placement)
    elseif piece_params.type=="attacker"and effects and effects.attacker_placement then sfx(effects.attacker_placement)end
    score_pieces()
    return true
   else
    player_obj:add_captured_piece(pc)
    return false
   end
  else
   if effects and effects.bad_placement then sfx(effects.bad_placement)end
   return false
  end
 else
  if effects and effects.bad_placement then sfx(effects.bad_placement)end
  return false
 end
end
