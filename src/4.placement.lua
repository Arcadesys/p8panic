--#globals effects sfx create_piece add pieces score_pieces printh ray_segment_intersect LASER_LEN
function legal_placement(piece_params)
 local uz={{x1=0,y1=0,x2=15,y2=23},{x1=112,y1=0,x2=127,y2=23},{x1=0,y1=104,x2=15,y2=127},{x1=112,y1=104,x2=127,y2=127}}
 local tp=create_piece(piece_params)
 if not tp then return false end
 local function vs(a,b)return{x=a.x-b.x,y=a.y-b.y}end
 local function vd(a,b)return a.x*b.x+a.y*b.y end
 local function pr(vertices,ax)
  if not vertices or #vertices==0 then return 0,0 end
  local mn,mx=vd(vertices[1],ax),vd(vertices[1],ax)
  for i=2,#vertices do local p=vd(vertices[i],ax)mn,mx=min(mn,p),max(mx,p)end
  return mn,mx
 end
 local function ga(vertices)
  local ua={}
  if not vertices or #vertices<2 then return ua end
  for i=1,#vertices do
   local p1,p2=vertices[i],vertices[(i%#vertices)+1]
   local e=vs(p2,p1)
   local n={x=-e.y,y=e.x}
   local l=sqrt(n.x^2+n.y^2)
   if l>0.0001 then
    n.x,n.y=n.x/l,n.y/l
    local u=true
    for ea in all(ua)do if abs(vd(ea,n))>0.999 then u=false;break end end
    if u then add(ua,n)end
   end
  end
  return ua
 end
 local cs=tp:get_draw_vertices()
 if not cs or #cs==0 then return false end
 for c in all(cs)do
  if c.x<0 or c.x>128 or c.y<0 or c.y>128 then return false end
  for z in all(uz)do if c.x>=z.x1 and c.x<=z.x2 and c.y>=z.y1 and c.y<=z.y2 then return false end end
 end
 for _,ep in ipairs(pieces)do
  local ec=ep:get_draw_vertices()
  if not ec or #ec==0 then goto nx end
  local ca={}
  for ax in all(ga(cs))do add(ca,ax)end
  for ax in all(ga(ec))do add(ca,ax)end
  if #ca==0 then
   local mn1,mx1,my1,my2=128,0,128,0
   for c in all(cs)do mn1,mx1,my1,my2=min(mn1,c.x),max(mx1,c.x),min(my1,c.y),max(my2,c.y)end
   local mn2,mx2,my3,my4=128,0,128,0
   for c in all(ec)do mn2,mx2,my3,my4=min(mn2,c.x),max(mx2,c.x),min(my3,c.y),max(my4,c.y)end
   if not(mx1<mn2 or mx2<mn1 or my2<my3 or my4<my1)then return false end
   goto nx
  end
  local col=true
  for ax in all(ca)do
   local mn1,mx1=pr(cs,ax)
   local mn2,mx2=pr(ec,ax)
   if mx1<mn2 or mx2<mn1 then col=false;break end
  end
  if col then return false end
  ::nx::
 end
 if piece_params.type=="attacker"then
  local ap,dx,dy=cs[1],cos(piece_params.orientation),sin(piece_params.orientation)
  local lhd=false
  for _,ep in ipairs(pieces)do
   if ep.type=="defender"then
    local dc=ep:get_draw_vertices()
    if not dc or #dc==0 then goto nt end
    for j=1,#dc do
     local k=(j%#dc)+1
     local ix,iy,t=ray_segment_intersect(ap.x,ap.y,dx,dy,dc[j].x,dc[j].y,dc[k].x,dc[k].y)
     if t and t>=0 and t<=200 then lhd=true;break end
    end
   end
   if lhd then break end
   ::nt::
  end
  if not lhd then return false end
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
   printh("P"..player_obj.id.." doesn't have color "..pc.." in stash")
   if effects and effects.bad_placement then sfx(effects.bad_placement)end
   return false
  end
 else
  printh("Placement not legal for P"..player_obj.id)
  if effects and effects.bad_placement then sfx(effects.bad_placement)end
  return false
 end
end
