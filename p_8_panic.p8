pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- Ray vs segment intersection helper (needed for laser collision)
local function ray_segment_intersect(ax, ay, dx, dy, x1, y1, x2, y2)
  -- Ray: (ax,ay) + t*(dx,dy), t>=0
  -- Segment: (x1,y1)-(x2,y2)
  local rx, ry = dx, dy
  local sx, sy = x2-x1, y2-y1 -- Segment vector components
  local det = rx*sy - ry*sx -- Determinant (rx*sy - ry*sx is D x S, where D is ray dir, S is seg dir)
  if abs(det) < 0.0001 then return nil end
  local t = ( (x1-ax)*sy - (y1-ay)*sx ) / det
  local u = ( (x1-ax)*ry - (y1-ay)*rx ) / det
  if t >= 0 and u >= 0 and u <= 1 then
    return ax + t*rx, ay + t*ry, t
  end
  return nil
end
-- Combined p8panic in a single file
-- cache math functions locally for faster access
local cos, sin, max, min, sqrt, abs, flr = cos, sin, max, min, sqrt, abs, flr
-- laser beam settings
function set_laser_color(c) laser_color = c end
local laser_color -- Stores the global laser color, settable by set_laser_color
-- length of attacker laser beam
local LASER_LEN = 24
local RETURN_COOLDOWN_FRAMES = 6 -- Added for cursor return cooldown

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
    local p_defender = pieces[i]
    if p_defender and p_defender.type == "defender" and p_defender.owner == player.get_player_color(player_id) and p_defender.state == "overcharged" then
      -- This player owns this overcharged defender. Check its targeting attackers.
      for attacker_idx = #p_defender.targeting_attackers, 1, -1 do
        local p_attacker = p_defender.targeting_attackers[attacker_idx]
        if p_attacker and p_attacker.position then -- Ensure attacker still exists and has a position
          local dx, dy = (cur.x + 4 - p_attacker.position.x), (cur.y + 4 - p_attacker.position.y)
          if dx*dx + dy*dy < 8*8 then -- Capture radius of 8
            del(pieces, p_attacker) -- Remove the attacker from the global list
            -- The defender's targeting_attackers list will be rebuilt in update_game_logic
            return true -- Captured one piece
          end
        end
      end
    end
  end
  return false -- No capture made
end

local function init_cursors(num_players)
  cursors = {}
  local positions = {
    {x = 8, y = 8},           -- top-left
    {x = 120, y = 8},         -- top-right
    {x = 120, y = 120},       -- bottom-right
    {x = 8, y = 120}          -- bottom-left
  }
  for i=1,num_players do
    local pos = positions[i] or {x=64, y=64}
    cursors[i] = {
      x = pos.x,
      y = pos.y,
      spawn_x = pos.x, -- Store initial spawn X
      spawn_y = pos.y, -- Store initial spawn Y
      pending_orientation = 0.75, -- Default: up
      pending_color = player.colors[i],
      pending_type = "defender",
      control_state = 0, -- 0: moving, 1: placing/orienting, 2: returning to spawn (cooldown)
      return_cooldown = 0 -- Timer for cooldown
    }
  end
end

