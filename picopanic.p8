pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
--init
music_enabled=true
cursor_speed=2
rotation_speed=0.01
effects={attacker_placement=56,defender_placement=57,overcharge=58,capture=59,bad_placement=60,gameover_timer=61,switch_mode=57,enter_placement=49,exit_placement=50}
sprites={defender_successful={6,22,38,54,38,22},defender_unsuccessful={4,20,36,52,36,20},defender_overcharged={5,21,37,53,37,21}}

function finish_game_menuitem()
 if current_game_state==GAME_STATE_PLAYING then
  if score_pieces then score_pieces()end
  current_game_state=GAME_STATE_GAMEOVER
  GAME_TIMER=0
  gameover_timer=2
  sfx(effects.gameover_timer)
  gameover_music_fade_start=true
 end
end

gameover_timer=2
gameover_music_fade_start=false
pre_game_state=nil
pre_game_start_t=0
pre_game_sequence={"3...","2...","1..."}

function draw_centered_sequence(seq,start_t,color)
 local elapsed=time()-start_t
 local idx=flr(elapsed)+1
 if idx<=#seq then
  local s=seq[idx]
  print(s,64-(#s*2),64,color or 7)
  return false
 end
  return true
end

function draw_shaky_centered_text(s, color)
  local ox = rnd(3) - 1.5
  local oy = rnd(3) - 1.5
  print(s, 64 - (#s * 2) + ox, 64 + oy, color or 8)
end
function start_pre_game_sequence()
  pre_game_state = 'countdown'
  pre_game_start_t = time()
end

function update_pre_game_sequence()
  if pre_game_state == 'countdown' then
    local elapsed = time() - pre_game_start_t
    local countdown_duration = #pre_game_sequence
    if elapsed >= countdown_duration then
      pre_game_state = 'panic'
      pre_game_start_t = time()
    end
    return true
  elseif pre_game_state == 'panic' then
    if (time() - pre_game_start_t) >= 1 then
      pre_game_state = 'done'
      return false
    end
    return true
  elseif pre_game_state == 'done' or pre_game_state == nil then
    return false
  end
  return false
end

function draw_pre_game_text()
  if pre_game_state == 'countdown' then
    draw_centered_sequence(pre_game_sequence, pre_game_start_t, 7)
  elseif pre_game_state == 'panic' then
    draw_shaky_centered_text("panic!", 8)
  end
end

---@diagnostic disable: undefined-global

player_manager = {}
STASH_SIZE = 6
PLAYER_COUNT = 4
CPU_PLAYERS = 3
create_piece = nil
pieces = {}
LASER_LEN = 60
cursors = {}
CAPTURE_RADIUS_SQUARED = 64

original_update_game_logic_func = nil
original_update_controls_func = nil

-- Performance optimization variables
frame_skip_counter = 0
FRAME_SKIP_INTERVAL = 2

ROUND_TIME_MIN = 120
ROUND_TIME_MAX = 600
ROUND_TIME = 180
GAME_TIMER_MAX = ROUND_TIME
GAME_TIMER = GAME_TIMER_MAX

function point_in_polygon(px, py, vertices)
  local inside = false
  local n = #vertices
  for i = 1, n do
    local j = (i % n) + 1
    local xi, yi = vertices[i].x, vertices[i].y
    local xj, yj = vertices[j].x, vertices[j].y
    if ((yi > py) ~= (yj > py)) and (px < (xj - xi) * (py - yi) / ((yj - yi) + 0.0001) + xi) then
      inside = not inside
    end
  end
  return inside
end

local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

function ray_segment_intersect(ray_ox, ray_oy, ray_dx, ray_dy,
                               seg_x1, seg_y1, seg_x2, seg_y2)
  local s_dx = seg_x2 - seg_x1
  local s_dy = seg_y2 - seg_y1
  local r_s_cross = ray_dx * s_dy - ray_dy * s_dx
  if r_s_cross == 0 then return nil, nil, nil end
  
  local t2 = ((seg_x1 - ray_ox) * ray_dy - (seg_y1 - ray_oy) * ray_dx) / r_s_cross
  local t1 = ((seg_x1 - ray_ox) * s_dy - (seg_y1 - ray_oy) * s_dx) / r_s_cross
  
  if t1 >= 0 and t2 >= 0 and t2 <= 1 then
    return ray_ox + t1 * ray_dx, ray_oy + t1 * ray_dy, t1
  end
  return nil, nil, nil
end

function attempt_capture(player_obj, cursor)
  local player_id = player_obj.id
  for _, piece_obj in ipairs(pieces) do
    if piece_obj.owner_id == player_id and piece_obj.state == "overcharged" then
      if piece_obj.targeting_attackers then
        for attacker_idx = #piece_obj.targeting_attackers, 1, -1 do
          local attacker_to_capture = piece_obj.targeting_attackers[attacker_idx]
          if attacker_to_capture then
            local dist_x = (cursor.x + 4) - attacker_to_capture.position.x
            local dist_y = (cursor.y + 4) - attacker_to_capture.position.y
            
            if (dist_x*dist_x + dist_y*dist_y) < CAPTURE_RADIUS_SQUARED then
              local captured_color = attacker_to_capture:get_color()
              if del(pieces, attacker_to_capture) then
                player_obj:add_captured_piece(captured_color)
                if effects and effects.capture then
                  sfx(effects.capture)
                end
                deli(piece_obj.targeting_attackers, attacker_idx)
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

function init_cursors(num_players)
  -- Score/stash display box size and offset for kitty-corner spawn
  local score_box_size = 24 -- 2x3 tiles = 16x24 px
  local spawn_offset = 6    -- distance from the box, diagonally
  local all_possible_spawn_points = {
    -- Player 1: top left, spawn down+right from UI box
    {x = 16 + 2, y = 24 + 2},
    -- Player 2: top right, spawn down+left from UI box
    {x = 128 - 16 - 2 - 8, y = 24 + 2},
    -- Player 3: bottom left, spawn up+right from UI box
    {x = 16 + 2, y = 128 - 24 - 2 - 8},
    -- Player 4: bottom right, spawn up+left from UI box
    {x = 128 - 16 - 2 - 8, y = 128 - 24 - 2 - 8}
  }

  cursors = {}

  for i = 1, num_players do
    local sp
    if i <= #all_possible_spawn_points then
      sp = all_possible_spawn_points[i]
    else
      sp = {x = 4 + (i-1)*10, y = 4}
    end

    if create_cursor then
      cursors[i] = create_cursor(i, sp.x, sp.y)
    else        cursors[i] = {
          id = i,
          x = sp.x,
          y = sp.y,
          spawn_x = sp.x,
          spawn_y = sp.y,
          control_state = 0,
          pending_type = "defender",
          pending_color = 7,
          pending_orientation = 0,
          return_cooldown = 0,
          color_select_idx = 1,
          draw = function()
          end
        }
    end
  end
end

GAME_STATE_MENU = 0
GAME_STATE_PLAYING = 1
GAME_STATE_GAMEOVER = 2
GAME_STATE_TUTORIAL = 3 -- New game state

current_game_state = GAME_STATE_MENU

tutorial_page_current = 1
tutorial_pages_data = {}

function init_tutorial_data()
  tutorial_pages_data = {}
  add(tutorial_pages_data, {
    lines = {"TUTORIAL: PAGE 1", "welcome to pico panic!", "PLACE DEFENDERS (SQUARES)", "AND ATTACKERS (TRIANGLES)."},
    pieces = {
      {type="defender", x=30, y=80, orientation=0, color=12},
      {type="attacker", x=98, y=80, orientation=0.25, color=8}
    }
  })
  add(tutorial_pages_data, {
    lines = {"TUTORIAL: PAGE 2", "ATTACKERS SHOOT LASERS.", "DEFENDERS SCORE IF NOT HIT,", "OR HIT BY ONLY ONE LASER."},
    pieces = {
      {type="attacker", x=20, y=70, orientation=0, color=10},
      {type="defender", x=40, y=70, orientation=0, color=12},
      {type="defender", x=80, y=70, orientation=0, color=14, state="hit"},
      {type="attacker", x=100, y=70, orientation=0.5, color=9},
      {type="attacker", x=80, y=90, orientation=0.25, color=11}
    }
  })
  add(tutorial_pages_data, {
    lines = {"TUTORIAL: PAGE 3", "OVERCHARGED DEFENDERS", "(HIT BY 3+ LASERS)", "CAN CAPTURE ENEMY ATTACKERS."},
    pieces = {
      {type="defender", x=64, y=70, orientation=0, color=11, state="overcharged"},
      {type="attacker", x=108, y=70, orientation=0.5, color=9},
      {type="attacker", x=90, y=90, orientation=0.4, color=10},
      {type="attacker", x=40, y=70, orientation=2, color=8}
    }
  })
  add(tutorial_pages_data, {
    lines = {"TUTORIAL: PAGE 4", "use your prisoners", "to block enemy attacks!"},
    pieces = {
      {type="defender", x=64, y=70, orientation=0, color=11, state="overcharged"},
      {type="attacker", x=108, y=70, orientation=0.5, color=9},
      {type="attacker", x=90, y=90, orientation=0.4, color=10},
      {type="defender", x=80, y=70, orientation=2, color=8}
    }
  })
  add(tutorial_pages_data, {
    lines = {"TUTORIAL: PAGE 5", "CONTROLS:", "x: PLACE PIECE", "o: switch mode","udlr: MOVE CURSOR", "while placing", "lr rotate", "ud select piece", "MOST POINTS WINS. GOOD LUCK!"},
    pieces = {}
  })
end

function setup_tutorial_page(page)
  -- Clear all pieces
  pieces = {}
  -- Place real pieces for this page
  if page.pieces then
    for _, def in ipairs(page.pieces) do
      local params = {}
      for k,v in pairs(def) do params[k]=v end
      -- Map x/y to position if needed by create_piece
      params.position = {x=params.x, y=params.y}
      params.x = nil params.y = nil
      local obj = create_piece(params)
      if obj then add(pieces, obj) end
    end
  end
  -- Run normal scoring/laser logic
  if score_pieces then score_pieces() end
end

function internal_update_game_logic()
  for _, p_item in ipairs(pieces) do
    if p_item.type == "defender" then
      p_item.hits = 0
      p_item.targeting_attackers = {}
      p_item.captured_flag = false
    end
  end
  
  if score_pieces then 
    score_pieces() 
  else 
  end
end

function go_to_state(new_state)
  -- reset gameover music fade when leaving gameover state
  if current_game_state == GAME_STATE_GAMEOVER and new_state != GAME_STATE_GAMEOVER then
    gameover_music_fade_start = false
  end
  
  if new_state == GAME_STATE_PLAYING and current_game_state ~= GAME_STATE_PLAYING then
    -- Reset pyramid rotation when starting new game
    pyramid_rotation_x = 0
pyramid_rotation_y = 0
pyramid_rotation_z = 0
    -- start music for play mode (track 0 by default)
    if music_enabled then
      music(0,0.5)
    else
      music(-1)
    end
    local current_game_stash_size = STASH_SIZE

    pieces = {}
    
    player_manager.init_players(PLAYER_COUNT)
    
    init_cursors(player_manager.get_player_count())
    start_pre_game_sequence()
    GAME_TIMER_MAX = ROUND_TIME
    GAME_TIMER = GAME_TIMER_MAX
    
    for i=1, player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p then 
        p.score = 0
        p.stash = {} 
        p.stash[p:get_color()] = current_game_stash_size 
      end
    end
    if original_update_game_logic_func then original_update_game_logic_func() end
  elseif new_state == GAME_STATE_TUTORIAL then
    init_tutorial_data() -- Initialize tutorial content
    tutorial_page_current = 1
    setup_tutorial_page(tutorial_pages_data[1])
  end
  current_game_state = new_state
end


function _init()
  menuitem(1, "Finish Game", finish_game_menuitem)
  if not player_manager then
  end
  
  if internal_update_game_logic then
    original_update_game_logic_func = internal_update_game_logic
  else
    original_update_game_logic_func = function() end
  end
  
  if update_controls then
    original_update_controls_func = update_controls
  else
    original_update_controls_func = function() end
  end
  
  menu_selection = 1
  
  current_game_state = GAME_STATE_MENU
  -- init_starfield() -- Initialize stars once
  init_tutorial_data() -- Initialize tutorial data once at start
end



function update_menu_state()
 if not menu_selection then menu_selection=1 end
 if btnp(⬆️)then menu_selection=max(1,menu_selection-1)
 elseif btnp(⬇️)then menu_selection=min(6,menu_selection+1)end
 if menu_selection==1 then
  if btnp(⬅️)then STASH_SIZE=max(3,STASH_SIZE-1)
  elseif btnp(➡️)then STASH_SIZE=min(10,STASH_SIZE+1)end
 elseif menu_selection==2 then
  if btnp(⬅️)then PLAYER_COUNT=max(1,PLAYER_COUNT-1) CPU_PLAYERS=min(CPU_PLAYERS,PLAYER_COUNT)
  elseif btnp(➡️)then PLAYER_COUNT=min(4,PLAYER_COUNT+1)end
 elseif menu_selection==3 then
  if btnp(⬅️)then CPU_PLAYERS=max(0,CPU_PLAYERS-1)
  elseif btnp(➡️)then CPU_PLAYERS=min(PLAYER_COUNT,CPU_PLAYERS+1)end
 elseif menu_selection==4 then
  if btnp(⬅️)then ROUND_TIME=max(ROUND_TIME_MIN,ROUND_TIME-30)
  elseif btnp(➡️)then ROUND_TIME=min(ROUND_TIME_MAX,ROUND_TIME+30)end
 elseif menu_selection==5 then
  if btnp(⬅️)or btnp(➡️)then
   music_enabled=not music_enabled
   if not music_enabled then music(-1)
   else if current_game_state==GAME_STATE_PLAYING then music(0,0.5)end end
  end
 end
 if btnp(❎)or btnp(🅾️)then
  if menu_selection==6 then go_to_state(GAME_STATE_TUTORIAL)
  else go_to_state(GAME_STATE_PLAYING)end
 end
end


function update_playing_state()
  local pre_game_active = update_pre_game_sequence()

  if pre_game_state ~= 'countdown' then
    if original_update_controls_func then 
      original_update_controls_func() 
    end

    -- Update CPU players normally 
    update_cpu_players()

    if original_update_game_logic_func then
      if type(original_update_game_logic_func) == "function" then
        original_update_game_logic_func()
      end
    end
  end

  if not pre_game_active then
    GAME_TIMER = max(0, GAME_TIMER - (1/30))
  end

  if GAME_TIMER <= 0 and current_game_state == GAME_STATE_PLAYING and not pre_game_active then
    if score_pieces then score_pieces() end
    current_game_state = GAME_STATE_GAMEOVER
    GAME_TIMER = 0
    gameover_timer = 2
    -- play gameover sound and start music fade
    sfx(effects.gameover_timer)
    gameover_music_fade_start = true
  end
end


function _update()
  if current_game_state == GAME_STATE_MENU then
    update_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    update_playing_state()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    update_gameover_state()
  elseif current_game_state == GAME_STATE_TUTORIAL then -- New state update
    update_tutorial_state()
  end
  -- update_starfield() -- Update starfield regardless of game state
end

function update_tutorial_state()
  if btnp(❎) then
    tutorial_page_current += 1
    if tutorial_page_current > #tutorial_pages_data then
      tutorial_page_current = 1 -- Loop back to first page
    end
    setup_tutorial_page(tutorial_pages_data[tutorial_page_current])
  elseif btnp(🅾️) then
    go_to_state(GAME_STATE_MENU)
  end
end

function update_gameover_state()
  if gameover_timer and gameover_timer > 0 then
    gameover_timer = max(0, gameover_timer - (1/30))
    
    -- fade out music during gameover timer
    if gameover_music_fade_start and music_enabled then
      local fade_progress = 1 - (gameover_timer / 2) -- fade from 1 to 0 over 2 seconds
      local volume = max(0, 0.5 * fade_progress) -- start from 0.5 volume and fade to 0
      if volume <= 0.01 then -- use a small threshold instead of exactly 0
        music(-1) -- stop music completely when volume is very low
        gameover_music_fade_start = false
      else
        music(0, volume) -- adjust music volume
      end
    end
    
    return
  end
  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_MENU)
  end
end


stars = {}

function init_starfield()
  stars = {}
  for i = 1, 20 do
    add(stars, {
      x = rnd(128),
      y = rnd(128),
      speed = rnd(0.01) + 0.1,
      size = flr(rnd(2)) + 1,
      color = flr(rnd(3)) + 5
    })
  end
end

function draw_menu_state_elements()
 print("pico panic",32,20,7)
 print("a game from the arcades",18,32,7) 

 if not menu_selection then menu_selection=1 end
 local c1,c2,c3,c4,c5,c6=11,11,11,11,11,11
 if menu_selection==1 then c1=7
 elseif menu_selection==2 then c2=7
 elseif menu_selection==3 then c3=7
 elseif menu_selection==4 then c4=7
 elseif menu_selection==5 then c5=7
 elseif menu_selection==6 then c6=7 end
 print("STASH SIZE: "..STASH_SIZE,28,70,c1)
 print("PLAYERS: "..PLAYER_COUNT,28,80,c2)
 print("CPU PLAYERS: "..CPU_PLAYERS,28,90,c3)
 local m,s=flr(ROUND_TIME/60),ROUND_TIME%60
 print("ROUND TIME: "..m..":"..(s<10 and"0"or"")..s,28,100,c4)
 print("MUSIC: "..(music_enabled and"ON"or"OFF"),28,110,c5)
 print("HOW TO PLAY",28,120,c6)
end

function draw_playing_state_elements()
  if pre_game_state == 'countdown' or pre_game_state == 'panic' then
    draw_pre_game_text()
    for _,c in ipairs(cursors) do if c.draw then c:draw() end end
    if pre_game_state == 'countdown' then
      return
    end
  end

  if pre_game_state == 'done' or pre_game_state == 'panic' or pre_game_state == nil then
    local secs = flr(GAME_TIMER)
    local timer_str = flr(secs/60) .. ":" .. (secs%60 < 10 and "0" or "") .. (secs%60)
    print(timer_str, 62 - #timer_str*2, 2, GAME_TIMER < 30 and 8 or 7)
    for _,o in ipairs(pieces) do if o.draw then o:draw() end end
    for _,c in ipairs(cursors) do if c.draw then c:draw() end end

    -- UI display constants for player info boxes
    local FONT_WIDTH = 4 -- Standard Pico-8 font width per char
    local FONT_HEIGHT = 5 -- Standard Pico-8 font character height
    local UI_BOX_SIZE = 24 -- Each player UI box is 16x24 pixels (2x3 tiles)
 for i=1,player_manager.get_player_count()do
  local p,c=player_manager.get_player(i),cursors[i]
  if p then
   local s,m=tostr(p.score),c and(c.pending_type=="attacker"and"A"or c.pending_type=="defender"and"D"or c.pending_type=="capture"and"C")or"?"
   local sm=s.." "..m
   local ax,ay=(i==2 or i==4)and 112 or 0,(i>=3)and 104 or 0
   local tx=(i==1 or i==3)and ax+2 or ax+14-#sm*4
   print(sm,tx,ay+2,p.color)
   local by,bh=ay+9,13
   for j=1,4 do
    local col,cnt=player_manager.colors[j],p.stash[player_manager.colors[j]]or 0
    local h=flr(cnt/STASH_SIZE*bh)
    if h>0 then
     local bx=((i==1 or i==3)and ax+1 or ax+11)+(j-1)*3
     local y1,y2=(i<=2)and by or by+bh-h,(i<=2)and by+h-1 or by+bh-1
     rectfill(bx,y1,bx+1,y2,col)
    end
   end
  end
 end
end
end


function draw_gameover_state()
  cls(0)
  
  if gameover_timer and gameover_timer > 0 then
    -- During timer: draw everything normally with "FINISH!" message
    map(0, 0, 0, 0, 16, 16)
    
    -- Draw pieces at their normal positions
    for _,o in ipairs(pieces) do 
      if o.draw then 
        o:draw() 
      end 
    end
    
    -- Draw cursors at their normal positions  
    for _,c in ipairs(cursors) do 
      if c and c.draw then 
        c:draw() 
      end 
    end
    
    -- Draw "FINISH!" over the timer area
    print("FINISH!", 52, 2, 7)
  else
    -- After timer: create a clean background for gameover screen with 3D pyramid
    cls(0) -- Clean black background
    rectfill(0, 0, 127, 15, 0) -- Clear top area for scores
    
    -- Don't draw pieces or cursors - clean gameover screen
    
    -- Find winning player and draw 3D pyramid
    local winning_player = nil
    local highest_score = -1
    for i = 1, player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p and p:get_score() > highest_score then
        highest_score = p:get_score()
        winning_player = p
      end
    end
    
    if winning_player then
      draw_3d_pyramid(64, 30, winning_player:get_color()) -- Center in top 2/3 of screen
      
      -- Add big winner chyron at bottom
      local winner_id = nil
      for i = 1, player_manager.get_player_count() do
        local p = player_manager.get_player(i)
        if p == winning_player then
          winner_id = i
          break
        end
      end
      
      if winner_id then
        local win_text = "PLAYER " .. winner_id .. " WINS!"
        local text_width = #win_text * 4 -- each char is 4 pixels wide
        local x_pos = 64 - (text_width / 2) -- center horizontally
        
        -- Draw shadow/outline for better visibility
        print(win_text, x_pos + 1, 113, 0) -- black shadow
        print(win_text, x_pos - 1, 113, 0) -- black shadow
        print(win_text, x_pos, 114, 0) -- black shadow
        print(win_text, x_pos, 112, 0) -- black shadow
        
        -- Draw main text in winner's color
        print(win_text, x_pos, 113, winning_player:get_color())
      end
    end
    
    -- Draw scores in the top area (0-16 pixels) when map is repositioned
    local sorted_players = {}
    for i = 1, player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p then
        add(sorted_players, {player = p, id = i})
      end
    end
    for i = 1, #sorted_players - 1 do
      for j = i + 1, #sorted_players do
        if sorted_players[j].player:get_score() > sorted_players[i].player:get_score() then
          local temp = sorted_players[i]
          sorted_players[i] = sorted_players[j]
          sorted_players[j] = temp
        end
      end
    end
    for i = 1, #sorted_players do
      local p = sorted_players[i].player
      local pid = sorted_players[i].id
      local cur = cursors[pid]
      local mode_letter = "?"
      if cur and cur.pending_type then
        if cur.pending_type == "attacker" then mode_letter = "A"
        elseif cur.pending_type == "defender" then mode_letter = "D"
        elseif cur.pending_type == "capture" then mode_letter = "C"
        end
      end
      local score_text = "P" .. pid .. ": " .. p:get_score() .. " " .. mode_letter
      print(score_text, 64 - #score_text * 2, 2 + i * 6, p:get_color()) -- Compact spacing in top area
    end
    print("Press X or O to return", 28, 120, 6)
  end
end

function draw_tutorial_state()
  cls(0)
  map(0, 0, 0, 0, 16, 16)

  -- Draw real pieces
  for _,o in ipairs(pieces) do if o.draw then o:draw() end end

  -- Draw text for the current tutorial page
  local page_data = tutorial_pages_data[tutorial_page_current]
  if page_data and page_data.lines then
    local start_y = 20
    for i, line_text in ipairs(page_data.lines) do
      print(line_text, 64 - (#line_text * 2), start_y + (i-1)*8, 7)
    end
  end

  -- Navigation hints
  print("❎:NEXT PAGE", 4, 118, 7)
  print("🅾️:MENU", 88, 118, 7)
end

-- 3D pyramid variables
pyramid_rotation_x = 0
pyramid_rotation_y = 0
pyramid_rotation_z = 0

function draw_3d_pyramid(cx, cy, color)
  pyramid_rotation_x += 0.005
  pyramid_rotation_y += 0.008
  pyramid_rotation_z += 0.003
  
  local size,height = 30,25
  local vertices = {
    {-size, 0, -size}, {size, 0, -size}, {size, 0, size}, {-size, 0, size}, {0, -height, 0}
  }
  
  local cx_cos,sx_sin,cy_cos,sy_sin,cz_cos,sz_sin = cos(pyramid_rotation_x),sin(pyramid_rotation_x),cos(pyramid_rotation_y),sin(pyramid_rotation_y),cos(pyramid_rotation_z),sin(pyramid_rotation_z)
  
  local projected = {}
  for i, v in ipairs(vertices) do
    local x,y,z = v[1],v[2],v[3]
    
    -- Combined rotation
    local y1,z1 = y * cx_cos - z * sx_sin, y * sx_sin + z * cx_cos
    local x2,z2 = x * cy_cos + z1 * sy_sin, -x * sy_sin + z1 * cy_cos
    local x3,y3 = x2 * cz_cos - y1 * sz_sin, x2 * sz_sin + y1 * cz_cos
    
    -- Projection
    local scale = 100 / (100 + z2)
    projected[i] = {x = cx + x3 * scale, y = cy + y3 * scale + 20}
  end
  
  -- Draw pyramid
  for i=1,4 do
    local j = i%4+1
    line(projected[i].x, projected[i].y, projected[j].x, projected[j].y, color)
    line(projected[i].x, projected[i].y, projected[5].x, projected[5].y, color)
  end
end

function _draw()
  cls(0)
  -- draw_starfield() -- Assuming draw_starfield is defined elsewhere
  
  if current_game_state == GAME_STATE_MENU then
    map(0, 0, 0, 0, 16, 16)
    draw_menu_state_elements()
  elseif current_game_state == GAME_STATE_PLAYING then
    map(0, 0, 0, 0, 16, 16)
    draw_playing_state_elements()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    draw_gameover_state() -- This function handles its own map drawing
  elseif current_game_state == GAME_STATE_TUTORIAL then -- New state draw
    draw_tutorial_state() -- This function handles its own map drawing
  end
end
-->8
--player
local Player={}Player.__index=Player
local colors={12,8,11,10}
local ghost_colors={1,9,3,4}
function Player:new(id,s,c,gc,cpu)
 local bd = cpu and (120 + rnd(60)) or 0
 local i={id=id,score=s or 0,color=c,ghost_color=gc,stash={},capture_mode=false,is_cpu=cpu or false,cpu_timer=rnd(bd),cpu_action_delay=bd}
 i.stash[c]=STASH_SIZE or 6
 setmetatable(i,self)return i
end
function Player:get_score()return self.score end
function Player:add_score(p)self.score+=p or 1 end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:is_in_capture_mode()return self.capture_mode end
function Player:toggle_capture_mode()self.capture_mode=not self.capture_mode end
function Player:add_captured_piece(pc)
 self.stash[pc]=(self.stash[pc]or 0)+1
end
function Player:get_captured_count(pc)return self.stash[pc]or 0 end
function Player:has_piece_in_stash(pc)return(self.stash[pc]or 0)>0 end
function Player:use_piece_from_stash(pc)
 if self:has_piece_in_stash(pc)then self.stash[pc]-=1 return true end
 return false
end
player_manager.colors,player_manager.ghost_colors=colors,ghost_colors
player_manager.max_players,player_manager.current_players=4,{}
function player_manager.init_players(np)
 if np<1 or np>4 then return end
 player_manager.current_players={}
 for i=1,np do
  local c,gc=colors[i]or 7,ghost_colors[i]or 1
  local cpu=(i>np-CPU_PLAYERS)
  player_manager.current_players[i]=Player:new(i,0,c,gc,cpu)
 end
end
function player_manager.get_player(pid)return player_manager.current_players[pid]end
function player_manager.get_player_color(pid)
 local p=player_manager.current_players[pid]
 return p and p.color or 7
end
function player_manager.get_player_ghost_color(pid)
 local p=player_manager.current_players[pid]
 return p and p.ghost_color or 1
end
function player_manager.get_player_count()return #player_manager.current_players end
-->8
--scoring
function reset_player_scores()
 if player_manager and player_manager.current_players then
  for _,p in ipairs(player_manager.current_players)do
   if p then p.score=0 end
  end
 end
end

function reset_piece_states_for_scoring()
 for _,p in ipairs(pieces)do
  if p then
   p.hits=0
   p.targeting_attackers={}
   p.dbg_target_count=nil
   if p.type=="defender"then p.state="successful"end
  end
 end
end

function _check_attacker_hit_piece(a,t,pm,rsif,cll,af)
 local av=a:get_draw_vertices()
 if not av or #av==0 then return end
 local apex=av[1]
 local dx,dy=cos(a.orientation),sin(a.orientation)

  local target_corners = t:get_draw_vertices()
  if not target_corners or #target_corners == 0 then return end

  for j = 1, #target_corners do
    local k = (j % #target_corners) + 1
    local ix, iy, hit_t = rsif(apex.x, apex.y, dx, dy,
                                                 target_corners[j].x, target_corners[j].y,
                                                 target_corners[k].x, target_corners[k].y)
    if hit_t and hit_t >= 0 and hit_t <= cll then
      t.hits = (t.hits or 0) + 1
      t.targeting_attackers = t.targeting_attackers or {}
      af(t.targeting_attackers, a)

      local attacker_player = pm.get_player(a.owner_id)
      local target_player = pm.get_player(t.owner_id)

      if attacker_player and target_player and a.owner_id ~= t.owner_id then
        attacker_player:add_score(1)
      end

      if t.type == "defender" then
        if t.hits >= 3 then
          t.state = "overcharged"
        elseif t.hits == 2 then
          t.state = "unsuccessful"
        elseif t.hits == 1 then
          t.state = "successful"
        end
      end
      return true
    end
  end
  return false
end

function _score_defender(p_obj, player_manager_param)
  if p_obj and p_obj.type == "defender" then
    local num_total_attackers_targeting = 0
    if p_obj.targeting_attackers then
      num_total_attackers_targeting = #p_obj.targeting_attackers
    end

    if num_total_attackers_targeting <= 1 then
      local defender_player = player_manager_param.get_player(p_obj.owner_id)
      if defender_player then
        defender_player:add_score(1)
      end
    end
  end
end

function score_pieces()
  local pm,rsif,ll,a=player_manager,ray_segment_intersect,LASER_LEN,add
  reset_player_scores()
  reset_piece_states_for_scoring()

  -- Pre-calculate all vertices once
  local piece_vertices = {}
  for i, piece in ipairs(pieces) do
    piece_vertices[i] = piece:get_draw_vertices()
  end

  -- Check all pieces for accurate hit detection (no spatial culling)
  for i, attacker_obj in ipairs(pieces) do
    if attacker_obj.type == "attacker" then
      local av = piece_vertices[i]
      if av and #av > 0 then
        local apex,dx,dy=av[1],cos(attacker_obj.orientation),sin(attacker_obj.orientation)
        local closest_t,closest_piece=ll,nil
        
        -- Check all pieces to ensure accurate hit detection
        for j, target_obj in ipairs(pieces) do
          if target_obj ~= attacker_obj then
            local tc = piece_vertices[j]
            if tc and #tc > 0 then
              for k = 1, #tc do
                local l = (k % #tc) + 1
                local ix, iy, t = rsif(apex.x, apex.y, dx, dy, tc[k].x, tc[k].y, tc[l].x, tc[l].y)
                if t and t >= 0 and t < closest_t then
                  closest_t,closest_piece = t,target_obj
                end
              end
            end
          end
        end
        if closest_piece then
          _check_attacker_hit_piece(attacker_obj, closest_piece, pm, rsif, ll, a)
        end
      end
    end
  end

  for _, p_obj in ipairs(pieces) do
    _score_defender(p_obj, pm)
    if p_obj.type == "defender" then
      local h=p_obj.hits
      p_obj.state = h >= 3 and "overcharged" or h == 2 and "unsuccessful" or "successful"
    end
  end

  local rp={}
  for _,p_obj in ipairs(pieces) do
    if not p_obj.captured_flag then a(rp, p_obj) end
  end
  pieces = rp
end
-->8
--piece
Piece={}Piece.__index=Piece
Attacker={}Attacker.__index=Attacker setmetatable(Attacker,{__index=Piece})
Defender={}Defender.__index=Defender setmetatable(Defender,{__index=Piece})
local cos,sin,max,min,sqrt,abs=cos,sin,max,min,sqrt,abs

function Piece:new(o)
 o=o or{}
 o.position=o.position or{x=64,y=64}
 o.orientation=o.orientation or 0
 o._cached_vertices=nil
 o._cached_pos_x=nil
 o._cached_pos_y=nil
 o._cached_orientation=nil
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
 -- Check if cache is valid
 if self._cached_vertices and 
    self._cached_pos_x==self.position.x and 
    self._cached_pos_y==self.position.y and 
    self._cached_orientation==self.orientation then
  return self._cached_vertices
 end
 
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
 
 -- Cache the result
 self._cached_vertices=wc
 self._cached_pos_x=cx
 self._cached_pos_y=cy
 self._cached_orientation=o
 
 return wc
end

function Piece:invalidate_cache()
 self._cached_vertices=nil
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
 local v=self:get_draw_vertices()
 if not v or #v==0 then return end
 local dx,dy,lc=cos(self.orientation),sin(self.orientation),self:get_color()
 local ht,hx,hy=200,v[1].x+dx*200,v[1].y+dy*200
 
 -- Check all pieces for laser intersection (no distance culling for accuracy)
 if pieces then
  for _,p in ipairs(pieces)do
   if p~=self then
    local pc=p:get_draw_vertices()
    for j=1,#pc do
     local k=(j%#pc)+1
     local ix,iy,t=ray_segment_intersect(v[1].x,v[1].y,dx,dy,pc[j].x,pc[j].y,pc[k].x,pc[k].y)
     if t and t>=0 and t<ht then 
      ht,hx,hy=t,ix,iy
      lc=p.state=="unsuccessful"and 8 or p.state=="overcharged"and 10 or lc
     end
    end
   end
  end
 end
 
 -- Optimize laser drawing with fewer segments (keep this optimization)
 local ns=flr(ht/4) -- Reduced detail from /3 to /4
 for i=0,ns-1 do
  local st=i*4
  local et=st+2  -- Longer segments
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

-- Add helper function to update piece position and invalidate cache
function Piece:set_position(x, y)
 self.position.x = x
 self.position.y = y
 self:invalidate_cache()
end

function Piece:set_orientation(orientation)
 self.orientation = orientation
 self:invalidate_cache()
end
-->8
--#globals effects sfx create_piece add pieces score_pieces ray_segment_intersect LASER_LEN
function legal_placement(piece_params)
 local uz={{0,0,15,23},{112,0,127,23},{0,104,15,127},{112,104,127,127}}
 local tp=create_piece(piece_params)
 if not tp then return false end
 
 local cs=tp:get_draw_vertices()
 if not cs or #cs==0 then return false end
 
 -- Quick bounds check first
 local min_x, max_x, min_y, max_y = 128, 0, 128, 0
 for c in all(cs)do
  min_x, max_x = min(min_x, c.x), max(max_x, c.x)
  min_y, max_y = min(min_y, c.y), max(max_y, c.y)
  if c.x<0 or c.x>128 or c.y<0 or c.y>128 then return false end
  for z in all(uz)do if c.x>=z[1] and c.x<=z[3] and c.y>=z[2] and c.y<=z[4] then return false end end
 end
 
 -- Spatial optimization: only check nearby pieces
 for _,ep in ipairs(pieces)do
  -- Quick distance check first
  local dist_sq = (ep.position.x - piece_params.position.x)^2 + (ep.position.y - piece_params.position.y)^2
  if dist_sq < 400 then -- Only check pieces within 20 pixels
   local ec=ep:get_draw_vertices()
   if ec and #ec>0 then
    local mn2,mx2,my3,my4=128,0,128,0
    for c in all(ec)do mn2,mx2,my3,my4=min(mn2,c.x),max(mx2,c.x),min(my3,c.y),max(my4,c.y)end
    if not(max_x<mn2 or mx2<min_x or max_y<my3 or my4<min_y)then return false end
   end
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
      if t and t>=0 and t<=LASER_LEN then return true end
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
-->8
--controls
local CSTATE_MOVE_SELECT,CSTATE_ROTATE_PLACE,CSTATE_COOLDOWN=0,1,2

function update_controls()
 for i,cur in ipairs(cursors)do
  local p=player_manager.get_player(i)
  if not p or p.is_cpu then goto next_cursor_ctrl end
  
  local es=true
  if p and p.stash then
   for _,cnt in pairs(p.stash)do if cnt>0 then es=false break end end
  end
  local hd=false
  if pieces then
   for _,po in pairs(pieces)do
    if po.owner_id==i and po.type=="defender"and po.state=="successful"then hd=true break end
   end
  end
  local fa="normal"
  if es then
   cur.pending_type="capture"
   fa="capture_only"
  elseif not hd then
   cur.pending_type="defender"
   cur.pending_color=p:get_color()
   fa="must_place_defender"
  end
  if cur.control_state==0 and btnp(🅾️,i-1)and fa=="normal"then
   cur.pending_type=cur.pending_type=="defender"and"attacker"or cur.pending_type=="attacker"and"capture"or"defender"
   cur.pending_orientation = 0
   if effects and effects.switch_mode then sfx(effects.switch_mode)end
  end

  p.capture_mode = (cur.pending_type == "capture")

  if cur.control_state == 0 then
   local spd=cursor_speed
   if btn(⬅️,i-1)then cur.x=max(0,cur.x-spd)
   elseif btnp(⬅️,i-1)then cur.x=max(0,cur.x-1)end
   if btn(➡️,i-1)then cur.x=min(cur.x+spd,120)
   elseif btnp(➡️,i-1)then cur.x=min(cur.x+1,120)end
   if btn(⬆️,i-1)then cur.y=max(0,cur.y-spd)
   elseif btnp(⬆️,i-1)then cur.y=max(0,cur.y-1)end
   if btn(⬇️,i-1)then cur.y=min(cur.y+spd,120)
   elseif btnp(⬇️,i-1)then cur.y=min(cur.y+1,120)end

   if btnp(❎,i-1)then
    if cur.pending_type=="capture"then
     if attempt_capture(p,cur)then
      cur.control_state,cur.return_cooldown=2,6
      if original_update_game_logic_func then original_update_game_logic_func()end
     end
    else
     cur.control_state=1
     if effects and effects.enter_placement then sfx(effects.enter_placement)end
    end
   end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if fa == "must_place_defender" then
        add(available_colors, p:get_color())
        cur.color_select_idx = 1
      else
        if p and p.stash then
          for color, count in pairs(p.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      if #available_colors == 0 and p and p:has_piece_in_stash(p:get_color()) then
         add(available_colors, p:get_color())
      elseif #available_colors == 0 then
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl
      end

      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      if fa ~= "must_place_defender" then
        if btnp(⬆️, i - 1) then
          cur.color_select_idx = cur.color_select_idx - 1
          if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end
        elseif btnp(⬇️, i - 1) then
          cur.color_select_idx = cur.color_select_idx + 1
          if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
        end
      end

      -- Rotate pending piece using left/right
      if btn(⬅️, i - 1) then
        cur.pending_orientation = cur.pending_orientation - rotation_speed
        if cur.pending_orientation < 0 then cur.pending_orientation = cur.pending_orientation + 1 end
      end
      if btn(➡️, i - 1) then
        cur.pending_orientation = cur.pending_orientation + rotation_speed
        if cur.pending_orientation >= 1 then cur.pending_orientation = cur.pending_orientation - 1 end
      end

      if fa == "must_place_defender" then
        cur.pending_color = p:get_color()
      else
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or p:get_ghost_color()
        else
            cur.pending_color = p:get_ghost_color() 
        end
      end

      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i,
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation,
          color = cur.pending_color
        }
        if place_piece(piece_params, p) then
          cur.control_state = CSTATE_COOLDOWN
          cur.return_cooldown = 6
          if original_update_game_logic_func then original_update_game_logic_func() end
        end
      end

      if btnp(🅾️, i - 1) then
        cur.control_state = CSTATE_MOVE_SELECT
        if effects and effects.exit_placement then
          sfx(effects.exit_placement)
        end
      end

    elseif cur.control_state == CSTATE_COOLDOWN then
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = CSTATE_MOVE_SELECT
        cur.pending_type = "defender"
        cur.pending_color = (p and p:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
--cursor
local dcp={control_state=0,pending_type="defender",pending_orientation=0.25,color_select_idx=1,return_cooldown=0}
function create_cursor(player_id,initial_x,initial_y)
 local p=player_manager and player_manager.get_player and player_manager.get_player(player_id)
 local pc,pgc=p and p.color or 7,p and p.ghost_color or 7
 local cur={
  id=player_id,x=initial_x,y=initial_y,spawn_x=initial_x,spawn_y=initial_y,
  control_state=0,pending_type="defender",pending_orientation=0.25,pending_color=pgc,
  color_select_idx=1,return_cooldown=0,
  draw=function(self)
   local cp=player_manager and player_manager.get_player(self.id)
   local cc=cp and cp.color or self.pending_color
   local cx,cy=self.x+4,self.y+4
   line(cx-2,cy-2,cx+2,cy+2,cc)line(cx-2,cy+2,cx+2,cy-2,cc)
   if self.pending_type~="capture"then
    local gp=create_piece({owner_id=self.id,type=self.pending_type,position={x=cx,y=cy},
     orientation=self.pending_orientation,color=self.pending_color,is_ghost=true})
    if gp and gp.draw then gp:draw()end
   end
   if cp and cp.capture_mode and pieces then
    for _,mp in ipairs(pieces)do
     if mp.owner_id==self.id and mp.type=="defender"and mp.state=="overcharged"and mp.targeting_attackers then
      for _,atc in ipairs(mp.targeting_attackers)do
       if atc and atc.position and atc.type=="attacker"then
        circ(atc.position.x,atc.position.y,5,14)
       end
      end
     end
    end
   end
  end
 }
 return cur
end
-->8
--cpu
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
__gfx__
00000000777777777777777777777777000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000766666666666666666666667000800800d0000d000bbbb00000000000000000000000000000000000000000000000000000000000000000100000000
00000000761111111111111111111167000888800dddddd00bbbbbb0000000000000000000000000000000000000000000000000000000000000000000000000
0000000076111111111111111111116700008800000dd0000bb00bb00000000000000000000000000000000000000000000037000000000000d0000000006600
0000000076111111111111111111116700089880000ddd000bb00bb0000000000000000000000000000000000000000000000300005000000010000000000600
000000007611111111111111111111670008008000dd0dd00bbbbbb0000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000dd000dd00bbbb00000000000000000000000000000000000000000000000000000000000000000000000000
00000000761111111111111111111167000000000d00000d00000000000000000000000000000000000000000000000000000000000000500000000000000000
000000007611111111111111111111670000000000000dd000000000000000000000000000000000000000000000000000000000000000555555555000000000
000000007611111111111111111111670888088000d00d0000bbbb00000000000000000000000000000000000000000000000000000055111111111550020000
000000007611111111111111111111670008880000d0dd000bb00bb0000000000000000000000000000000000000000000000000005511111111115515500000
000000007611111111111111111111670000890000ddc0000b0bb0b0000000000000000000000000000000000000000000000000551111111111222511155000
0000000076111111111111111111116700088980000dcdd00b0bb0b0000000000000000000000000000000000000000000000005111111112222555511111500
0000000076111111111111111111116700880080000d00dd0bb00bb0000000000000000000000000000000000000000000000051111555522555555111221150
0000000076111111111111111111116700800880000d000d00bbbb00000000000000000000000000000000000000000000000511111552255555555522211115
0000000076111111111111111111116700000000000d000000000000000000000000000000000000000000000000000000005111111222222222255241112211
0000000076111111111111111111116700000880000dd0000000000000000000000000000000000000000000000000000000511ee11122111155555441222211
00000000761111111111111111111167000088000000d00000bbbb00000000000000000000000000000000222220000000051111eee225555555554442222551
00000000761111111111111111111167088880000000d00d0bb00bb0000000000000000000000000000022555552200000051111122555552255444122222551
000000007611111111111111111111670008800000ddccdd0b0000b0000000000000000000000000000255555225520000051111225522222444112255225551
00000000761111111111111111111167000990000dd0cd000b0000b0000000000000000000000000002522222255552000511152222214222111155552255551
00000000761111111111111111111167088988800d00dd000bb00bb000000000000000000000000000255c555555552000511155555122122255522225555511
000000007666666666666666666666678800008800000dd000bbbb0000000000000000000000000002555555222555c200511155555555555522222255555ee1
0000000077777777777777777777777700000008000000d0000000000000000000000000000000000255222225555252005155111555555555555555555ee111
00000000111111677611111111111111800000080000000000000000000000000000000000000000025555555332225200515511111111222222221581115555
0000000011111167761111111111111188000088000000dd00000000000000000000000000000000025335c52222555200515555111111222221115111555255
00000000151111677611151111111111088008800dddddd0000bb00000000000000000000000000002553222225c555200515555551111111115555555552211
000000001d51116776115d1111111111008088000d0ddcd000b00b00000000000000000000000000002552555555552000511155555528222552555552222111
0000000011111167761111111111d11100889000000dccd000b00b00000000000000000000000000002555555555252000051111552255555555555222221111
000000001111116776111111111d11110009900000dd0ddd000bb00000000000000000000000000000025ee52222220000051111111155225555511111111eee
000000001111116776111111111111110880888000d000d0000000000000000000000000000000000000222255522000000511112555211111118111111eee11
000000001111116776111111111111118800008800dd000000000000000000000000000000000000000000222220000000005111111111111111111111111111
__label__
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111111
11cc1111111cc1670000000000000000000000000000000000000077700000777077700000000000000000000000000000000000000000007688811111888111
111c111111c111670000000000000000000000000000000000000000700700007000700000000000000000000000000000000000000000007611811111818111
111c111111c111670000000000000000000000000000000000000077700000077000700000000000000000000000000000000000000000007618811111888111
111c111111c111670000000000000000000000000000000000000070000700007000700000000000000000000000000000000000000000007611811111818111
11ccc111111cc1670000000000000000000000000000000000000077700000777000700000000000000000000000000000000000000000007688811111818111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111188
1cc1881bb11111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111188
1cc1881bb11111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111888
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111188188
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111118111188
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111181111111
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611118111111111
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611881111111111
1cc11111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007618111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007881111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000007611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000087611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000807611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080007611111111111111
66666666666666670000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008800007666666666666666
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000080000007777777777777777
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008800000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000800000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000008000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000bbbb0000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000b000bbbbb00000000000800000000000000000000000000000
0000000000000000000000000000eeeee000000000000000000000000000000000000000000000b0bbbbbbb00000000088000000000000000000000000000000
000000000000000000000000000e00000e00000000000000000000000000000000000000000000bbbbbbb0bbbb00000800000000000000000000000000000000
00000000000000000000000000e8800000e0000000000000000000000000000000000000000000bbb00bb0bbb000088000000000000000000000000000000000
0000000000000000000000000e800800000e00000000000000000000000000000000000000000b0bb00bb0b0b008000000000000000000000000000000000000
0000000000000000000000000e800088000e00000000000000000000000000000000000000000b0bbbbbbb0b0080000000000000000000000000000000000000
0000000000000000000000000e800000800e00000000000000000000000000000000000000000b00bbbbbbb08000000000000000000000000000000000000000
0000000000000000000000000e000000080e00000000000000000000000000000000000000006bbbb00bbb0b0000000000000000000000000000000000000000
0000000000000000000000000e888888888e000000000000000000000000000000000000000006000bbbbb000000000000000000000000000000000000000000
00000000000000000000000000e0000000e0aaa000000000000000000000000000000000000000000000b8000000000000000000000000000000000000000000
000000000000000000000000000e00000e000000aaa0000000000000000000000000000000000000000880000000000000000000000000000000000000000000
0000000000000000000000000000eeeee00000500000a00000000000000000000000000000000000008b00000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000aa0a000000ccccccccc0000000000000000880b00000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000aa0000cd0000d0c0000000000000080000b00000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000aa0cdddddd0c0000000000000800000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000c00dd000c000000000008000000b000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000c00ddd00c000000000880000000b000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000c0dd0dd0c00000000000000000b0000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000add000ddc0000000080000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000acd00000dc00000088000000000b0000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000a00caccccccc00008000000000000b0000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000a0000a00000000008000000000000b00000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000a000080008800000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000088888000000000000000b00000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000a00000000a088800808000000000000000b00000000000000000500000000000000000000000000000
000000000000000000000000000000000000000000000a000000000a00800808000000000000000b00000000000000b000000000000000000000000000000000
0000000000000000000000000000000000eeeee0000a0000000000a00080808080000000000000000000000000000b0b00000000000000000000000000000000
000000000000000000000000000000000e00000e0aa0000000000a0000080800000000000000000b0000000000000b00b0000050000000000000000000000000
00000000000000000000000000000000e0000000e000000000000a000008080000000000000000b0000000000000b0000b000000000000000000000000000000
0000000000000000000000000000002e2220008aae0000000000a000000080000000000000000000000000000000b0000bb00000000000000000000000000000
0000000000000000000000000000225e558888800e000000000000000000000000000000000000b000000000000b000bb0000000000000000000000000000000
0000000000000000000000000002555e882552800e000000000a00000000000000003700000000b000000000000bbbb000000000000000000000000000000000
0000000000000000000000000025222e825558200e000000000a0000000000000000030000000b000000000000bb000000000000000000000000000000000000
00000000000000000000000000255c5e855585200e00000000a000000000000000000000000000000000000a0000000000000000000000000000000000000000
00000000000000000000000002555555e82855c2e0000eeeee000000000000000000000000000b0000000aaa0000000000000000000000000000000000000000
000000000000000000000000025522222e58525e0000e0000ae00000000000000000000000000b000000a000a000000000000000000000000000000000000000
0000000000000000000000000255555553eeeee2000e0000aa0e000000000000000000000000b000000a0000a000000000000000000000000000000000000000
000000000000000000000000025335c52222555200e00a0a0a00e0000000000000000000000000000aa00000a000000000000000000000000000000000000000
00000000000000000000000002553222225c555200e000a0aa00e00000000000000000000000b000aaaaa0000a000000000000000000c0000000000000000000
000000000000000000000000002552555555552000e00a0a0a00e00000000000000000000000b00a00000aaaaa00000000000000000c0c000000000000000000
000000000000000000000000002555555555252000e0a0a0a000e0000000000000000000000baa0000000000000000000000b00000c00c000000000000000000
00000000000000000000000000025ee52222220000eaaa00aa00e000000000000000000aaa0000000000000000000000000bb0000c0000c00000000000000000
0000000000000000000000000000222255522000000e0aa0a00e00000000000000000a0000b00000000000000000000000b0b000c00000c00000000000000000
00000000000000000000000000c000c2222000000000e00aa0e00000000000000a0aa00000b000000000000000000000bb00b00c000ccccc0000000000000000
000000000000000000000000000c0c000000000000000eeeee0000000000000aa000000000b00000000000000000000b00000bccccc000000000000000000000
0000000000000000000000000000c0000000000000000000000000000000aaa0000000000000000000000000000000b000000b00000000000000000000000000
000000000000000000000000000c0c0000000000000000000000000000a00000000000000b000000000000000000bbbbbbbbbb00000000000000000000000000
00000000000000000000000000c000c00000000000000000000000a0aa000000000000000b0000000000000000bb000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000aa0000000000000000000b0000000000bbb00000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000a0000000000000000000000000000000000b00000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000aa000000000000000000000000b000000b0bb000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000aaa000000000000000000000000000b00b0bb0000000000000000000000000000000000000000000000000
0000000000000000000000000000000088888888a0000000000000000000000000000000bbb00000000000000000000000000000000000000000000000000000
0000000000000000000000000000000080bbbb0080000000000000000000000000000bbb00000000000000000000000000000000000000000000000000000000
000000000000000000000000000000008bbbbbb08000000000000000000000000bbb000b00000000000000000000000000000000000000000000000000000000
000000000000000000000000000000008bb00bb080000000000000000000000b0000000b00000000000000000000000000000000000000000000000000000000
000000000000000000000000000000008bb00bb080000000000000000000b0b00000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000080bbbbbb8000000000000000000bb0000000000b000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000800bbbb080000000000000abbb0000000000000b000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000008000000080000000000000a000aaaaa00000000b000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000008888888880000000000000a0bbbb00a000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000abbbbbb0a0100000b0000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000abb00bb0a0000000b0000000000000000000000000000000000000000000000000000000000
00000000000000000000370000000000000000000000000000000abb00bb0a000000b00000000000000000000000000000003700000000000000000000000000
00000000000000000000030000000000000000000000000000000abbbbbb0a000000000000000000000000000000000000000300000000000000000000000000
00000000000000000000000000000000000000000000000000000a0bbbb00a000000b00000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000aaaa0000a000000b00000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000aaaaa00000b000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000b000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000000000000000b0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000b00000000000000000000000000000000000000000000000000000000000000
77777777777777770000000000000000000000000000000000000000000000000000000000000000000000000000005555555550000000007777777777777777
66666666666666670000000000000000000000000000000000000000000000000b00000000000000000000000000551111111115500200007666666666666666
11bbb11111bbb1670000000000000000000000000000000000000000000000000b000000000000000000000000551111111111551550000076aaa11111aaa111
1111b11111b1b167000000000000000000000000000000000000000000000000b000000000000000000000005511111111112225111550007611a11111a1a111
111bb11111bbb167000000000000000000000000000000000000000000000000b00000000000000000000005111111112222555511111500761aa11111aaa111
1111b11111b1b167000000000000000000000000000000000000000000000000b000000000000000000000511115555225555551112211507611a11111a1a111
11bbb11111b1b16700000000000000000000000000000000000000000000000b00000000000000000000051111155225555555552221111576aaa11111a1a111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000051111112222222222552411122117611111111111111
111111111111116700000000000000000000000000000000000000000000000b00000000000000000000511ee111221111555554412222117611111111111111
111111111111116700000000000000000000000000000000000000000000000b000000000000000000051111eee2255555555544422225517611111111111111
11111111111111670000000000000000000000000000000000000000000000b00000000000000000000511111225555522554441222225517611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000511112255222224441122552255517611111111111111
1111111111111167000000000000000000000000000000000000000000500b000000000000000000005111522222142221111555522555517611111111111111
1111111111111167000000000000000000000000000000000000000000000b000000000000000000005111555551221222555222255555117611111111111111
1111111111111167000000000000000000000000000000000000000000000b00000000000000000000511155555555555522222255555ee17611111111111111
11111111111111670000000000000000000000000000000000000000000000500000000000000000005155111555555555555555555ee1117611111111111111
111111111111116700000000000000000000000000000000000000000000b0000000000000000000005155111111112222222215811155557611111111111111
111111111111116700000000000000000000000000000000000000000000b0000000000000000000005155551111112222211151115552557611111111111111
1111111bb111116700000000000000000000000000000000000000000000b0000000000000000000005155555511111111155555555522117611111111111111
1111111bb11111670000000000000000000000000000000000000000000000000000000000000000005111555555282225525555522221117611111111111111
1111111bb11111670000000000000000000000000000000000000000000b00000000000000000000000511115522555555555552222211117611111111111111
1111111bb11111670000000000000000000000000000000000000000000b0000000000000000000000051111111155225555511111111eee7611111111111111
11111111111111670000000000000000000000000000000000000000000b00000000000000000000000511112555211111118111111eee117611111111111111
11111111111111670000000000000000000000000000000000000000000000000000000000000000000051111111111111111111111111117611111111111111

__map__
1213000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1213000000000000000000000000111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2223000000000000000000000000212200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000d000000000f00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000002a2b0000000c0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000003a3b000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000c000000000e000000000c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
020300000000000000001c1d1e1f010200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
121300000000000d00002c2d2e2f111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
121300000000000000003c3d3e3f111200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0102020202020202020202020202020300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
1112121212121212121212121212121300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
2122222222222222222222222222222300000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
00010000226501f6501d6501a6501765014650116500f6500f6500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000c3100c3200c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3300c3200c3100c3100c310
011000001815000100001000010000100001000010000100181500010000100001000010000100001000010018150001000010000100001000010000100001002415224152241522415200100000000000000000
0110000007412134221343213432034321f432134321343207432134321f4321343203432134320c4320c432074321b4321f4322743207432164322b43216432034321f432244320f432004320c4321842218010
001000000705007000030500a0000c0000f00016050130001b000000001f000220000000000000240500000000000000001b0501f050000000000000150021500000000000000000000000000000000000000000
001000000c3530060000000006000c3530060000600006000f6330060000600006000c3530060000600006000c3530060000600006000c3530060000600006001c63300600006000c35300600006000c35300600
0010000000000000001f050070501805000000000000000018050000001b05000000180501b0500000000000000001b0500000018050180500000000000000001f05022050000002405000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000a3100a3200a3300a3300a3300a3300a3300a3300a3300a3300a3300a3300a3300a3300a3300a3300a33016330163300a33016330163300a3301633016330163300a3301633016330163300a32016310
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00100000134121342213432134320f4321f432134321343213432134321f432134321b432134320c4320c432134321b4321f4322743213432164322b432164320f4321f432244320f4320c4320c4221841218010
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
01100000001520020300003006031b6730000000603006030f6430060300003006031b6731860300603006030c1520060300603006030f6730010300603006031c6330000000603006031b67300603006030c153
0010000000000000002705026050240500000024050000001b050000001b05000000180501b0500000000000000001b050000002405027050270500000027050000001f050220500000024050000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000831008320083300833008330083300833008330083300833008330083300833008330083300833008330083300833008330083300833008330083300833008330083300833008330083200831000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000c3530060000000006000c3530060000600006000f6330060000600006000c3530060000600006000c3530060000600006000c3530060000600006001c63300600006000c35300600006000c35300600
0010000000000000002705026050240500000030050000001b050000001b05000000180501b0500000000000000001b050000003005027050270500000027050000001f050220500000024050000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000002405000000220500000027050260503005000000000000000030055000060000000000330503205030050000003205033050000000000000000000003205633056370563a05630056330562405022050
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000001d77029700227000070000700007002670000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700007000070000700
000700000c7701f7700000027770297001f7700000027770000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0107000027770000001f7702970027770000001f77000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0002000021650216501f6501865016650136501165010650106500000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000400000d7500c7500b7500e75013750197501d7501f750217502275022700237002370000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
011000002215000100221500010022150001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100001000010000100
0002000019750167501475011750107500f7500e7500f750107501375015750177501a7501e750000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
010800000845008450084500745007450074500050000500005000050000500095000950009500095000950009500005000050000500005000050000500005000050000500005000050000500005000050000500
001000002745027400274502745027450274002740027400274002740027400274002740027400274002740027400274002740027400274002740027400274002740027400274002740000000000000000000000
001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0020000024a5000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__music__
00 42024344
01 01050344
00 09050b44
00 11050b44
00 09050b44
00 010d0344
00 090d0344
00 110d0344
00 090d0344
00 01050644
00 09050e44
00 11051644
00 09051e44
00 010d0644
00 090d0e44
00 110d1644
02 090d1e44

