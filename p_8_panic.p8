pico-8 cartridge // http://www.pico-8.com
version 16
__lua__
--init
player_manager={}
player_manager.current_players={}
player_manager.init_players=function(n)
  player_manager.current_players={}
  for i=1,n do
    local c=player_manager.colors and player_manager.colors[i]or 7
    local gc=player_manager.ghost_colors and player_manager.ghost_colors[i]or 7
    player_manager.current_players[i]={
      id=i,
      score=0,
      color=c,
      ghost_color=gc,
      stash_counts={[c]=STASH_SIZE}
    }
  end
end
player_manager.get_player=function(i)
  return player_manager.current_players[i]
end
player_manager.reset_all_players=function()
  for _,p in pairs(player_manager.current_players)do p.score=0 end
end
STASH_SIZE=6
d=nil
pieces={}
LASER_LEN=60
N_PLAYERS=4
cursors={}
CAPTURE_RADIUS_SQUARED=64
global_game_state="main_menu"
countdown_timer=0
initiate_game_start_request=false
panic_display_timer=0

player_count=N_PLAYERS
stash_count=STASH_SIZE
function point_in_polygon(px,py,vertices)
  local inside=false
  local n=#vertices
  for i=1,n do
    local j=(i%n)+1
    local xi,yi=vertices[i].x,vertices[i].y
    local xj,yj=vertices[j].x,vertices[j].y
    if((yi>py)~=(yj>py))and(px<(xj-xi)*(py-yi)/((yj-yi)+0.0001)+xi)then
      inside=not inside
    end
  end
  return inside
end

local cos,sin=cos,sin
local max,min=max,min
local sqrt,abs=sqrt,abs
function ray_segment_intersect(ray_ox,ray_oy,ray_dx,ray_dy,seg_x1,seg_y1,seg_x2,seg_y2)
  local s_dx=seg_x2-seg_x1
  local s_dy=seg_y2-seg_y1
  local r_s_cross=ray_dx*s_dy-ray_dy*s_dx
  if r_s_cross==0 then return nil,nil,nil end
  
  local t2=((seg_x1-ray_ox)*ray_dy-(seg_y1-ray_oy)*ray_dx)/r_s_cross
  local t1=((seg_x1-ray_ox)*s_dy-(seg_y1-ray_oy)*s_dx)/r_s_cross
  
  if t1>=0 and t2>=0 and t2<=1 then
    return ray_ox+t1*ray_dx,ray_oy+t1*ray_dy,t1
  end
  return nil,nil,nil
end
function attempt_capture(player_obj,cursor)
  local player_id=player_obj.id
  for _,def_obj in ipairs(pieces)do
    if def_obj.type=="defender"and def_obj.owner_id==player_id and def_obj.state=="overcharged"then
      if def_obj.targeting_attackers then
        for attacker_idx=#def_obj.targeting_attackers,1,-1 do
          local attacker_to_capture=def_obj.targeting_attackers[attacker_idx]
          if attacker_to_capture then
            local dist_x=(cursor.x+4)-attacker_to_capture.position.x
            local dist_y=(cursor.y+4)-attacker_to_capture.position.y
            
            if(dist_x*dist_x+dist_y*dist_y)<CAPTURE_RADIUS_SQUARED then
              local captured_color=attacker_to_capture:get_color()
              player_obj:add_captured_piece(captured_color)
              if del(pieces,attacker_to_capture)then
                deli(def_obj.targeting_attackers,attacker_idx)
                return true 
              end
            end
          end
        end
      end
    end
  end
  return false
end
sfx_on=true
game_timer=3
config={
  player_options={2,3,4},
  current_players_idx=3,

  timer_options={1,2,3,5,10},
  current_timer_idx=3,

  get_players_value=function()return config.player_options[config.current_players_idx]end,
  set_players_idx=function(idx)
    config.current_players_idx=idx
    N_PLAYERS=config.get_players_value()
  end,

  get_timer_value=function()return config.timer_options[config.current_timer_idx]end,
  set_timer_idx=function(idx)
    config.current_timer_idx=idx
    game_timer=config.get_timer_value()
  end
}

N_PLAYERS=config.get_players_value()
game_timer=config.get_timer_value()
-->8
--player
local Player={}
Player.__index=Player
function Player:new(id,score0,c0,gc0)
  local instance={
    id=id,
    score=score0 or 0,
    color=c0,
    ghost_color=gc0,
    stash={},
    stash_counts={},
    captured_pieces_count=0 
  }
  instance.stash_counts[c0]=STASH_SIZE or 6

  setmetatable(instance,self)
  return instance
end
function Player:get_score()return self.score end
function Player:add_score(pts)
  self.score=self.score+(pts or 1)
end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:add_captured_piece(piece_color)
  if self.stash_counts[piece_color]==nil then
    self.stash_counts[piece_color]=0
  end
  self.stash_counts[piece_color]+=1
  if self.stash[piece_color]==nil then
    self.stash[piece_color]=0
  end
  self.stash[piece_color]+=1
end
function Player:get_piece_count(piece_color)
  return self.stash[piece_color]or 0
end
function Player:has_piece(piece_color)
  return(self.stash[piece_color]or 0)>0
end
function Player:use_piece_from_stash(piece_color_to_use)
  if self.stash_counts[piece_color_to_use]and self.stash_counts[piece_color_to_use]>0 then
    self.stash_counts[piece_color_to_use]-=1
    printh("P"..self.id.." used c:"..piece_color_to_use..". Stash: "..(self.stash_counts[piece_color_to_use]or 0))
    
    if self.stash[piece_color_to_use]and self.stash[piece_color_to_use]>0 then
      self.stash[piece_color_to_use]-=1
    end
    return true
  else
    return false
  end
end
player_manager.colors={
  [1]=12,
  [2]=8,
  [3]=11,
  [4]=10
}
player_manager.ghost_colors={
  [1]=5,
  [2]=14,
  [3]=3,
  [4]=15
}
player_manager.current_players={}

player_manager.init_players=function(n)
  player_manager.current_players={}
  for i=1,n do
    local p_color=player_manager.colors[i]
    local p_ghost_color=player_manager.ghost_colors[i]
    if Player and Player.new then
      player_manager.current_players[i]=Player:new(i,0,p_color,p_ghost_color)
    else
      player_manager.current_players[i]={id=i,score=0,color=p_color,ghost_color=p_ghost_color,stash={},stash_counts={[p_color]=STASH_SIZE or 6}} 
    end
  end
end
player_manager.get_player=function(id)
  return player_manager.current_players[id]
end