-- call this after player selection
function start_game_with_players(num_players)
  player.init_players(num_players)
  init_cursors(num_players)
  pieces = {} -- Clear pieces from any previous game
  -- Any other game state reset for a new game
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
          attempt_capture_at_cursor(cur, i) -- Pass player ID 'i'
        else
          cur.control_state = 1
          cur.pending_color = player.get_player_color(i) or player.colors[i]
          -- pending_orientation is already set from previous state or init
        end
      end
    elseif cur.control_state==1 then
      local cidx=i-1
      if btn(0, cidx) then cur.pending_orientation = wrap_angle(cur.pending_orientation-0.02) end
      if btn(1, cidx) then cur.pending_orientation = wrap_angle(cur.pending_orientation+0.02) end
      -- Player color cycling logic - review needed for intent
      if btnp(2, cidx) then cur.pending_color = (cur.pending_color-2)%4+1 end
      if btnp(3, cidx) then cur.pending_color = cur.pending_color%4+1 end

      if btnp(4, cidx) then -- Attempt to place piece
        local piece_to_place = {
          owner = cur.pending_color, type = cur.pending_type,
          position = { x=cur.x+4, y=cur.y+4 }, -- piece center from cursor top-left
          orientation = cur.pending_orientation
        }

        if legal_placement(piece_to_place) then
          place_piece(piece_to_place) -- Use the new place_piece function
          cur.control_state = 2 -- Change to returning state
          cur.return_cooldown = RETURN_COOLDOWN_FRAMES
        else
          -- Optional: Add feedback for illegal placement (e.g., sound, visual cue)
          -- Player remains in placement mode (control_state 1) to adjust
        end
      end
      if btnp(5, cidx) then cur.control_state = 0 end -- Cancel placement, back to move mode
    
    elseif cur.control_state==2 then -- Cooldown: Returning to spawn
      cur.return_cooldown -= 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = 0 -- Back to normal movement
        cur.pending_orientation = 0.75 -- Reset to default orientation (up)
        cur.pending_type = "defender" -- Reset to default type
        cur.return_cooldown = 0 -- Clear cooldown timer
      end
      -- No input processed during this state
    end
  end
end

-- SECTION 7: Drawing Module
-- pieces = {} -- This was redundant, pieces is initialized in start_game_with_players

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

