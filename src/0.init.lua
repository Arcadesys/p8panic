-- Combined p8panic in a single file
-- cache math functions locally for faster access
local cos, sin, max, min, sqrt, abs, flr = cos, sin, max, min, sqrt, abs, flr
-- laser beam settings
local LASER_LEN = 128
local laser_color = 7
function set_laser_color(c) laser_color = c end
-- length of attacker laser beam
local LASER_LEN = 24

-- SECTION 0: Geometry Helpers
-- Helper: Point‐in‐polygon (works for convex polygons, incl. triangles & quads)
local function point_in_polygon(px, py, vertices)
  local inside = false
  local n = #vertices
  for i=1,n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and
       (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end

-- SECTION 1: Player Module
local player = {}
-- p1: blue (12), ghost: dark blue (1)
player.colors = { [1]=12, [2]=4, [3]=11, [4]=10 }
player.ghost_colors = { [1]=1, [2]=8, [3]=3, [4]=9 }
player.max_players = 4
player.current_players = {}

function player.init_players(num_players)
  if num_players < 1 or num_players > player.max_players then
    print("Error: Invalid number of players.")
    return
  end
  player.current_players = {}
  for i=1,num_players do
    player.current_players[i] = {
      id = i,
      score = 0,
      color = player.colors[i],
      pieces_placed = 0
    }
  end
  print("Initialized "..num_players.." players.")
end


function player.get_player_data(pid)
  return player.current_players[pid]
end

function player.get_player_color(pid)
  return (player.current_players[pid] and player.current_players[pid].color) or 7
end

-- SECTION 2: Legacy Cursor Removed

-- SECTION 3: Collision Module
local function check_rect_overlap(r1, r2)
  if not r1 or not r2 then return false end
  return r1.x < r2.x+r2.w and r1.x+r1.w > r2.x and
         r1.y < r2.y+r2.h and r1.y+r1.h > r2.y
end

local function is_area_occupied(x, y, w, h, all_pieces_list)
  local check_rect = {x=x,y=y,w=w,h=h}
  if not all_pieces_list then return false end
  for p in all(all_pieces_list) do
    if p.position then
      local pr = { x=p.position.x, y=p.position.y, w=8, h=8 }
      if check_rect_overlap(check_rect, pr) then return true end
    end
  end
  return false
end

local function find_safe_teleport_location(placed_x, placed_y, item_w, item_h, all_pieces_list, board_w, board_h)
  local max_r = max(flr(board_w/item_w), flr(board_h/item_h))
  local pgx, pgy = flr(placed_x/item_w), flr(placed_y/item_h)
  for r=1,max_r do
    local pts, seen = {}, {}
    local function add_pt(gx,gy)
      local k = gx.."_"..gy
      if not seen[k] and gx>=0 and gy>=0 and gx<flr(board_w/item_w) and gy<flr(board_h/item_h) then
        add(pts,{gx=gx,gy=gy}); seen[k]=true
      end
    end
    for i=-r,r do add_pt(pgx+i,pgy-r); add_pt(pgx+i,pgy+r) end
    for i=-r+1,r-1 do add_pt(pgx-r,pgy+i); add_pt(pgx+r,pgy+i) end
    for pt in all(pts) do
      local cx,cy=pt.gx*item_w,pt.gy*item_h
      if not is_area_occupied(cx,cy,item_w,item_h,all_pieces_list) then
        return cx,cy
      end
    end
  end
  for gy=0,flr(board_h/item_h)-1 do
    for gx=0,flr(board_w/item_w)-1 do
      local cx,cy=gx*item_w,gy*item_h
      if not (cx==placed_x and cy==placed_y)
        and not is_area_occupied(cx,cy,item_w,item_h,all_pieces_list) then
        return cx,cy
      end
    end
  end
  return nil,nil
end

-- SECTION 4: Placement Module
local function legal_placement(piece)
  local w,h=8,8
  local th, tb = 8,6
  local bw,bh,laser_len=128,128,128
  local function vec_sub(a,b) return {x=a.x-b.x, y=a.y-b.y} end
  local function vec_dot(a,b) return a.x*b.x+a.y*b.y end
  local function vec_norm(v)
    local l=sqrt(v.x^2+v.y^2)
    return l>0.0001 and {x=v.x/l,y=v.y/l} or {x=0,y=0}
  end

  local function get_rot(p)
    local o,pv={},{}
    local cx,cy=p.position.x,p.position.y
    local lc={}
    if p.type=="attacker" then
      add(lc,{x=th/2,y=0}); add(lc,{x=-th/2,y=tb/2}); add(lc,{x=-th/2,y=-tb/2})
    else
      local hw,hh=w/2,h/2
      add(lc,{x=-hw,y=-hh});add(lc,{x=hw,y=-hh})
      add(lc,{x=hw,y=hh}); add(lc,{x=-hw,y=hh})
    end
    for c in all(lc) do
      local rx=c.x*cos(p.orientation)-c.y*sin(p.orientation)
      local ry=c.x*sin(p.orientation)+c.y*cos(p.orientation)
      add(pv,{x=cx+rx,y=cy+ry})
    end
    return pv
  end

  local function project(vs,ax)
    local mn,mx=vec_dot(vs[1],ax),vec_dot(vs[1],ax)
    for i=2,#vs do
      local pr=vec_dot(vs[i],ax)
      mn, mx = min(mn,pr), max(mx,pr)
    end
    return mn,mx
  end

  local function get_axes(vs)
    local ua={}
    for i=1,#vs do
      local p1=vs[i]; local p2=vs[(i%#vs)+1]
      local e=vec_sub(p2,p1); local n={x=-e.y,y=e.x}
      local l=sqrt(n.x^2+n.y^2)
      if l>0.0001 then n.x,n.y=n.x/l,n.y/l
        local uniq=true
        for ea in all(ua) do if abs(vec_dot(ea,n))>0.999 then uniq=false end end
        if uniq then add(ua,n) end
      end
    end
    return ua
  end

  -- 1. bounds
  local corners=get_rot(piece)
  for c in all(corners) do
    if c.x<0 or c.x>bw or c.y<0 or c.y>bh then return false end
  end

  -- 2. collision
  if pieces then
    for ep in all(pieces) do
      if ep~=piece then
        local v1,v2=get_rot(piece),get_rot(ep)
        local axes=get_axes(v1)
        for ax in all(get_axes(v2)) do add(axes,ax) end
        for ax in all(axes) do
          local a1,a2=project(v1,ax),project(v2,ax)
          if a1> a2 or a2< a1 then return false end
        end
      end
    end
  end

  -- 3. attacker laser
  if piece.type=="attacker" then
    local apex=corners[1]
    local dir=vec_norm({x=cos(piece.orientation),y=sin(piece.orientation)})
    local endp={x=apex.x+dir.x*laser_len,y=apex.y+dir.y*laser_len}
    local hit=false
    for dp in all(pieces) do
      if dp.type=="defender" then
        -- reuse SAT on segment vs OBB (omitted for brevity—assume always true for now)
        hit=true; break
      end
    end
    if not hit then return false end
  end

  return true
end

local function redraw_lasers()
  -- placeholder for laser visualization
end

local function place_piece(p)
  if legal_placement(p) then
    add(pieces,p)
    redraw_lasers()
  end
end

-- SECTION 5: UI Module (No UI code)
-- (no UI code)

-- SECTION 5b: Menu Module
menu_active = true
selected_players = 3; min_players = 3; max_players = 4
selected_stash_size = 6; min_stash_size = 3; max_stash_size = 10
menu_options = {
  {text="Players",     value_key="selected_players",   min_val=min_players,      max_val=max_players},
  {text="Stash Size",  value_key="selected_stash_size", min_val=min_stash_size,   max_val=max_stash_size},
  {text="Start Game"}
}
current_menu_selection_index = 1

function _update_menu_controls()
  if not menu_active then return end
  if btnp(2) then current_menu_selection_index = (current_menu_selection_index - 2) % #menu_options + 1 end
  if btnp(3) then current_menu_selection_index = current_menu_selection_index % #menu_options + 1 end
  local opt = menu_options[current_menu_selection_index]
  if opt.value_key then
    local cv = (opt.value_key=="selected_players" and selected_players) or selected_stash_size
    if btnp(0) then cv = max(opt.min_val, cv-1) end
    if btnp(1) then cv = min(opt.max_val, cv+1) end
    if opt.value_key=="selected_players" then selected_players=cv else selected_stash_size=cv end
  elseif opt.text=="Start Game" then
    if btnp(4) or btnp(5) then
      menu_active=false
      start_game_with_players(selected_players)
    end
  end
end

function _draw_main_menu()
  if not menu_active then return end
  cls(1); print("p8panic",48,10,7)
  local y0,line_h=30,10
  for i,opt in ipairs(menu_options) do
    local col,pre = i==current_menu_selection_index and 8 or 7, i==current_menu_selection_index and "> " or "  "
    local txt=pre..opt.text
    if opt.value_key then
      local v = (opt.value_key=="selected_players" and selected_players) or selected_stash_size
      txt = txt..": < "..v.." >"
    end
    print(txt,20,y0+(i-1)*line_h,col)
  end
  print("use d-pad to navigate",10,100,6)
  print("left/right to change",10,108,6)
  print("o/x to start",10,116,6)
end

-- SECTION 6: Controls Module

local function wrap_angle(a) return (a%1+1)%1 end



-- support multiple player cursors
cursors = {}

local function attempt_capture_at_cursor(cur)
  for i=#pieces,1,-1 do
    local p=pieces[i]
    if p.type=="attacker" then
      local dx,dy = (cur.x+4-p.position.x),(cur.y+4-p.position.y)
      if dx*dx+dy*dy < 64*64 then
        del(pieces,p); break
      end
    end
  end
end
cursors = {}
local function init_cursors(num_players)
  cursors = {}
  for i=1,num_players do
    cursors[i] = {
      x = 64-4,
      y = 64-4,
      pending_orientation = 0.75,
      pending_color = player.colors[i],
      pending_type = "defender",
      control_state = 0
    }
  end
end

-- call this after player selection
function start_game_with_players(num_players)
  player.init_players(num_players)
  init_cursors(num_players)
end

function update_controls()
  for i,cur in ipairs(cursors) do
    if cur.control_state==0 then
      -- move cursor with controller i (0-indexed)
      local cidx=i-1
      if btn(0, cidx) then cur.x = max(cur.x-1,0) end
      if btn(1, cidx) then cur.x = min(cur.x+1,120) end
      if btn(2, cidx) then cur.y = max(cur.y-1,0) end
      if btn(3, cidx) then cur.y = min(cur.y+1,120) end
      if btnp(5, cidx) then
        cur.pending_type = (cur.pending_type=="defender" and "attacker")
                        or (cur.pending_type=="attacker" and "capture")
                        or "defender"
      end
      if btnp(4, cidx) then
        -- allow placing/capturing for each player
        if cur.pending_type=="capture" then
          attempt_capture_at_cursor(cur)
        else
          cur.control_state = 1
          cur.pending_color = player.get_player_color(i) or player.colors[i]
        end
      end
    elseif cur.control_state==1 then
      local cidx=i-1
      if btn(0, cidx) then cur.pending_orientation = wrap_angle(cur.pending_orientation-0.02) end
      if btn(1, cidx) then cur.pending_orientation = wrap_angle(cur.pending_orientation+0.02) end
      if btnp(2, cidx) then cur.pending_color = (cur.pending_color-2)%4+1 end
      if btnp(3, cidx) then cur.pending_color = cur.pending_color%4+1 end
      if btnp(4, cidx) then
        add(pieces,{
          owner = cur.pending_color, type = cur.pending_type,
          position = { x=cur.x+4, y=cur.y+4 },
          orientation = cur.pending_orientation
        })
        cur.control_state = 0
        local nx,ny = find_safe_teleport_location(cur.x,cur.y,8,8,pieces,128,128)
        if nx then cur.x,cur.y = nx,ny end
      end
      if btnp(5, cidx) then cur.control_state = 0 end
    end
  end
end

-- SECTION 7: Drawing Module
pieces = {}

-- Piece dims for drawing
local defender_width, defender_height = 8,8
local attacker_triangle_height, attacker_triangle_base = 8,6

local function get_piece_draw_vertices(piece)
  local o, cx, cy = piece.orientation, piece.position.x, piece.position.y
  local lc, ws = {}, {}
  if piece.type=="attacker" then
    add(lc,{x=attacker_triangle_height/2,y=0})
    add(lc,{x=-attacker_triangle_height/2,y=attacker_triangle_base/2})
    add(lc,{x=-attacker_triangle_height/2,y=-attacker_triangle_base/2})
  else
    local hw, hh = defender_width/2, defender_height/2
    add(lc,{x=-hw,y=-hh}); add(lc,{x=hw,y=-hh})
    add(lc,{x=hw,y=hh});   add(lc,{x=-hw,y=hh})
  end
  for c in all(lc) do
    local rx,ry = c.x*cos(o)-c.y*sin(o), c.x*sin(o)+c.y*cos(o)
    add(ws,{x=cx+rx,y=cy+ry})
  end
  return ws
end

function _update()
  _update_menu_controls()
  if not menu_active then update_controls() end
end

function _draw()
  _draw_main_menu()
  if menu_active then return end

  cls(0)
  for p in all(pieces) do
    if p and p.position and p.orientation then
      local v=get_piece_draw_vertices(p)
      local col=p.owner or 7
      if p.type=="attacker" then
        -- draw attacker triangle
        line(v[1].x,v[1].y,v[2].x,v[2].y,col)
        line(v[2].x,v[2].y,v[3].x,v[3].y,col)
        line(v[3].x,v[3].y,v[1].x,v[1].y,col)
        -- dancing ants laser beam
        do
          local apex=v[1]
          local dx,dy=cos(p.orientation)*LASER_LEN,sin(p.orientation)*LASER_LEN
          local segments=16
          local phase=flr(t()*8)%2
          for s=0,segments-1 do
            if (s+phase)%2==0 then
              local x1=apex.x+dx*(s/segments)
              local y1=apex.y+dy*(s/segments)
              local x2=apex.x+dx*((s+1)/segments)
              local y2=apex.y+dy*((s+1)/segments)
              line(x1,y1,x2,y2, laser_color or (p.owner or 7))
            end
          end
        end
        -- draw laser beam
        local apex = v[1]
        local dx, dy = cos(p.orientation)*LASER_LEN, sin(p.orientation)*LASER_LEN
        line(apex.x, apex.y, apex.x + dx, apex.y + dy, p.owner or 7)
        -- show capture indicator if any cursor is in capture mode
        for _,cur in ipairs(cursors) do
          if cur.pending_type=="capture" then
            circ(p.position.x, p.position.y, attacker_triangle_height/2+2, 13)
            break
          end
        end
      else
        for i=1,4 do
          local n=i%4+1
          line(v[i].x,v[i].y,v[n].x,v[n].y,col)
        end
      end
    end
  end

  -- draw all cursors
  for i,cur in ipairs(cursors) do
    local cx,cy = cur.x, cur.y
    local col = player.ghost_colors[i] or 7
    if cur.control_state==0 then
      if cur.pending_type=="defender" then
        rect(cx,cy,cx+7,cy+7,col)
      elseif cur.pending_type=="attacker" then
        local x,y=cx+4,cy+4
        line(x+4,y,x-2,y-3,col)
        line(x-2,y-3,x-2,y+3,col)
        line(x-2,y+3,x+4,y,col)
      else
        local x,y=cx+4,cy+4
        line(x-2,y,x+2,y,col); line(x,y-2,x,y+2,col)
      end
    else
      local tp={ owner=cur.pending_color, type=cur.pending_type,
                 position={x=cx+4,y=cy+4}, orientation=cur.pending_orientation }
      local v=get_piece_draw_vertices(tp)
      if tp.type=="attacker" then
        for j=1,3 do
          local k=j%3+1
          line(v[j].x,v[j].y,v[k].x,v[k].y,cur.pending_color)
        end
      else
        for j=1,4 do
          local k=j%4+1
          line(v[j].x,v[j].y,v[k].x,v[k].y,cur.pending_color)
        end
      end
    end
  end
end
