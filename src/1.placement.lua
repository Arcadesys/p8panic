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