local function draw_piece(p)
  if not p or not p.position or not p.orientation then return end
  local v = get_piece_draw_vertices(p)
  local col = p.owner or 7

  if p.type == "attacker" then
    -- Draw attacker triangle
    line(v[1].x, v[1].y, v[2].x, v[2].y, col)
    line(v[2].x, v[2].y, v[3].x, v[3].y, col)
    line(v[3].x, v[3].y, v[1].x, v[1].y, col)

    -- Draw laser beam
    local apex = v[1]
    local dir_x, dir_y = cos(p.orientation), sin(p.orientation)
    local min_t = LASER_LEN
    local hit_defender_at_min_t = false

    if pieces then -- Ensure pieces table exists and is iterable
      for _, other_piece in ipairs(pieces) do
        if other_piece and other_piece ~= p then -- Don't check collision with self
          local is_other_defender = (other_piece.type == "defender")
          local other_verts = get_piece_draw_vertices(other_piece)
          
          if not other_verts or #other_verts == 0 then goto next_other_piece_laser_check_dp end

          for j=1,#other_verts do
            local k = (j%#other_verts)+1
            local ix, iy, t_intersect = ray_segment_intersect(
              apex.x, apex.y, dir_x, dir_y,
              other_verts[j].x, other_verts[j].y, other_verts[k].x, other_verts[k].y)
            
            if t_intersect and t_intersect >= 0 then
              if t_intersect < min_t then
                min_t = t_intersect
                hit_defender_at_min_t = is_other_defender 
              elseif t_intersect == min_t and is_other_defender then
                -- If multiple things hit at same closest distance, prioritize if one is a defender
                hit_defender_at_min_t = true
              end
            end
          end -- end for j (looping through other_piece vertices)
        end -- end if other_piece and other_piece ~= p
        ::next_other_piece_laser_check_dp::
      end -- end for _, other_piece (looping through all pieces)
    end -- end if pieces

    local beam_len = min(min_t, LASER_LEN)
    local segments = 16 -- Number of dashes for the laser
    local speed = 4     -- Speed of "dancing ants" animation
    local phase = (t()*speed)%2 -- Animation phase
    
    local current_beam_color = laser_color or (p.owner or 7) -- Default to global or owner
    if hit_defender_at_min_t then -- If the laser's effective end is on a defender
      current_beam_color = 8 -- PICO-8 red
    end

    for s=0,segments-1 do
      local dash_is_visible = ((s+phase)%2)<1
      if dash_is_visible then
        local x1 = apex.x + dir_x*beam_len*(s/segments)
        local y1 = apex.y + dir_y*beam_len*(s/segments)
        local x2 = apex.x + dir_x*beam_len*((s+1)/segments)
        local y2 = apex.y + dir_y*beam_len*((s+1)/segments)
        line(x1,y1,x2,y2, current_beam_color)
      end
    end
  elseif p.type == "defender" then
    -- Draw defender (rectangle)
    for i=1,#v do -- Iterate through all vertices returned
      local next_idx = (i % #v) + 1
      line(v[i].x,v[i].y,v[next_idx].x,v[next_idx].y,col)
    end
    
    -- Visual cue for defender state
    if p.state == "unsuccessful" then
      circfill(p.position.x, p.position.y, 1, 0) -- Small black dot
    elseif p.state == "overcharged" then
      circfill(p.position.x, p.position.y, 2, 7) -- Slightly larger white dot
    end
  end
end

function update_game_logic()
  -- 1. Reset/Initialize per-frame defender data
  for _, p_item in ipairs(pieces) do
    if p_item and p_item.type == "defender" then
      p_item.targeting_attackers = {} -- Clear list of who is targeting it this frame
    end
  end

  -- 2. Process attackers and their effects on defenders
  for attacker_idx, attacker_piece in ipairs(pieces) do
    if attacker_piece and attacker_piece.type == "attacker" then
      local attacker_vertices = get_piece_draw_vertices(attacker_piece)
      if not attacker_vertices or #attacker_vertices == 0 then goto continue_attacker_loop end
      local apex = attacker_vertices[1]
      local dir_x = cos(attacker_piece.orientation)
      local dir_y = sin(attacker_piece.orientation)

      local attacker_player_id = nil
      for pid, p_data in pairs(player.current_players) do
        if p_data.color == attacker_piece.owner then
          attacker_player_id = pid
          break
        end
      end

      for defender_idx, defender_piece in ipairs(pieces) do
        if attacker_idx == defender_idx then goto continue_defender_loop end

        if defender_piece and defender_piece.type == "defender" then
          local defender_corners = get_piece_draw_vertices(defender_piece)
          if not defender_corners or #defender_corners == 0 then goto continue_defender_loop end

          local laser_hits_this_defender = false
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local x1, y1 = defender_corners[j].x, defender_corners[j].y
            local x2, y2 = defender_corners[k].x, defender_corners[k].y
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, x1, y1, x2, y2)
            if t and t >= 0 and t <= LASER_LEN then
              laser_hits_this_defender = true
              break
            end
          end
          
          if laser_hits_this_defender then
            defender_piece.hits += 1
            add(defender_piece.targeting_attackers, attacker_piece) -- Add ref to attacker
            if attacker_player_id and player.current_players[attacker_player_id] then
              player.current_players[attacker_player_id].score += 1
            end
          end
        end
        ::continue_defender_loop::
      end
    end
    ::continue_attacker_loop::
  end

  -- 3. Update defender states based on targeting attackers
  for _, p_item in ipairs(pieces) do
    if p_item and p_item.type == "defender" then
      local count = #(p_item.targeting_attackers or {})
      if count <= 1 then p_item.state = "successful"
      elseif count == 2 then p_item.state = "unsuccessful"
      else p_item.state = "overcharged" end
    end
  end
end

function _update()
  _update_menu_controls()
  if not menu_active then
    update_controls()
    update_game_logic() -- Process game logic like hits, targeting, and states
  end
end

function _draw()
  _draw_main_menu()
  if menu_active then return end

  cls(0) -- Clear screen

  -- Draw all pieces using the helper function
  if pieces then
    for _, p_item in ipairs(pieces) do
      draw_piece(p_item) -- Call the helper for each piece
    end
  end

  -- Draw attacker capture indicators (if any cursor is in capture mode)
  local any_cursor_in_capture_mode = false
  if cursors then
    for _, cur_check in ipairs(cursors) do
      if cur_check.pending_type == "capture" then
        any_cursor_in_capture_mode = true
        break
      end
    end
  end

  if any_cursor_in_capture_mode and pieces then
    for _, p_attacker_check in ipairs(pieces) do
      if p_attacker_check and p_attacker_check.type == "attacker" then
        -- attacker_triangle_height is an upvalue from SECTION 7
        local radius = (attacker_triangle_height or 8)/2 + 2 
        circ(p_attacker_check.position.x, p_attacker_check.position.y, radius, 13) -- PICO-8 light-red/pink
      end
    end
  end

  -- Draw all cursors
  if cursors then
    for i,cur in ipairs(cursors) do
      local cx,cy = cur.x, cur.y
      local col = player.ghost_colors[i] or 7
      
      if cur.control_state==0 or cur.control_state==2 then -- Moving or in Cooldown
        if cur.pending_type=="defender" then
          rect(cx,cy,cx+7,cy+7,col)
        elseif cur.pending_type=="attacker" then
          local x,y=cx+4,cy+4 -- Center of 8x8 cursor box
          line(x,y-2,x-2,y+2,col) 
          line(x,y-2,x+2,y+2,col) 
          line(x-2,y+2,x+2,y+2,col) 
        else -- Capture mode cursor (crosshair)
          local x,y=cx+4,cy+4
          line(x-2,y,x+2,y,col); line(x,y-2,x,y+2,col)
        end
      elseif cur.control_state==1 then -- Placing: Draw ghost piece
        local tp={ owner=cur.pending_color, type=cur.pending_type,
                   position={x=cx+4,y=cy+4}, orientation=cur.pending_orientation }
        local v_ghost=get_piece_draw_vertices(tp)
        if tp.type=="attacker" then
          for j=1,3 do
            local k=j%3+1
            line(v_ghost[j].x,v_ghost[j].y,v_ghost[k].x,v_ghost[k].y,cur.pending_color)
          end
          -- Draw preview laser for attacker ghost
          local apex_ghost = v_ghost[1] 
          local dx_ghost = cos(tp.orientation)
          local dy_ghost = sin(tp.orientation)
          local min_t_ghost = LASER_LEN

          if pieces then 
            for _, existing_piece in ipairs(pieces) do
              if existing_piece and existing_piece.type == "defender" then
                local def_verts = get_piece_draw_vertices(existing_piece)
                if def_verts and #def_verts > 0 then
                  for j_vert=1, #def_verts do
                    local k_vert = (j_vert % #def_verts) + 1
                    local ix, iy, t_val = ray_segment_intersect(apex_ghost.x, apex_ghost.y, dx_ghost, dy_ghost, def_verts[j_vert].x, def_verts[j_vert].y, def_verts[k_vert].x, def_verts[k_vert].y)
                    if t_val and t_val >= 0 and t_val < min_t_ghost then 
                      min_t_ghost = t_val
                    end
                  end
                end
              end
            end
          end
          local beam_len_ghost = min(min_t_ghost, LASER_LEN)
          
          local laser_end_x = apex_ghost.x + dx_ghost * beam_len_ghost
          local laser_end_y = apex_ghost.y + dy_ghost * beam_len_ghost
          line(apex_ghost.x, apex_ghost.y, laser_end_x, laser_end_y, cur.pending_color)

        else -- Defender ghost
          for j_vert=1,4 do
            local k_vert=j_vert%4+1
            line(v_ghost[j_vert].x,v_ghost[j_vert].y,v_ghost[k_vert].x,v_ghost[k_vert].y,cur.pending_color)
          end
        end
      end
    end -- end for ipairs(cursors)
  end -- end if cursors
end-- SECTION 8: Game Loop
function _init()
  -- Initialize game state, players, etc.
  -- This will be called once when the cartridge starts
  -- start_game_with_players(3) -- Example: Start with 3 players immediately
end
-->8
-- SECTION 4: Placement Module
function legal_placement(piece) -- Made global by removing 'local'
  local w,h=8,8
  local th, tb = 8,6
  local bw,bh=128,128 
  local function vec_sub(a,b) return {x=a.x-b.x, y=a.y-b.y} end
  local function vec_dot(a,b) return a.x*b.x+a.y*b.y end

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
  local piece_corners = get_rot(piece) -- Cache rotated vertices of the current piece
  if pieces then
    for _, ep in ipairs(pieces) do -- Use ipairs for dense, 1-indexed array
      -- The check 'ep~=piece' is removed as 'piece' is not in 'pieces' table yet during this call.
      local ep_corners = get_rot(ep)
      
      local combined_axes = {}
      for ax_piece in all(get_axes(piece_corners)) do add(combined_axes, ax_piece) end
      for ax_ep in all(get_axes(ep_corners)) do add(combined_axes, ax_ep) end

      local collision_with_ep = true -- Assume collision until a separating axis is found
      if #combined_axes == 0 and #piece_corners > 0 and #ep_corners > 0 then
        -- This case can happen if polygons are degenerate (e.g. a line)
        -- For simplicity, assume non-degenerate or handle as collision if unsure.
      end

      for ax in all(combined_axes) do
        local min1, max1 = project(piece_corners, ax)
        local min2, max2 = project(ep_corners, ax)
        if max1 < min2 or max2 < min1 then -- Separating axis found
          collision_with_ep = false -- No collision between piece and ep
          break -- Stop checking axes for this pair
        end
      end

      if collision_with_ep then
        -- All axes showed overlap for this pair (piece, ep), so they collide
        return false -- Illegal placement
      end
    end
  end

  -- 3. attacker laser validation
  if piece.type == "attacker" then
    local apex = piece_corners[1] -- First vertex from get_rot for attacker is the apex
    local dir_x = cos(piece.orientation)
    local dir_y = sin(piece.orientation)
    
    local laser_hits_defender = false
    if pieces then -- Ensure pieces table exists
      for _, ep_val in ipairs(pieces) do -- Use ipairs for dense, 1-indexed array
        if ep_val.type == "defender" then
          local defender_corners = get_rot(ep_val) -- Get rotated corners of the existing defender
          for j = 1, #defender_corners do
            local k = (j % #defender_corners) + 1
            local x1, y1 = defender_corners[j].x, defender_corners[j].y
            local x2, y2 = defender_corners[k].x, defender_corners[k].y
            
            local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y, x1, y1, x2, y2)
            
            if t and t >= 0 and t <= LASER_LEN then -- Hit within laser range (t>=0 ensures it's forward)
              laser_hits_defender = true
              break -- Found a hit with this defender's segment
            end
          end
        end
        if laser_hits_defender then
          break -- Found a defender hit by the laser
        end
      end
    end
    
    if not laser_hits_defender then
      return false -- Attacker laser must hit a defender
    end
  end

  return true
end

function place_piece(p) -- Made global by removing 'local'
  -- p is the candidate piece data: { owner, type, position, orientation }
  if legal_placement(p) then
    -- Augment the piece data 'p' before adding it to the global 'pieces' list
    if p.type == "defender" then
      p.hits = 0
      p.state = "neutral" -- "successful", "unsuccessful", "overcharged"
      p.targeting_attackers = {} -- List of attacker pieces targeting this defender
    elseif p.type == "attacker" then
      -- Attackers don't have specific state like defenders in this mechanic
      -- but could have properties like 'currently_hitting = {}' if needed later
    end
    add(pieces, p) -- Add the (potentially augmented) piece 'p'
    -- redraw_lasers() was a placeholder, actual laser drawing is in _draw
  end
end
__gfx__
00000000aaaaaaaaaaaaaaaaaaaaaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9999999999999999999999a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9444444444444444444449a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9400000000000000000049a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9444444444444444444449a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000a9999999999999999999999a000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000aaaaaaaaaaaaaaaaaaaaaaaa000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__map__
0102020202020202020202020202020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1100000000000000000000000000001300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122222222222222222222222222222300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000

