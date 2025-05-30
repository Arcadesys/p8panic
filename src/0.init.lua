function finish_game_menuitem()
  if current_game_state == GAME_STATE_PLAYING then
    if score_pieces then score_pieces() end
    current_game_state = GAME_STATE_GAMEOVER
    GAME_TIMER = 0
  end
end

gameover_timer = 2

pre_game_state = nil
pre_game_start_t = 0
pre_game_sequence = {"3...", "2...", "1..."}

function draw_centered_sequence(seq, start_t, color)
  local elapsed = time() - start_t
  local idx = flr(elapsed) + 1
  if idx <= #seq then
    local s = seq[idx]
    print(s, 64 - (#s * 2), 64, color or 7)
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
PLAYER_COUNT = 2
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
                printh("P" .. player_id .. " captured attacker (color: " .. captured_color .. ")")
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
  local all_possible_spawn_points = {
    {x = 18, y = 18},
    {x = 128 - 18 - 1, y = 18},
    {x = 18, y = 128 - 18 - 1},
    {x = 128 - 18 - 1, y = 128 - 18 - 1}
  }

  cursors = {}

  for i = 1, num_players do
    local sp
    if i <= #all_possible_spawn_points then
      sp = all_possible_spawn_points[i]
    else
      printh("Warning: No spawn point defined for P" .. i .. ". Defaulting.")
      sp = {x = 4 + (i-1)*10, y = 4}
    end

    if create_cursor then
      cursors[i] = create_cursor(i, sp.x, sp.y)
    else
      printh("ERROR: create_cursor function is not defined! Cannot initialize cursors properly.")
      cursors[i] = {
        id = i,
        x = sp.x, y = sp.y,
        spawn_x = sp.x, spawn_y = sp.y,
        control_state = 0,
        pending_type = "defender",
        pending_color = 7,
        pending_orientation = 0,
        return_cooldown = 0,
        color_select_idx = 1,
        draw = function() printh("Fallback cursor draw for P"..i) end
      }
    end
  end
end

GAME_STATE_MENU = 0
GAME_STATE_PLAYING = 1
GAME_STATE_GAMEOVER = 2

current_game_state = GAME_STATE_MENU

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
    printh("Error: score_pieces is nil in internal_update_game_logic!")
  end
end


function go_to_state(new_state)
  if new_state == GAME_STATE_PLAYING and current_game_state ~= GAME_STATE_PLAYING then
    local current_game_stash_size = STASH_SIZE
    printh("GO_TO_STATE: CAPTURED STASH_SIZE="..current_game_stash_size)

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
        printh("P"..i.." STASH INIT: C="..p:get_color().." SZ="..current_game_stash_size.." CT="..p.stash[p:get_color()])
      end
    end
    if original_update_game_logic_func then original_update_game_logic_func() end
  end
  current_game_state = new_state
end


function _init()
  menuitem(1, "Finish Game", finish_game_menuitem)
  if not player_manager then
    printh("ERROR: player_manager is NIL in _init()", true)
  end
  
  if internal_update_game_logic then
    original_update_game_logic_func = internal_update_game_logic
  else
    printh("ERROR: internal_update_game_logic is NIL in _init!", true)
    original_update_game_logic_func = function() end
  end
  
  if update_controls then
    original_update_controls_func = update_controls
  else
    printh("ERROR: update_controls is NIL in _init!", true)
    original_update_controls_func = function() end
  end
  
  if not _ENV.score_pieces then
     printh("ERROR: score_pieces is NIL in _init!", true)
  end

  menu_selection = 1
  
  current_game_state = GAME_STATE_MENU
  
  if not player_manager.get_player_count then
     printh("ERROR: player_manager.get_player_count is NIL in _init()", true)
  end
end



function update_menu_state()
  if not menu_selection then menu_selection = 1 end

  if btnp(⬆️) then
    menu_selection = max(1, menu_selection - 1)
  elseif btnp(⬇️) then
    menu_selection = min(3, menu_selection + 1)
  end

  if menu_selection == 1 then
    if btnp(⬅️) then
      STASH_SIZE = max(3, STASH_SIZE - 1)
    elseif btnp(➡️) then
      STASH_SIZE = min(10, STASH_SIZE + 1)
    end
  elseif menu_selection == 2 then
    if btnp(⬅️) then
      PLAYER_COUNT = max(2, PLAYER_COUNT - 1)
    elseif btnp(➡️) then
      PLAYER_COUNT = min(4, PLAYER_COUNT + 1)
    end
  elseif menu_selection == 3 then
    if btnp(⬅️) then
      ROUND_TIME = max(ROUND_TIME_MIN, ROUND_TIME - 30)
    elseif btnp(➡️) then
      ROUND_TIME = min(ROUND_TIME_MAX, ROUND_TIME + 30)
    end
  end

  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_PLAYING)
  end
end


function update_playing_state()
  local pre_game_active = update_pre_game_sequence()

  if pre_game_state ~= 'countdown' then
    if original_update_controls_func then 
      original_update_controls_func() 
    else 
      printh("Error: original_update_controls_func is nil in update_playing_state!") 
    end

    if original_update_game_logic_func then
      if type(original_update_game_logic_func) == "function" then
        original_update_game_logic_func()
      else
        printh("Error: original_update_game_logic_func is not a function in update_playing_state!")
      end
    else 
      printh("Error: original_update_game_logic_func is nil in update_playing_state!") 
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
  end
end


function _update()
  if current_game_state == GAME_STATE_MENU then
    update_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    update_playing_state()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    update_gameover_state()
  end
end

function update_gameover_state()
  if gameover_timer and gameover_timer > 0 then
    gameover_timer = max(0, gameover_timer - (1/30))
    return
  end
  if btnp(❎) or btnp(🅾️) then
    go_to_state(GAME_STATE_MENU)
  end
end




function draw_menu_state()
  print("P8PANIC", 50, 40, 7)
  print("PRESS X OR O", 40, 54, 8)
  print("TO START", 50, 62, 8)
  if not menu_selection then menu_selection = 1 end
  local stash_color = (menu_selection == 1) and 7 or 11
  local player_color = (menu_selection == 2) and 7 or 11
  local timer_color = (menu_selection == 3) and 7 or 11
  print((menu_selection == 1 and ">" or " ").." STASH SIZE: "..STASH_SIZE, 28, 80, stash_color)
  print((menu_selection == 2 and ">" or " ").." PLAYERS: "..PLAYER_COUNT, 28, 90, player_color)
  local minstr = flr(ROUND_TIME/60)
  local secstr = (ROUND_TIME%60 < 10 and "0" or "")..(ROUND_TIME%60)
  print((menu_selection == 3 and ">" or " ").." ROUND TIME: "..minstr..":"..secstr, 28, 100, timer_color)
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
    local m,fw,fh,bh,bw,bs,nb = 2,4,5,8,2,1,4
    for i=1,player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      if p then
        local s = tostr(p:get_score())
        local sw = #s*fw
        local tw = nb*bw + (nb-1)*bs
        local block_w = max(sw,tw)
        local ax = (i==2 or i==4) and (128-m-block_w) or m
        local ay = (i>=3) and (128-m-(fh+2+bh)) or m
        print(s, ax + ((block_w-sw) * ((i==2 or i==4) and 1 or 0)), ay, p:get_color())
        local bx = (i==2 or i==4) and (ax + block_w - tw) or ax
        local by = ay + fh + 1
        for j=1,nb do
          local col = player_manager.colors[j] or 0
          local cnt = p.stash[col] or 0
          local h = flr(cnt / STASH_SIZE * bh)
          h = mid(0,h,bh)
          if i==1 or i==2 then
            if h>0 then rectfill(bx,by,bx+bw-1,by+h-1,col)
            else line(bx,by,bx+bw-1,by,1) end
          else
            if h>0 then rectfill(bx,by+(bh-h),bx+bw-1,by+bh-1,col)
            else line(bx,by+bh-1,bx+bw-1,by+bh-1,1) end
          end
          bx += bw + bs
        end
      end
    end
  end
end


function draw_gameover_state()
  cls(0)
  map(0, 0, 0, 0, 16, 16, 0)
  draw_playing_state_elements()
  print("FINISH!", 52, 60, 7)
  if not gameover_timer or gameover_timer <= 0 then
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
      local score_text = "P" .. pid .. ": " .. p:get_score()
      print(score_text, 64 - #score_text * 2, 70 + i * 8, p:get_color())
    end
    print("Press X or O to return", 28, 100, 6)
  end
end

function _draw()
  cls(0)
  map(0, 0, 0, 0, 16, 16,0)
  if current_game_state == GAME_STATE_MENU then
    draw_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    draw_playing_state_elements()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    draw_gameover_state()
  end
end
