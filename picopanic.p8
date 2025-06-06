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
              player_obj:add_captured_piece(captured_color)
              if del(pieces, attacker_to_capture) then
                -- printh("P" .. player_id .. " captured attacker (color: " .. captured_color .. ")")
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
    else
      cursors[i] = {
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
          -- printh("Fallback cursor draw for P"..i)
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
    -- printh("GO_TO_STATE: CAPTURED STASH_SIZE="..current_game_stash_size)

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

    -- Update CPU players
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
   local s,m=tostr(p:get_score()),"?"
   if c and c.pending_type then
    if c.pending_type=="attacker"then m="A"
    elseif c.pending_type=="defender"then m="D"
    elseif c.pending_type=="capture"then m="C"end
   end
   local sm,w=s.." "..m,#(s.." "..m)*4
   local ax,ay=(i==2 or i==4)and 112 or 0,(i>=3)and 104 or 0
   local tx=(i==1 or i==3)and ax+2 or ax+14-w
   print(sm,tx,ay+2,p:get_color())
   local by,bh=ay+9,13
   for j=1,4 do
    local col,cnt=player_manager.colors[j]or 0,p.stash[player_manager.colors[j]or 0]or 0
    local h=flr(cnt/STASH_SIZE*bh)
    local bx=((i==1 or i==3)and ax+1 or ax+11)+(j-1)*3
    local y1,y2=(i<=2)and by or by+bh-h,(i<=2)and by+h-1 or by+bh-1
    if h>0 then rectfill(bx,y1,bx+1,y2,col)end
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
  -- Update all three rotation axes at much slower speeds for smooth motion
  pyramid_rotation_x += 0.005
  pyramid_rotation_y += 0.008
  pyramid_rotation_z += 0.003
  
  -- Large pyramid vertices (scaled up for top 2/3 of screen)
  local size = 30
  local height = 25
  local vertices = {
    {x = -size, y = 0, z = -size},    -- base vertex 1
    {x = size, y = 0, z = -size},     -- base vertex 2
    {x = size, y = 0, z = size},      -- base vertex 3
    {x = -size, y = 0, z = size},     -- base vertex 4
    {x = 0, y = -height, z = 0}       -- apex
  }
  
  -- Rotation matrices for all three axes
  local cos_x, sin_x = cos(pyramid_rotation_x), sin(pyramid_rotation_x)
  local cos_y, sin_y = cos(pyramid_rotation_y), sin(pyramid_rotation_y)
  local cos_z, sin_z = cos(pyramid_rotation_z), sin(pyramid_rotation_z)
  
  local projected = {}
  for i, v in ipairs(vertices) do
    local x, y, z = v.x, v.y, v.z
    
    -- Rotate around X axis
    local y1 = y * cos_x - z * sin_x
    local z1 = y * sin_x + z * cos_x
    
    -- Rotate around Y axis
    local x2 = x * cos_y + z1 * sin_y
    local z2 = -x * sin_y + z1 * cos_y
    
    -- Rotate around Z axis
    local x3 = x2 * cos_z - y1 * sin_z
    local y3 = x2 * sin_z + y1 * cos_z
    
    -- Simple perspective projection
    local distance = 100
    local scale = distance / (distance + z2)
    local px = cx + x3 * scale
    local py = cy + y3 * scale + 20  -- offset down a bit in the top area
    
    projected[i] = {x = px, y = py, z = z2}
  end
  
  -- Draw pyramid faces with proper depth sorting
  -- Base (square base for more impressive look)
  line(projected[1].x, projected[1].y, projected[2].x, projected[2].y, color)
  line(projected[2].x, projected[2].y, projected[3].x, projected[3].y, color)
  line(projected[3].x, projected[3].y, projected[4].x, projected[4].y, color)
  line(projected[4].x, projected[4].y, projected[1].x, projected[1].y, color)
  
  -- Side faces from base to apex
  line(projected[1].x, projected[1].y, projected[5].x, projected[5].y, color)
  line(projected[2].x, projected[2].y, projected[5].x, projected[5].y, color)
  line(projected[3].x, projected[3].y, projected[5].x, projected[5].y, color)
  line(projected[4].x, projected[4].y, projected[5].x, projected[5].y, color)
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
function Player:new(id,s,c,gc,cpu)
 local base_delay = cpu and (120 + rnd(60)) or 0  -- 120-180 frames for CPU, 0 for humans
 local i={id=id,score=s or 0,color=c,ghost_color=gc,stash={},capture_mode=false,is_cpu=cpu or false,cpu_timer=rnd(base_delay),cpu_action_delay=base_delay}
 i.stash[c]=STASH_SIZE or 6
 setmetatable(i,self)return i
end
function Player:get_score()return self.score end
function Player:add_score(p)self.score=self.score+(p or 1)end
function Player:get_color()return self.color end
function Player:get_ghost_color()return self.ghost_color end
function Player:is_in_capture_mode()return self.capture_mode end
function Player:toggle_capture_mode()self.capture_mode=not self.capture_mode end
function Player:add_captured_piece(pc)
 if self.stash[pc]==nil then self.stash[pc]=0 end
 self.stash[pc]+=1
end
function Player:get_captured_count(pc)return self.stash[pc]or 0 end
function Player:has_piece_in_stash(pc)return(self.stash[pc]or 0)>0 end
function Player:use_piece_from_stash(pc)
 if self:has_piece_in_stash(pc)then self.stash[pc]=self.stash[pc]-1 return true end
 return false
end
player_manager.colors={[1]=12,[2]=8,[3]=11,[4]=10}
player_manager.ghost_colors={[1]=1,[2]=9,[3]=3,[4]=4}
player_manager.max_players,player_manager.current_players=4,{}
function player_manager.init_players(np)
 if np<1 or np>player_manager.max_players then return end
 player_manager.current_players={}
 for i=1,np do
  local c,gc=player_manager.colors[i]or 7,player_manager.ghost_colors[i]or 1
  local cpu=(i>np-CPU_PLAYERS)
  player_manager.current_players[i]=Player:new(i,0,c,gc,cpu)
 end
end
function player_manager.get_player(pid)return player_manager.current_players[pid]end
function player_manager.get_player_color(pid)
 local p=player_manager.get_player(pid)
 return p and p:get_color()or 7
end
function player_manager.get_player_ghost_color(pid)
 local p=player_manager.get_player(pid)
 return p and p:get_ghost_color()or 1
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
  -- Ensure required globals are available
  local player_manager = player_manager
  local ray_segment_intersect = ray_segment_intersect
  local LASER_LEN = LASER_LEN
  local add = add
  reset_player_scores()
  reset_piece_states_for_scoring()

  for _, attacker_obj in ipairs(pieces) do
    if attacker_obj and attacker_obj.type == "attacker" then
      local attacker_vertices = attacker_obj:get_draw_vertices()
      if attacker_vertices and #attacker_vertices > 0 then
        local apex = attacker_vertices[1]
        local dir_x = cos(attacker_obj.orientation)
        local dir_y = sin(attacker_obj.orientation)
        local closest_t = LASER_LEN
        local closest_piece = nil
        -- Check all other pieces for intersection
        for _, target_obj in ipairs(pieces) do
          if target_obj ~= attacker_obj then
            local target_corners = target_obj:get_draw_vertices()
            if target_corners and #target_corners > 0 then
              for j = 1, #target_corners do
                local k = (j % #target_corners) + 1
                local ix, iy, t = ray_segment_intersect(apex.x, apex.y, dir_x, dir_y,
                  target_corners[j].x, target_corners[j].y,
                  target_corners[k].x, target_corners[k].y)
                if t and t >= 0 and t < closest_t then
                  closest_t = t
                  closest_piece = target_obj
                end
              end
            end
          end
        end
        if closest_piece then
          _check_attacker_hit_piece(attacker_obj, closest_piece, player_manager, ray_segment_intersect, LASER_LEN, add)
        end
      end
    end
  end

  for _, p_obj in ipairs(pieces) do
    _score_defender(p_obj, player_manager)
    if p_obj.type == "defender" then
      p_obj.dbg_target_count = nil
      -- Update defender state based on final hit count
      if p_obj.hits >= 3 then
        p_obj.state = "overcharged"
      elseif p_obj.hits == 2 then
        p_obj.state = "unsuccessful"
      elseif p_obj.hits <= 1 then
        p_obj.state = "successful"
      end
    end
  end

  local remaining_pieces = {}
  for _,p_obj in ipairs(pieces) do
    if not p_obj.captured_flag then
      add(remaining_pieces, p_obj)
    end
  end
  pieces = remaining_pieces
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
-->8
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
-->8
--controls
local CSTATE_MOVE_SELECT,CSTATE_ROTATE_PLACE,CSTATE_COOLDOWN=0,1,2

function update_controls()
 for i,cur in ipairs(cursors)do
  local p=player_manager.get_player(i)
  if not p then goto next_cursor_ctrl end
  
  -- Skip controls for CPU players
  if p.is_cpu then goto next_cursor_ctrl end
  
  local current_player_obj = p  -- Set the current player object
  
  local empty_stash=true
  if p and p.stash then
   for _,cnt in pairs(p.stash)do if cnt>0 then empty_stash=false end end
  end
  local has_def=false
  if pieces then
   for _,po in pairs(pieces)do
    if po.owner_id==i and po.type=="defender"and po.state=="successful"then has_def=true break end
   end
  end
  local forced="normal"
  if empty_stash then
   cur.pending_type="capture"
   forced="capture_only"
  elseif not has_def then
   cur.pending_type="defender"
   cur.pending_color=p:get_color()
   forced="must_place_defender"
  end
  if cur.control_state==CSTATE_MOVE_SELECT and btnp(🅾️,i-1)and forced=="normal"then
   if cur.pending_type=="defender"then
    cur.pending_type="attacker"
        elseif cur.pending_type == "attacker" then
            cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
            cur.pending_type = "defender"
        end
        cur.pending_orientation = 0
        if effects and effects.switch_mode then
          sfx(effects.switch_mode)
        end
    end

    if current_player_obj then
        current_player_obj.capture_mode = (cur.pending_type == "capture")
    end

    if cur.control_state == CSTATE_MOVE_SELECT then
      if btn(⬅️, i - 1) then 
        cur.x = max(0, cur.x - cursor_speed) 
      elseif btnp(⬅️, i - 1) then 
        cur.x = max(0, cur.x - 1) 
      end
      
      if btn(➡️, i - 1) then 
        cur.x = min(cur.x + cursor_speed, 128 - 8) 
      elseif btnp(➡️, i - 1) then 
        cur.x = min(cur.x + 1, 128 - 8) 
      end
      
      if btn(⬆️, i - 1) then 
        cur.y = max(0, cur.y - cursor_speed) 
      elseif btnp(⬆️, i - 1) then 
        cur.y = max(0, cur.y - 1) 
      end
      
      if btn(⬇️, i - 1) then 
        cur.y = min(cur.y + cursor_speed, 128 - 8) 
      elseif btnp(⬇️, i - 1) then 
        cur.y = min(cur.y + 1, 128 - 8) 
      end

      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end
          end
        else
          cur.control_state = CSTATE_ROTATE_PLACE
          if effects and effects.enter_placement then
            sfx(effects.enter_placement)
          end
        end
      end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if forced_action_state == "must_place_defender" then
        add(available_colors, current_player_obj:get_color())
        cur.color_select_idx = 1
      else
        if current_player_obj and current_player_obj.stash then
          for color, count in pairs(current_player_obj.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      if #available_colors == 0 and current_player_obj and current_player_obj:has_piece_in_stash(current_player_obj:get_color()) then
         add(available_colors, current_player_obj:get_color())
      elseif #available_colors == 0 then
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl
      end

      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      if forced_action_state ~= "must_place_defender" then
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

      if forced_action_state == "must_place_defender" then
        cur.pending_color = current_player_obj:get_color()
      else
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_ghost_color()
        else
            cur.pending_color = current_player_obj:get_ghost_color() 
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
        if place_piece(piece_params, current_player_obj) then
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
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
--cursor
local dcp={control_state=0,pending_type="defender",pending_orientation=0.25,color_select_idx=1,return_cooldown=0}
function create_cursor(player_id,initial_x,initial_y)
 local pc,pgc=7,7
 if player_manager and player_manager.get_player then
  local p=player_manager.get_player(player_id)
  if p then
   if p.get_color then pc=p:get_color()end
   if p.get_ghost_color then
    local gcv=p:get_ghost_color()
    if gcv then pgc=gcv end
   end
  end
 end
 local cur={
  id=player_id,x=initial_x,y=initial_y,spawn_x=initial_x,spawn_y=initial_y,
  control_state=dcp.control_state,pending_type=dcp.pending_type,
  pending_orientation=dcp.pending_orientation,pending_color=pgc,
  color_select_idx=dcp.color_select_idx,return_cooldown=dcp.return_cooldown,
  draw=function(self)
   local cc,cp
   if player_manager and player_manager.get_player then
    cp=player_manager.get_player(self.id)
    if cp and cp.get_color then cc=cp:get_color()end
   end
   if not cc then cc=self.pending_color end
   local cx,cy=self.x+4,self.y+4
   line(cx-2,cy-2,cx+2,cy+2,cc)line(cx-2,cy+2,cx+2,cy-2,cc)
   if self.pending_type=="attacker"or self.pending_type=="defender"then
    local gpp={owner_id=self.id,type=self.pending_type,position={x=self.x+4,y=self.y+4},
     orientation=self.pending_orientation,color=self.pending_color,is_ghost=true}
    local gp=create_piece(gpp)
    if gp and gp.draw then gp:draw()end
   end
   if cp and cp:is_in_capture_mode()then
    if pieces then
     for _,mp in ipairs(pieces)do
      if mp.owner_id==self.id and mp.type=="defender"and mp.state=="overcharged"then
       if mp.targeting_attackers and #mp.targeting_attackers>0 then
        for _,atc in ipairs(mp.targeting_attackers)do
         if atc and atc.position and atc.type=="attacker"then
          circ(atc.position.x,atc.position.y,5,14)
         end
        end
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