function player_manager.reset_all_players()
  for _,player_obj in ipairs(player_manager.current_players)do
    if player_obj then
      player_obj.score=0
    end
  end
end
function create_player(id,score0,c0,gc0)
  if Player and Player.new then
    return Player:new(id,score0,c0,gc0)
  else
    return{
      id=id,
      score=score0 or 0,
      color=c0 or 7,
      ghost_color=gc0 or 7,
      stash={},
      stash_counts={[c0 or 7]=STASH_SIZE or 6}
    }
  end
end
-->8
--scoring
function reset_player_scores()
  if player_manager and player_manager.current_players then
    for _,player_obj in ipairs(player_manager.current_players)do
      if player_obj then
        player_obj.score=0
      end
    end
  end
end

function reset_piece_states_for_scoring()
  for _,p_obj in ipairs(pieces)do
    if p_obj then
      p_obj.hits=0
      p_obj.targeting_attackers={}
    end
  end
end

function _check_attacker_hit_defender(attacker_obj,defender_obj,player_manager_param,ray_segment_intersect_func,current_laser_len,add_func)
  local attacker_vertices=attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices==0 then return end
  local apex=attacker_vertices[1]
  local dir_x=cos(attacker_obj.orientation)
  local dir_y=sin(attacker_obj.orientation)

  local defender_corners=defender_obj:get_draw_vertices()
  if not defender_corners or #defender_corners==0 then return end

  for j=1,#defender_corners do
    local k=(j%#defender_corners)+1
    local ix,iy,t=ray_segment_intersect_func(apex.x,apex.y,dir_x,dir_y,
                                             defender_corners[j].x,defender_corners[j].y,
                                             defender_corners[k].x,defender_corners[k].y)
    if t and t>=0 and t<=current_laser_len then
      defender_obj.hits=(defender_obj.hits or 0)+1
      defender_obj.targeting_attackers=defender_obj.targeting_attackers or{}
      add_func(defender_obj.targeting_attackers,attacker_obj)

      local attacker_player=player_manager_param.get_player(attacker_obj.owner_id)
      local defender_player=player_manager_param.get_player(defender_obj.owner_id)

      if attacker_player and defender_player and attacker_obj.owner_id~=defender_obj.owner_id then
        attacker_player:add_score(1)
      end

      if defender_obj.hits==1 then
        defender_obj.state="successful"
      elseif defender_obj.hits==2 then
        defender_obj.state="unsuccessful"
      elseif defender_obj.hits>=3 then
        defender_obj.state="overcharged"
      end
      return true
    end
  end
  return false
end

function _score_defender(p_obj,player_manager_param)
  if p_obj and p_obj.type=="defender"then
    local num_total_attackers_targeting=0
    if p_obj.targeting_attackers then
      num_total_attackers_targeting=#p_obj.targeting_attackers
    end
    p_obj.dbg_target_count=num_total_attackers_targeting

    if num_total_attackers_targeting<=1 then
      local defender_player=player_manager_param.get_player(p_obj.owner_id)
      if defender_player then
        defender_player:add_score(1)
      end
    end
  end
end

function score_pieces()
  reset_player_scores()
  reset_piece_states_for_scoring()

  for _,attacker_obj in ipairs(pieces)do
    if attacker_obj and attacker_obj.type=="attacker"then
      for _,defender_obj in ipairs(pieces)do
        if defender_obj and defender_obj.type=="defender"then
          _check_attacker_hit_defender(attacker_obj,defender_obj,player_manager,ray_segment_intersect,LASER_LEN,add)
        end
      end
    end
  end

  for _,p_obj in ipairs(pieces)do
    _score_defender(p_obj,player_manager)
  end

  local remaining_pieces={}
  for _,p_obj in ipairs(pieces)do
    if not p_obj.captured_flag then
      add(remaining_pieces,p_obj)
    else
      printh("Piece removed due to overcharge capture: P"..p_obj.owner_id.." "..p_obj.type)
    end
  end
  pieces=remaining_pieces
end

function calculate_final_scores()
  score_pieces()
end

update_game_state=score_pieces
-->8
--piece
Piece={}
Piece.__index=Piece

Attacker={}
Attacker.__index=Attacker
setmetatable(Attacker,{__index=Piece})

Defender={}
Defender.__index=Defender
setmetatable(Defender,{__index=Piece})

DEFENDER_WIDTH=8
DEFENDER_HEIGHT=8
local ATTACKER_TRIANGLE_HEIGHT=8
local ATTACKER_TRIANGLE_BASE=6

local cos,sin=cos,sin
local max,min=max,min
local sqrt,abs=sqrt,abs

function Piece:new(o)
  o=o or{}
  o.position=o.position or{x=64,y=64}
  o.orientation=o.orientation or 0
  setmetatable(o,self)
  return o
end

function Piece:get_color()
  if self.is_ghost and self.ghost_color_override then
    return self.ghost_color_override
  end
  if self.color then
    return self.color
  end
  if self.owner_id then
    local owner_player=player_manager.get_player(self.owner_id)
    if owner_player then
      return owner_player:get_color()
    end
  end
  return 7
end

function Piece:get_draw_vertices()
  local o=self.orientation
  local cx=self.position.x
  local cy=self.position.y
  local local_corners={}

  if self.type=="attacker"then
    local h=ATTACKER_TRIANGLE_HEIGHT
    local b=ATTACKER_TRIANGLE_BASE
    add(local_corners,{x=h/2,y=0})
    add(local_corners,{x=-h/2,y=b/2})
    add(local_corners,{x=-h/2,y=-b/2})
  else
    local w,h=DEFENDER_WIDTH,DEFENDER_HEIGHT
    local hw=w/2
    local hh=h/2
    add(local_corners,{x=-hw,y=-hh})
    add(local_corners,{x=hw,y=-hh})
    add(local_corners,{x=hw,y=hh})
    add(local_corners,{x=-hw,y=hh})
  end

  local world_corners={}
  for lc in all(local_corners)do
    local rotated_x=lc.x*cos(o)-lc.y*sin(o)
    local rotated_y=lc.x*sin(o)+lc.y*cos(o)
    add(world_corners,{x=cx+rotated_x,y=cy+rotated_y})
  end
  return world_corners
end

function Piece:draw()
  local vertices=self:get_draw_vertices()
  local color=self:get_color()
  if #vertices>=3 then
    for i=1,#vertices do
      local v1=vertices[i]
      local v2=vertices[(i%#vertices)+1]
      line(v1.x,v1.y,v2.x,v2.y,color)
    end
  end
end

function Attacker:new(o)
  o=o or{}
  o.type="attacker"
  return Piece.new(self,o)
end

function Attacker:draw()
  Piece.draw(self)
  
  local vertices=self:get_draw_vertices()
  if not vertices or #vertices==0 then return end
  local apex=vertices[1]

  local dir_x=cos(self.orientation)
  local dir_y=sin(self.orientation)
  local laser_color=self:get_color()
  local laser_end_x=apex.x+dir_x*LASER_LEN
  local laser_end_y=apex.y+dir_y*LASER_LEN
  local closest_hit_t=LASER_LEN

  local hit_defender_state=nil

  if pieces then
    for _,other_piece in ipairs(pieces)do
      if other_piece.type=="defender"then
        local def_corners=other_piece:get_draw_vertices()
        for j=1,#def_corners do
          local k=(j%#def_corners)+1
          local ix,iy,t=ray_segment_intersect(
            apex.x,apex.y,dir_x,dir_y,
            def_corners[j].x,def_corners[j].y,def_corners[k].x,def_corners[k].y
          )
          if t and t>=0 and t<closest_hit_t then
            closest_hit_t=t
            laser_end_x=ix
            laser_end_y=iy
            hit_defender_state=other_piece.state
          end
        end
      end
    end
  end

  if hit_defender_state=="unsuccessful"then
    laser_color=8
  elseif hit_defender_state=="overcharged"then
    laser_color=10
  end

  local ant_spacing=4
  local ant_length=2
  local num_ants=flr(closest_hit_t/ant_spacing)
  local time_factor=time()*20

  for i=0,num_ants-1 do
    local ant_start_t=(i*ant_spacing+time_factor)%closest_hit_t
    local ant_end_t=ant_start_t+ant_length
    
    if ant_end_t<=closest_hit_t then
      local ant_start_x=apex.x+dir_x*ant_start_t
      local ant_start_y=apex.y+dir_y*ant_start_t
      local ant_end_x=apex.x+dir_x*ant_end_t
      local ant_end_y=apex.y+dir_y*ant_end_t
      line(ant_start_x,ant_start_y,ant_end_x,ant_end_y,laser_color)
    else
      local segment1_end_t=closest_hit_t
      local segment1_start_x=apex.x+dir_x*ant_start_t
      local segment1_start_y=apex.y+dir_y*ant_start_t
      local segment1_end_x=apex.x+dir_x*segment1_end_t
      local segment1_end_y=apex.y+dir_y*segment1_end_t
      line(segment1_start_x,segment1_start_y,segment1_end_x,segment1_end_y,laser_color)
      
      local segment2_len=ant_end_t-closest_hit_t
      if segment2_len>0 then
        local segment2_start_x=apex.x
        local segment2_start_y=apex.y
        local segment2_end_x=apex.x+dir_x*segment2_len
        local segment2_end_y=apex.y+dir_y*segment2_len
        line(segment2_start_x,segment2_start_y,segment2_end_x,segment2_end_y,laser_color)
      end
    end
  end
end

function Defender:new(o)
  o=o or{}
  o.type="defender"
  o.hits=0
  o.state="neutral"
  o.targeting_attackers={}
  return Piece.new(self,o)
end

function Defender:draw()
  local vertices=self:get_draw_vertices()
  local color=self:get_color()
  if #vertices==4 then
    line(vertices[1].x,vertices[1].y,vertices[2].x,vertices[2].y,color)
    line(vertices[2].x,vertices[2].y,vertices[3].x,vertices[3].y,color)
    line(vertices[3].x,vertices[3].y,vertices[4].x,vertices[4].y,color)
    line(vertices[4].x,vertices[4].y,vertices[1].x,vertices[1].y,color)
  end
end

function create_piece(params)
  local piece_obj
  if params.type=="attacker"then
    piece_obj=Attacker:new(params)
  elseif params.type=="defender"then
    piece_obj=Defender:new(params)
  else
    printh("Error: Unknown piece type: "..(params.type or"nil"))
    return nil
  end
  return piece_obj
end
-->8
--placement
function legal_placement(piece_params)
  local bw,bh=128,128
  local temp_piece_obj=create_piece(piece_params)
  if not temp_piece_obj then return false end

  local function vec_sub(a,b)return{x=a.x-b.x,y=a.y-b.y}end
  local function vec_dot(a,b)return a.x*b.x+a.y*b.y end
  local function project(vs,ax)
    if not vs or #vs==0 then return 0,0 end
    local mn,mx=vec_dot(vs[1],ax),vec_dot(vs[1],ax)
    for i=2,#vs do
      local pr=vec_dot(vs[i],ax)
      mn,mx=min(mn,pr),max(mx,pr)
    end
    return mn,mx
  end
  local function get_axes(vs)
    local ua={}
    if not vs or #vs<2 then return ua end
    for i=1,#vs do
      local p1=vs[i]
      local p2=vs[(i%#vs)+1]
      local e=vec_sub(p2,p1)
      local n={x=-e.y,y=e.x}
      local l=sqrt(n.x^2+n.y^2)
      if l>0.0001 then
        n.x,n.y=n.x/l,n.y/l
        local uniq=true
        for ea in all(ua)do if abs(vec_dot(ea,n))>0.999 then uniq=false;break end end
        if uniq then add(ua,n)end
      end
    end
    return ua
  end

  local corners=temp_piece_obj:get_draw_vertices()
  if not corners or #corners==0 then return false end
  for c in all(corners)do
    if c.x<0 or c.x>bw or c.y<0 or c.y>bh then return false end
  end

  for _,ep_obj in ipairs(pieces)do
    local ep_corners=ep_obj:get_draw_vertices()
    if not ep_corners or #ep_corners==0 then goto next_ep_check end

    local combined_axes={}
    for ax_piece in all(get_axes(corners))do add(combined_axes,ax_piece)end
    for ax_ep in all(get_axes(ep_corners))do add(combined_axes,ax_ep)end
    
    if #combined_axes==0 then
        local min_x1,max_x1,min_y1,max_y1=bw,0,bh,0
        for c in all(corners)do min_x1=min(min_x1,c.x)max_x1=max(max_x1,c.x)min_y1=min(min_y1,c.y)max_y1=max(max_y1,c.y)end
        local min_x2,max_x2,min_y2,max_y2=bw,0,bh,0
        for c in all(ep_corners)do min_x2=min(min_x2,c.x)max_x2=max(max_x2,c.x)min_y2=min(min_y2,c.y)max_y2=max(max_y2,c.y)end
        if not(max_x1<min_x2 or max_x2<min_x1 or max_y1<min_y2 or max_y2<min_y1)then
            return false 
        end
        goto next_ep_check 
    end

    local collision_with_ep=true
    for ax in all(combined_axes)do
      local min1,max1=project(corners,ax)
      local min2,max2=project(ep_corners,ax)
      if max1<min2 or max2<min1 then
        collision_with_ep=false
        break
      end
    end
    if collision_with_ep then return false end
    ::next_ep_check::
  end

  if piece_params.type=="attacker"then
    local apex=corners[1]
    local dir_x=cos(piece_params.orientation)
    local dir_y=sin(piece_params.orientation)
    local laser_hits_defender=false
    for _,ep_obj in ipairs(pieces)do
      if ep_obj.type=="defender"then
        local def_corners=ep_obj:get_draw_vertices()
        if not def_corners or #def_corners==0 then goto next_laser_target_check end
        for j=1,#def_corners do
          local k=(j%#def_corners)+1
          local ix,iy,t=ray_segment_intersect(
            apex.x,apex.y,dir_x,dir_y,
            def_corners[j].x,def_corners[j].y,def_corners[k].x,def_corners[k].y
          )
          if t and t>=0 and t<=LASER_LEN then
            laser_hits_defender=true
            break
          end
        end
      end
      if laser_hits_defender then break end
      ::next_laser_target_check::
    end
    if not laser_hits_defender then return false end
  end

  return true
end

function place_piece(piece_params,player_obj)
  if legal_placement(piece_params)then
    local piece_color_to_place=piece_params.color

    if piece_color_to_place==nil then
      printh("PLACE ERROR: piece_params.color is NIL!")
      return false
    end
    
    printh("Place attempt: P"..player_obj.id.." color: "..tostring(piece_color_to_place).." type: "..piece_params.type)

    if player_obj:use_piece_from_stash(piece_color_to_place)then
      local new_piece_obj=create_piece(piece_params)
      if new_piece_obj then
        add(pieces,new_piece_obj)
        score_pieces()
        printh("Placed piece with color: "..tostring(new_piece_obj:get_color()))
        return true
      else
        printh("Failed to create piece object after stash use.")
        player_obj:add_captured_piece(piece_color_to_place)
        return false
      end
    else
      printh("P"..player_obj.id.." has no piece of color "..tostring(piece_color_to_place).." in stash.")
      return false
    end
  else
    printh("Placement not legal for P"..player_obj.id)
    return false
  end
end
-->8
--controls
local CSTATE_MOVE_SELECT=0
local CSTATE_ROTATE_PLACE=1
local CSTATE_COOLDOWN=2
function update_controls()
  if controls_disabled then return end
  local cursor_speed=2
  local rotation_speed=0.02
  for i,cur in ipairs(cursors)do
    local current_player_obj=player_manager.get_player(i)
    if not current_player_obj then goto next_cursor_ctrl end
    if cur.control_state==CSTATE_MOVE_SELECT then
      if btn(⬅️,i-1)then cur.x=max(0,cur.x-cursor_speed)end
      if btn(➡️,i-1)then cur.x=min(cur.x+cursor_speed,128-8)end
      if btn(⬆️,i-1)then cur.y=max(0,cur.y-cursor_speed)end
      if btn(⬇️,i-1)then cur.y=min(cur.y+cursor_speed,128-8)end

      if btnp(🅾️,i-1)then
        if cur.pending_type=="defender"then
          cur.pending_type="attacker"
        elseif cur.pending_type=="attacker"then
          cur.pending_type="capture"
        elseif cur.pending_type=="capture"then
          cur.pending_type="defender"
        end
      end

      if btnp(❎,i-1)then
        if cur.pending_type=="capture"then
          if attempt_capture(current_player_obj,cur)then
            cur.control_state=CSTATE_COOLDOWN;cur.return_cooldown=6
            if original_update_game_logic_func then original_update_game_logic_func()end
          end
        else
          cur.control_state=CSTATE_ROTATE_PLACE
          cur.pending_orientation=0
        end
      end
    elseif cur.control_state==CSTATE_ROTATE_PLACE then
      local available_colors={}
      if current_player_obj and current_player_obj.stash_counts then
        for color,count in pairs(current_player_obj.stash_counts)do
          if count>0 then add(available_colors,color)end
        end
      end
      if #available_colors==0 then available_colors={current_player_obj:get_color()}end
      if cur.color_select_idx>#available_colors then cur.color_select_idx=1 end
      if cur.color_select_idx<1 then cur.color_select_idx=#available_colors end

      if btnp(⬆️,i-1)then
        cur.color_select_idx=cur.color_select_idx-1
        if cur.color_select_idx<1 then cur.color_select_idx=#available_colors end
      elseif btnp(⬇️,i-1)then
        cur.color_select_idx=cur.color_select_idx+1
        if cur.color_select_idx>#available_colors then cur.color_select_idx=1 end
      end

      if btn(⬅️,i-1)then
        cur.pending_orientation=cur.pending_orientation-rotation_speed
        if cur.pending_orientation<0 then cur.pending_orientation=cur.pending_orientation+1 end
      end
      if btn(➡️,i-1)then
        cur.pending_orientation=cur.pending_orientation+rotation_speed
        if cur.pending_orientation>=1 then cur.pending_orientation=cur.pending_orientation-1 end
      end

      cur.pending_color=available_colors[cur.color_select_idx]or current_player_obj:get_color()

      if btnp(❎,i-1)then
        local piece_params={
          owner_id=i,
          type=cur.pending_type,
          position={x=cur.x+4,y=cur.y+4},
          orientation=cur.pending_orientation,
          color=cur.pending_color
        }
        if place_piece(piece_params,current_player_obj)then
          cur.control_state=CSTATE_COOLDOWN
          cur.return_cooldown=6
          if original_update_game_logic_func then original_update_game_logic_func()end
        end
      end
      if btnp(🅾️,i-1)then
        cur.control_state=CSTATE_MOVE_SELECT
      end

    elseif cur.control_state==CSTATE_COOLDOWN then
      cur.return_cooldown=cur.return_cooldown-1
      if cur.return_cooldown<=0 then
        cur.x=cur.spawn_x
        cur.y=cur.spawn_y
        cur.control_state=CSTATE_MOVE_SELECT
        cur.pending_orientation=0
        cur.pending_type="defender"
        cur.pending_color=(current_player_obj and current_player_obj:get_ghost_color())or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
--ui
ui={}

local pyr_vertices={
  {0,-0.8,0},
  {-1,0.8,-1},
  {1,0.8,-1},
  {1,0.8,1},
  {-1,0.8,1}
}
local pyr_edges={
  {1,2},{1,3},{1,4},{1,5},
  {2,3},{3,4},{4,5},{5,2}
}
local pyr_angle_x=0
local pyr_angle_y=0
local pyr_angle_z=0

function pyr_rotate_point(v,ax,ay,az)
  local x,y,z=v[1],v[2],v[3]
  local cy,sy=cos(ax),sin(ax)
  y,z=y*cy-z*sy,y*sy+z*cy
  local cx,sx=cos(ay),sin(ay)
  x,z=x*cx+z*sx,-x*sx+z*cx
  local cz,sz=cos(az),sin(az)
  x,y=x*cz-y*sz,x*sz+y*cz
  return{x,y,z}
end

function pyr_project_point(v,projection_scale)
  local viewer_z=3
  local px=v[1]/(viewer_z-v[3])
  local py=v[2]/(viewer_z-v[3])
  return 64+px*projection_scale,64+py*projection_scale
end

function draw_pyramid(size, color)
  -- Animate angles
  pyr_angle_x += 0.01
  pyr_angle_y += 0.013
  pyr_angle_z += 0.008
  -- Transform and project
  local pts2d = {}
  local current_projection_scale = size or 48 -- Default size if not provided
  for i,v in ipairs(pyr_vertices) do
    local v3 = pyr_rotate_point(v, pyr_angle_x, pyr_angle_y, pyr_angle_z)
    local sx, sy = pyr_project_point(v3, current_projection_scale)
    pts2d[i] = {sx, sy}
  end
  -- Draw edges
  local edge_color=color or 6
  for e in all(pyr_edges)do
    local a,b=pts2d[e[1]],pts2d[e[2]]
    line(a[1],a[2],b[1],b[2],edge_color)
  end
end

function ui.draw_main_menu()
  cls(0)
  draw_pyramid(48,6)
  print("P8PANIC",48,20,7)
  local options={
    "Players: "..(menu_player_count or N_PLAYERS or 2),
    "Stash Size: "..(menu_stash_size or STASH_SIZE or 3),
    "Game Timer: "..(game_timer or 3).." min",
    "Start Game",
    "Finish Game",
    "How To Play"
  }
  for i,opt in ipairs(options)do
    local y=38+i*9
    local col=(menu_option==i and 11)or 7
    print(opt,20,y,col)
    if menu_option==i then
      print("\136",10,y,11)
    end
  end
end

function ui.draw_how_to_play()
  cls(0)
  print("HOW TO PLAY",30,20,7)
  print("Use arrows to navigate",10,40,7)
  print("Press (X) to select",10,50,7)
  print("Press (X) to return",10,100,7)
end

function ui.draw_game_hud()
  local screen_w=128
  local screen_h=128
  local margin=5
  local line_h=6

  local corners = {
    -- P1: Top-Left (score at y, stash below)
    { x = margin, y = margin, align_right = false, stash_y_multiplier = 1 },
    -- P2: Top-Right (score at y, stash below)
    { x = screen_w - margin, y = margin, align_right = true, stash_y_multiplier = 1 },
    -- P3: Bottom-Left (score at y, stash above)
    { x = margin, y = screen_h - margin - line_h, align_right = false, stash_y_multiplier = -1 },
    -- P4: Bottom-Right (score at y, stash above)
    { x = screen_w - margin, y = screen_h - margin - line_h, align_right = true, stash_y_multiplier = -1 }
  }

  for i = 1, (N_PLAYERS or 1) do -- Use global N_PLAYERS
    local p = player_manager and player_manager.current_players and player_manager.current_players[i] -- Use global player_manager
    if p then
      local corner_cfg = corners[i]
      if not corner_cfg then goto continue_loop end

      local current_x_anchor = corner_cfg.x
      local score_print_y = corner_cfg.y
      local align_right = corner_cfg.align_right

      -- 1. Print Score
      local score_val = p.score or 0
      local score_text_prefix = "" -- "SCORE " removed
      local score_text_full = score_text_prefix .. score_val
      local print_x_score
      if align_right then
        print_x_score = current_x_anchor - (#score_text_full * 4)
      else
        print_x_score = current_x_anchor
      end
      print(score_text_full, print_x_score, score_print_y, p.color or 7)

      -- 2. Print Stash Bars
      local bar_width = 2 -- Remains 2, as per previous modification
      local bar_h_spacing = 1 
      local effective_bar_step = bar_width + bar_h_spacing
      local stash_item_max_height = 8

      local num_distinct_colors = 0
      if type(p.stash_counts) == "table" then
        for _color, count_val in pairs(p.stash_counts) do
          if count_val > 0 then -- Only count if a bar will be drawn
            num_distinct_colors = num_distinct_colors + 1
          end
        end
      end

      local total_stash_block_width
      if num_distinct_colors > 0 then
        total_stash_block_width = (num_distinct_colors * bar_width) + ((num_distinct_colors - 1) * bar_h_spacing)
      else
        total_stash_block_width = 0
      end
      
      local block_render_start_x
      if align_right then
        block_render_start_x = current_x_anchor - total_stash_block_width
      else
        block_render_start_x = current_x_anchor
      end

      if type(p.stash_counts) == "table" and num_distinct_colors > 0 then
        local bar_idx = 0
        for piece_color, count in pairs(p.stash_counts) do
          if count > 0 then
            local item_actual_color = piece_color
            
            local bar_height = min(count, stash_item_max_height)
            local current_bar_x_start_offset = bar_idx * effective_bar_step
            local current_bar_x_start = block_render_start_x + current_bar_x_start_offset
            local current_bar_x_end = current_bar_x_start + bar_width - 1

            if corner_cfg.stash_y_multiplier == 1 then
              local bar_top_y = score_print_y + line_h
              rectfill(current_bar_x_start, bar_top_y, current_bar_x_end, bar_top_y + bar_height - 1, item_actual_color)
            else
              local bar_bottom_y = score_print_y - 1
              rectfill(current_bar_x_start, bar_bottom_y - bar_height + 1, current_bar_x_end, bar_bottom_y, item_actual_color)
            end
            bar_idx = bar_idx + 1
          end
        end
      end
    end
    ::continue_loop::
  end
end

function ui.draw_winner_screen()
  cls(0)
  calculate_final_scores() -- Calculate final scores before displaying
  print("GAME OVER!", 44, 25, 8)

  -- Gather player scores
  local player_scores = {}
  if player_manager and player_manager.get_player and N_PLAYERS then
    for i=1,N_PLAYERS do
      local p = player_manager.get_player(i)
      if p and p.score then
        add(player_scores, {id=i, score=p.score})
      end
    end
  end

  -- Sort by score descending
  for i=1,#player_scores-1 do
    for j=i+1,#player_scores do
      if player_scores[j].score > player_scores[i].score then
        local tmp = player_scores[i]
        player_scores[i] = player_scores[j]
        player_scores[j] = tmp
      end
    end
  end

  -- Print four key/value pairs: 1st, 2nd, 3rd, 4th
  local places = {"1st", "2nd", "3rd", "4th"}
  for i=1,4 do
    local ps = player_scores[i]
    local y = 40 + i*12
    if ps then
      print(places[i]..": Player "..ps.id.."  Score: "..ps.score, 20, y, 7)
    else
      print(places[i]..": ---", 20, y, 7)
    end
  end

  print("Press (X) to return", 28, 100, 7)
end
 
-- Draw the How To Play screen
function ui.draw_how_to_play() -- Keep this instance
  cls(0)
  print("HOW TO PLAY", 40, 20, 7)
  -- Placeholder instructions
  print("Use arrows to navigate menu", 10, 40, 7)
  print("Press (X) to select", 10, 50, 7)
  print("Press (X) to return", 10, 100, 7)
end

function ui.update_main_menu_logic() -- Renamed from _update_main_menu_logic
  -- Navigate options
  if btnp(3) then menu_option = min(6, menu_option + 1) end -- down, max option is 6
  if btnp(2) then menu_option = max(1, menu_option - 1) end -- up
  
  -- Adjust values
  if menu_option == 1 then -- Players
    if btnp(1) then menu_player_count = min(4, menu_player_count + 1) end -- right (increase)
    if btnp(0) then menu_player_count = max(2, menu_player_count - 1) end -- left (decrease)
  elseif menu_option == 2 then -- Stash Size
    if btnp(1) then menu_stash_size = min(10, menu_stash_size + 1) end -- right (increase)
    if btnp(0) then menu_stash_size = max(3, menu_stash_size - 1) end -- left (decrease)
  elseif menu_option == 3 then -- Game Timer
    if btnp(1) then game_timer = min(10, game_timer + 1) end -- right (increase)
    if btnp(0) then game_timer = max(1, game_timer - 1) end -- left (decrease)
  end
  -- Select option
  if btnp(5) then -- ❎ (X)
    if menu_option == 4 then -- Start Game
      -- Update N_PLAYERS and STASH_SIZE from menu selections
      N_PLAYERS = menu_player_count
      STASH_SIZE = menu_stash_size
      -- game_timer is already set globally by menu navigation

      initiate_game_start_request = true -- Set the flag to request game start
      printh("Menu: Requested Start Game. P:"..N_PLAYERS.." S:"..STASH_SIZE.." T:"..game_timer)
      -- DO NOT change global_game_state here directly.
    elseif menu_option == 5 then -- Finish Game (New Option)
      N_PLAYERS = menu_player_count -- Set N_PLAYERS from current menu selection
      STASH_SIZE = menu_stash_size -- Set STASH_SIZE for consistency

      -- Ensure player_manager is initialized for the current N_PLAYERS setting.
      -- This is important if "Finish Game" is hit before "Start Game" or after changing player count.
      -- player_manager.init_players should create players with score 0 if they don't exist.
      local needs_player_init = true -- Assume init is needed by default
      if player_manager and player_manager.get_player then
        local players_seem_correctly_initialized = true
        for i=1, N_PLAYERS do
          if not player_manager.get_player(i) then
            players_seem_correctly_initialized = false
            break
          end
        end
        -- This check is simplified; init_players should handle making it correct for N_PLAYERS.
        -- If player_manager.init_players is robust, we can call it to ensure state.
      end
      
      if player_manager and player_manager.init_players then
        printh("Finish Game: Ensuring players are initialized for P:"..N_PLAYERS)
        player_manager.init_players(N_PLAYERS)
      end
      global_game_state = "game_over"
      printh("Menu: Finish Game selected. Set state to game_over. Configured P:"..N_PLAYERS)
    elseif menu_option == 6 then -- How To Play (old option index 5)
      global_game_state = "how_to_play"
    end
  end
end

local SPRITES = {
  HEART_ICON = 208 -- Example sprite number for heart
  -- ... other sprites
}

-- Define menu items
ui.menu_items = {
  {text="CONTINUE", action=function() gs.set_state("in_game") end, visible = function() return gs.current_state_name == "paused" end},
  {text="FINISH GAME", action=function() gs.set_state("game_over") end, visible = function() return gs.current_state_name == "paused" end},
  {text="RETURN TO MAIN MENU", action=function() gs.set_state("main_menu") end, visible = function() return gs.current_state_name == "paused" end},
  {text="START GAME", action=function() gs.set_state("in_game") end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="PLAYERS:", type="selector", options=config.player_options, current_idx_func=function() return config.current_players_idx end, action=function(idx) config.set_players_idx(idx) end, value_text_func=function() return config.get_players_value() end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="SET TIMER:", type="selector", options=config.timer_options, current_idx_func=function() return config.current_timer_idx end, action=function(idx) config.set_timer_idx(idx) end, value_text_func=function() return config.get_timer_value().." MIN" end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="HOW TO PLAY", action=function() gs.set_state("how_to_play") end, visible = function() return gs.current_state_name == "main_menu" end},
  {text="FAVOURITE", action=function() favourite_current_game() end, icon=SPRITES.HEART_ICON, visible = function() return gs.current_state_name == "main_menu" end},
  {text="RESET CART", action=function() reset_cart() end}, 
  {text="SHUTDOWN", action=function() shutdown() end}
} -- Ensure the table is properly closed here

function ui.draw_countdown_screen()
  -- printh("ui.draw_countdown_screen called. countdown_timer: " .. tostr(countdown_timer)) -- DEBUG -- Temporarily commented out
  cls(0) -- Clear screen

  if type(ui.draw_playfield_background) == "function" then ui.draw_playfield_background() end
  if type(ui.draw_game_hud) == "function" then ui.draw_game_hud() end -- Changed from draw_player_huds
  if type(cursors) == "table" and type(cursors.draw_all) == "function" then cursors.draw_all() end -- Changed from ui.draw_cursors
  if type(pieces) == "table" and type(pieces.draw_all) == "function" then pieces.draw_all() end -- Changed from ui.draw_pieces

  local countdown_text = ""
  local current_cd_time = countdown_timer or 0

  if current_cd_time > 2 then
    countdown_text = "3"
  elseif current_cd_time > 1 then
    countdown_text = "2"
  elseif current_cd_time > 0 then
    countdown_text = "1"
  end
  
  local text_width = #countdown_text * 4
  print(countdown_text, 64 - text_width / 2, 60, 7)
  -- printh("ui.draw_countdown_screen finished.") -- DEBUG -- Temporarily commented out
end

function ui.draw_panic_screen() -- New function for drawing "Panic!"
  -- printh("ui.draw_panic_screen called. panic_display_timer: " .. tostr(panic_display_timer)) -- DEBUG -- Temporarily commented out
  cls(0) -- Clear screen
  -- Optionally, draw playfield elements here too if they should be visible
  if type(ui.draw_playfield_background) == "function" then ui.draw_playfield_background() end
  if type(ui.draw_game_hud) == "function" then ui.draw_game_hud() end -- Changed from draw_player_huds
  if type(cursors) == "table" and type(cursors.draw_all) == "function" then cursors.draw_all() end -- Changed from ui.draw_cursors
  if type(pieces) == "table" and type(pieces.draw_all) == "function" then pieces.draw_all() end -- Changed from ui.draw_pieces

  local text = "Panic!"
  local text_width = #text * 4
  local x = 64 - text_width / 2
  local y = 60

  -- Simple screen shake effect
  if panic_display_timer > 0 then
    local shake_intensity = 2
    x += flr(rnd(shake_intensity * 2 + 1)) - shake_intensity
    y += flr(rnd(shake_intensity * 2 + 1)) - shake_intensity
  end

  print(text, x, y, 8) -- Use a different color, e.g., red (8)
end
-->8
--cursor
local default_cursor_props={
  control_state=0,
  pending_type="defender",
  pending_orientation=0,
  color_select_idx=1,
  return_cooldown=0,
}
function create_cursor(player_id,initial_x,initial_y)
  local p_color=7
  local p_ghost_color=7
  if player_manager and player_manager.get_player then
    local player=player_manager.get_player(player_id)
    if player then
      if player.get_color then
        p_color=player:get_color()
      end
      if player.get_ghost_color then
        local ghost_color_val=player:get_ghost_color()
        if ghost_color_val then
          p_ghost_color=ghost_color_val
        end
      end
    end
  end
  local cur={
    id=player_id,
    x=initial_x,
    y=initial_y,
    spawn_x=initial_x,
    spawn_y=initial_y,
    control_state=default_cursor_props.control_state,
    pending_type=default_cursor_props.pending_type,
    pending_orientation=default_cursor_props.pending_orientation,
    pending_color=p_ghost_color,
    color_select_idx=default_cursor_props.color_select_idx,
    return_cooldown=default_cursor_props.return_cooldown,
    draw=function(self)
      local cursor_color
      if player_manager and player_manager.get_player then
        local p=player_manager.get_player(self.id)
        if p and p.get_color then
          cursor_color=p:get_color()
        end
      end
      if not cursor_color then
        cursor_color=self.pending_color
      end
      
      local cx,cy=self.x+4,self.y+4
      -- Draw X-shaped crosshair with 5-pixel size
      line(cx-2,cy-2,cx+2,cy+2,cursor_color)
      line(cx-2,cy+2,cx+2,cy-2,cursor_color)
      
      -- Show ghost piece only when applicable
      if self.pending_type=="attacker" or self.pending_type=="defender" then
        local ghost_piece_params={
          owner_id=self.id,
          type=self.pending_type,
          position={x=self.x+4,y=self.y+4},
          orientation=self.pending_orientation,
          color=self.pending_color,
          is_ghost=true
        }
        local ghost_piece=create_piece(ghost_piece_params)
        if ghost_piece and ghost_piece.draw then
          ghost_piece:draw()
        end
      end
    end
  }
  return cur
end
-->8
--main
if not N_PLAYERS then N_PLAYERS=2 end
if not table then table=table or{}end
local ui_handler
local game_start_time=0
local remaining_time_seconds=0
local game_winners={}
local game_max_score=-1
local processed_game_over=false
local controls_disabled=false
function _init()
  if player_manager==nil then 
    player_manager={}
  end
  if pieces==nil then pieces={}end
  if cursors==nil then cursors={}end
  if ui then
    ui_handler=ui
  else 
    ui_handler={
      draw_main_menu=function()print("NO UI - MAIN MENU",40,60,8)end,
      draw_game_hud=function()print("NO UI - GAME HUD",40,60,8)end,
      draw_how_to_play=function()print("NO UI - HOW TO PLAY",20,60,8)end,
      draw_winner_screen=function()cls(0)print("NO UI - WINNER SCREEN",20,60,8)end,
      update_main_menu_logic=function()end
    }
  end
  menuitem(1,false)
  menuitem(2,false)
  menuitem(3,false)
  menuitem(1,"Return to Main Menu",function()
    global_game_state="main_menu"
    _init_main_menu_state()
  end)
  menuitem(2,"finish game",function()
    if global_game_state=="in_game"then
      if player_manager and player_manager.init_players then
        player_manager.init_players(N_PLAYERS)
      end
      global_game_state="game_over"
      processed_game_over=false
    end
  end)
  
  if global_game_state=="main_menu"then
    _init_main_menu_state()
  else
    player_count=N_PLAYERS
    stash_count=STASH_SIZE
    init_game_properly()
  end
end
function start_countdown()
  global_game_state = "countdown"
  countdown_timer = 3 -- 3 seconds
  controls_disabled = true
end
function _calculate_and_store_winners()
  local current_max_score = -1
  local current_winners = {}
  if player_manager and player_manager.get_player and N_PLAYERS then
    for i=1, N_PLAYERS do
      local p = player_manager.get_player(i)
      if p and type(p.score) == "number" then
        if p.score > current_max_score then
          current_max_score = p.score
          current_winners = {p.id}
        elseif p.score == current_max_score then
          add(current_winners, p.id)
        end
      end
    end
  end
  game_winners = current_winners
  game_max_score = current_max_score
  local winners_str = ""
  for i, winner_id in ipairs(game_winners) do
    winners_str = winners_str .. winner_id
    if i < #game_winners then
      winners_str = winners_str .. ", "
    end
  end
end
function _update()
  if initiate_game_start_request then -- Check the flag
    initiate_game_start_request = false -- Reset the flag
    init_game_properly() -- Call the function that starts the countdown
    return -- Exit _update early as state is changing
  end
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.update_main_menu_logic then
      ui_handler.update_main_menu_logic()
    end
  elseif global_game_state == "how_to_play" then
    -- return to main menu on Z
    if btnp(4) then
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  elseif global_game_state == "countdown" then
    countdown_timer -= 2/60 -- Made countdown twice as fast
    if countdown_timer <= 0 then
      global_game_state = "panic_display"
      panic_display_timer = 1.5 -- Show "Panic!" for 1.5 seconds
      controls_disabled = true -- Keep controls disabled during panic display
    end
  elseif global_game_state == "panic_display" then -- Add this new state block
    panic_display_timer -= 1/60
    if panic_display_timer <= 0 then
      global_game_state = "in_game"
      controls_disabled = false
      game_start_time = time()
      if game_timer and type(game_timer) == "number" then
          remaining_time_seconds = game_timer * 60
      else
          remaining_time_seconds = 180 -- Default to 3 minutes if game_timer is problematic
      end
    end
  elseif global_game_state == "in_game" then
    if remaining_time_seconds > 0 then
      remaining_time_seconds -= 1/60 -- Pico-8 runs at 60 FPS for _update
      if remaining_time_seconds <= 0 then
        remaining_time_seconds = 0
        if update_game_state then
          update_game_state() -- Recalculate scores one last time
        end
        global_game_state = "game_over"
        processed_game_over = false -- Ensure winner calculation will run
      end
    else -- if remaining_time_seconds is already 0 or less
        if global_game_state == "in_game" then 
            global_game_state = "game_over"
            processed_game_over = false
        end
    end
    if not controls_disabled then
        if update_controls then -- Call the main controls update function
            update_controls()
        end
        if player_manager and player_manager.update_all_players then
             player_manager.update_all_players() -- This might update player state based on control input
        end
    end
  elseif global_game_state == "game_over" then
    if not processed_game_over then
      _calculate_and_store_winners()
      processed_game_over = true
    end
    if btnp(4) then -- Z (confirm)
      global_game_state = "main_menu"
      _init_main_menu_state()
    end
  end
end
function _draw()
  cls(0) 
  if global_game_state == "main_menu" then
    if ui_handler and ui_handler.draw_main_menu then
      ui_handler.draw_main_menu()
    end
  elseif global_game_state == "how_to_play" then
    if ui_handler and ui_handler.draw_how_to_play then
      ui_handler.draw_how_to_play()
    end
  elseif global_game_state == "countdown" then
    if ui_handler and ui_handler.draw_countdown_screen then
      ui_handler.draw_countdown_screen()
    else
      print("NO UI - COUNTDOWN", 40, 60, 8)
    end
  elseif global_game_state == "panic_display" then -- Add this block
    if ui_handler and ui_handler.draw_panic_screen then
      ui_handler.draw_panic_screen()
    else
      print("NO UI - PANIC DISPLAY", 40, 60, 8)
    end
  elseif global_game_state == "in_game" then
    -- draw game elements and HUD
    _draw_game_screen()   -- Draw timer, pieces, and cursors
    if ui_handler and ui_handler.draw_game_hud then
      ui_handler.draw_game_hud()
    end
  elseif global_game_state == "game_over" then
    if ui_handler and ui_handler.draw_winner_screen then
      ui_handler.draw_winner_screen() -- This function will use game_winners and game_max_score
    end
  end
end
function _init_main_menu_state()
  global_game_state = "main_menu"
  menu_option = 1 -- Default to first menu item
  -- Reset player/stash counts to current config or defaults
  if config and config.get_players_value then menu_player_count = config.get_players_value() else menu_player_count = N_PLAYERS end
  menu_stash_size = STASH_SIZE -- Assuming STASH_SIZE is the relevant config for menu
  if config and config.timer_options and config.current_timer_idx then game_timer = config.timer_options[config.current_timer_idx] else game_timer = 3 end -- Default game_timer
  pieces = {}
  cursors = {}
  if player_manager and player_manager.reset_all_players then
    player_manager.reset_all_players()
  end
  game_winners = {}
  game_max_score = -1
  processed_game_over = false
  controls_disabled = false -- Ensure controls are enabled in menu
end
_start_game = function()
  if not menu_player_count or menu_player_count < 1 then
    return
  end
  if not menu_stash_size or menu_stash_size < 1 then
    return
  end
  N_PLAYERS = menu_player_count
  STASH_SIZE = menu_stash_size
  global_game_state = "in_game"
  player_count = N_PLAYERS
  stash_count = STASH_SIZE
  if game_state_changed then
    game_state_changed(global_game_state)
  end
  init_game_properly() -- initialize players, cursors, pieces and start countdown
end
function init_game_properly()
  player_count = N_PLAYERS
  stash_count = STASH_SIZE
  if player_manager and player_manager.init_players then
    player_manager.init_players(N_PLAYERS)
  else
    return -- Exit if critical function is missing
  end
  pieces = {} -- Clear any existing pieces
  cursors = {} -- Clear existing cursors
  -- spawn cursors at default positions: near each corner
  local spawn_positions = {
    {x=8, y=8},
    {x=120-8, y=8},
    {x=8, y=120-8},
    {x=120-8, y=120-8}
  }
  for i = 1, N_PLAYERS do
    if create_cursor then
      local pos = spawn_positions[i] or {x=64, y=64}
      add(cursors, create_cursor(i, pos.x, pos.y))
    end
  end
  
  -- Initialize player stashes (if not already handled by init_players)
  for i=1, N_PLAYERS do
    local p = player_manager.get_player(i)
    if p and p.initialize_stash then 
      p.initialize_stash(STASH_SIZE) 
    end
  end
  start_countdown()
  processed_game_over = false
  game_winners = {} 
  game_max_score = -1
end
function _update_game_logic()
  if original_update_game_logic_func then
    original_update_game_logic_func() 
  end
  if original_update_controls_func then
    original_update_controls_func() 
  end
end
function _draw_game_screen()
  cls(0) 
  local minutes = flr(remaining_time_seconds / 60)
  local seconds = flr(remaining_time_seconds % 60)
  local seconds_str
  if seconds < 10 then
    seconds_str = "0" .. (""..seconds)
  else
    seconds_str = ""..seconds
  end
  local timer_str = (""..minutes) .. ":" .. seconds_str
  print(timer_str, 64 - #timer_str * 2, 5, 7) -- Top-center
  if pieces then
    for piece_obj in all(pieces) do
      if piece_obj and piece_obj.draw then
        piece_obj:draw()
      end
    end
  end
  if cursors then
    for _, cursor_obj in pairs(cursors) do
      if cursor_obj and cursor_obj.draw then
        cursor_obj:draw()
      end
    end
  end
  -- Removed fallback cursor drawing since we have the X-shape implementation
  if ui_handler and ui_handler.draw_game_hud then
    ui_handler.draw_game_hud()
  end
end

