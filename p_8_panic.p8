pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- effects table for sound effects
-- fill in as you add sfx to your cart

music_enabled = true
effects = {
  attacker_placement = 56,
  defender_placement = 57,
  overcharge = 58,
  capture = 59,
  bad_placement = 60,
  gameover_timer = 61,
  switch_mode = 48,      -- placeholder sfx id for switching mode
  enter_rotation = 49,   -- placeholder sfx id for entering rotation mode
  exit_rotation = 50    -- placeholder sfx id for exiting rotation mode
}

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
  if new_state == GAME_STATE_PLAYING and current_game_state ~= GAME_STATE_PLAYING then
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
  if not menu_selection then menu_selection = 1 end

  if btnp(⬆️) then
    menu_selection = max(1, menu_selection - 1)
  elseif btnp(⬇️) then
    menu_selection = min(5, menu_selection + 1) -- Increased to 5 for new music option
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
  elseif menu_selection == 4 then -- Music toggle
    if btnp(⬅️) or btnp(➡️) then
      music_enabled = not music_enabled
      if not music_enabled then
        music(-1) -- stop music
      else
        if current_game_state == GAME_STATE_PLAYING then
          music(0,0.5)
        end
      end
    end
  end

  if btnp(❎) or btnp(🅾️) then
    if menu_selection == 5 then
      go_to_state(GAME_STATE_TUTORIAL)
    else
      go_to_state(GAME_STATE_PLAYING)
    end
  end
end


function update_playing_state()
  local pre_game_active = update_pre_game_sequence()

  if pre_game_state ~= 'countdown' then
    if original_update_controls_func then 
      original_update_controls_func() 
    else 
    end

    if original_update_game_logic_func then
      if type(original_update_game_logic_func) == "function" then
        original_update_game_logic_func()
      else
      end
    else 
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

function update_starfield()
  for star in all(stars) do
    star.y += star.speed
    if star.y > 128 then
      star.y = -star.size
      star.x = rnd(128)
    end
  end
end

function draw_starfield()
  for star in all(stars) do
    if star.size == 1 then
      pset(star.x, star.y, star.color)
    else
      circfill(star.x, star.y, star.size - 1, star.color)
    end
  end
end

function draw_menu_state()
  print("P8PANIC", 50, 30, 7) -- Adjusted y for new option
  print("PRESS X OR O", 40, 44, 8)
  print("TO START", 50, 52, 8)
  if not menu_selection then menu_selection = 1 end
  local stash_color = (menu_selection == 1) and 7 or 11
  local player_color = (menu_selection == 2) and 7 or 11
  local timer_color = (menu_selection == 3) and 7 or 11
  local music_color = (menu_selection == 4) and 7 or 11
  local tutorial_color = (menu_selection == 5) and 7 or 11

  print("STASH SIZE: "..STASH_SIZE, 28, 70, stash_color)
  print("PLAYERS: "..PLAYER_COUNT, 28, 80, player_color)
  local minstr = flr(ROUND_TIME/60)
  local secstr = (ROUND_TIME%60 < 10 and "0" or "")..(ROUND_TIME%60)
  print("ROUND TIME: "..minstr..":"..secstr, 28, 90, timer_color)
  print("MUSIC: "..(music_enabled and "ON" or "OFF"), 28, 100, music_color)
  print("HOW TO PLAY", 28, 110, tutorial_color)
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
    local TEXT_TO_BARS_GAP = 2 -- Vertical gap between text line and stash bars (1 pixel clearance)

    local STASH_BAR_WIDTH = 2 -- Width of each individual stash bar (2 pixels wide)
    local STASH_BAR_SPACING = 1 -- Horizontal space between stash bars
    local NUM_STASH_DISPLAY_COLORS = 4 -- How many stash colors to display as bars

    for i=1,player_manager.get_player_count() do
      local p = player_manager.get_player(i)
      local cur = cursors[i]
      if p then
        local s = tostr(p:get_score())
        local mode_letter = "?"
        if cur and cur.pending_type then
          if cur.pending_type == "attacker" then mode_letter = "A"
          elseif cur.pending_type == "defender" then mode_letter = "D"
          elseif cur.pending_type == "capture" then mode_letter = "C"
          end
        end
        local s_mode = s.." "..mode_letter
        local score_text_width = #s_mode * FONT_WIDTH

        -- Overlay box is 2x3 tiles = 16x24 px. We'll use 2px margin inside.
        local UI_BOX_WIDTH = 16 -- Actual width of UI box
        local anchor_x = (i==2 or i==4) and (128 - UI_BOX_WIDTH) or 0  -- Use actual width
        local anchor_y = (i>=3) and (128 - 24) or 0          -- 24px height for 3 tiles

        -- Render score and mode text
        local text_y_pos = anchor_y + 2 -- 2px margin from top
        local text_x_pos
        if i == 1 or i == 3 then -- Left-side players (P1, P3): left-align text
          text_x_pos = anchor_x + 2 -- 2px margin from left
        else -- Right-side players (P2, P4): right-align text
          text_x_pos = anchor_x + UI_BOX_WIDTH - score_text_width - 2 -- 2px margin from right
        end
        print(s_mode, text_x_pos, text_y_pos, p:get_color())

        -- Render stash bars
        local bars_area_y_start = anchor_y + FONT_HEIGHT + TEXT_TO_BARS_GAP + 1 -- Extra 1 pixel below score
        local bars_area_height = UI_BOX_SIZE - (FONT_HEIGHT + TEXT_TO_BARS_GAP + 1) -- Adjusted for extra gap
        local max_bar_height = bars_area_height - 3 -- Reserve 3px padding at top when at max

        if bars_area_height >= 1 then -- Only draw if there's space
          local total_stash_bars_width = NUM_STASH_DISPLAY_COLORS * STASH_BAR_WIDTH + (NUM_STASH_DISPLAY_COLORS - 1) * STASH_BAR_SPACING
          
          local bars_block_start_x
          if i == 1 or i == 3 then -- Left-side players: left-align bars
            bars_block_start_x = anchor_x + 1 -- 1 pixel padding from screen edge
          else -- Right-side players: right-align bars
            bars_block_start_x = anchor_x + UI_BOX_WIDTH - total_stash_bars_width - 1 -- Use correct box width
          end

          for j = 1, NUM_STASH_DISPLAY_COLORS do
            local stash_color_for_bar = player_manager.colors[j] or 0 -- Get actual color ID
            local count_in_stash = p.stash[stash_color_for_bar] or 0
            
            local bar_pixel_height = flr(count_in_stash / STASH_SIZE * max_bar_height) -- Use max_bar_height instead of bars_area_height
            bar_pixel_height = mid(0, bar_pixel_height, max_bar_height) -- Clamp to max_bar_height

            local current_bar_x = bars_block_start_x + (j - 1) * (STASH_BAR_WIDTH + STASH_BAR_SPACING)
            
            -- For players 1 and 2: bars grow downwards from top (0 is uppermost)
            -- For players 3 and 4: bars grow upwards from bottom (traditional)
            local current_bar_y_top, current_bar_y_bottom
            if i == 1 or i == 2 then
              -- Bars grow downwards: 0 is at the top, bars extend downward
              current_bar_y_top = bars_area_y_start
              current_bar_y_bottom = current_bar_y_top + bar_pixel_height - 1
            else
              -- Bars grow upwards: align to bottom of bars area
              current_bar_y_top = bars_area_y_start + (bars_area_height - bar_pixel_height)
              current_bar_y_bottom = current_bar_y_top + bar_pixel_height - 1
            end
            
            if bar_pixel_height > 0 then
              rectfill(current_bar_x, current_bar_y_top, current_bar_x + STASH_BAR_WIDTH - 1, current_bar_y_bottom, stash_color_for_bar)
            else
              -- Draw a small line for an empty stash of this color
              local empty_bar_line_y
              if i == 1 or i == 2 then
                empty_bar_line_y = bars_area_y_start -- Top for downward-growing bars
              else
                empty_bar_line_y = bars_area_y_start + bars_area_height - 1 -- Bottom for upward-growing bars
              end
              line(current_bar_x, empty_bar_line_y, current_bar_x + STASH_BAR_WIDTH - 1, empty_bar_line_y, 1) -- Dark color for empty
            end
          end
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
      local cur = cursors[pid]
      local mode_letter = "?"
      if cur and cur.pending_type then
        if cur.pending_type == "attacker" then mode_letter = "A"
        elseif cur.pending_type == "defender" then mode_letter = "D"
        elseif cur.pending_type == "capture" then mode_letter = "C"
        end
      end
      local score_text = "P" .. pid .. ": " .. p:get_score() .. " " .. mode_letter
      print(score_text, 64 - #score_text * 2, 70 + i * 8, p:get_color())
    end
    print("Press X or O to return", 28, 100, 6)
  end
end

function draw_tutorial_state()
  cls(0)
  map(0, 0, 0, 0, 16, 16,0)

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

function _draw()
  cls(0)
  -- draw_starfield() -- Assuming draw_starfield is defined elsewhere
  map(0, 0, 0, 0, 16, 16,0)
  if current_game_state == GAME_STATE_MENU then
    draw_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    draw_playing_state_elements()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    draw_gameover_state()
  elseif current_game_state == GAME_STATE_TUTORIAL then -- New state draw
    draw_tutorial_state()
  end
end
-->8
--player
local Player = {}
Player.__index = Player

function Player:new(id, initial_score, color, ghost_color)
  local instance = {
    id = id,
    score = initial_score or 0,
    color = color,
    ghost_color = ghost_color,
    stash = {},
    capture_mode = false
  }
  instance.stash[color] = STASH_SIZE or 6
  setmetatable(instance, self)
  return instance
end

function Player:get_score()
  return self.score
end

function Player:add_score(points)
  self.score = self.score + (points or 1)
end

function Player:get_color()
  return self.color
end

function Player:get_ghost_color()
  return self.ghost_color
end

function Player:is_in_capture_mode()
  return self.capture_mode
end

function Player:toggle_capture_mode()
  self.capture_mode = not self.capture_mode
end

function Player:add_captured_piece(piece_color)
  if self.stash[piece_color] == nil then
    self.stash[piece_color] = 0
  end
  self.stash[piece_color] += 1
end

function Player:get_captured_count(piece_color)
  return self.stash[piece_color] or 0
end

function Player:has_piece_in_stash(piece_color)
  return (self.stash[piece_color] or 0) > 0
end

function Player:use_piece_from_stash(piece_color)
  if self:has_piece_in_stash(piece_color) then
    self.stash[piece_color] = self.stash[piece_color] - 1
    return true
  end
  return false
end

player_manager.colors = {
  [1] = 12,
  [2] = 8,
  [3] = 11,
  [4] = 10
}

player_manager.ghost_colors = {
  [1] = 1,
  [2] = 9,
  [3] = 3,
  [4] = 4
}

player_manager.max_players = 4
player_manager.current_players = {}

function player_manager.init_players(num_players)
  if num_players < 1 or num_players > player_manager.max_players then
    return
  end

  player_manager.current_players = {}
  for i = 1, num_players do
    local color = player_manager.colors[i]
    local ghost_color = player_manager.ghost_colors[i]
    if not color then
      color = 7
    end
    if not ghost_color then
      ghost_color = 1
    end
    player_manager.current_players[i] = Player:new(i, 0, color, ghost_color)
  end
end

function player_manager.get_player(player_id)
  return player_manager.current_players[player_id]
end

function player_manager.get_player_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_color()
  else
    return 7
  end
end

function player_manager.get_player_ghost_color(player_id)
  local p_instance = player_manager.get_player(player_id)
  if p_instance then
    return p_instance:get_ghost_color()
  else
    return 1
  end
end

function player_manager.get_player_count()
  return #player_manager.current_players
end
-->8
--scoring
function reset_player_scores()
  if player_manager and player_manager.current_players then
    for _, player_obj in ipairs(player_manager.current_players) do
      if player_obj then
        player_obj.score = 0
      end
    end
  end
end

function reset_piece_states_for_scoring()
  for _, p_obj in ipairs(pieces) do
    if p_obj then
      p_obj.hits = 0
      p_obj.targeting_attackers = {}
      p_obj.dbg_target_count = nil
      -- Reset defender state to default - it will be recalculated based on actual hits
      if p_obj.type == "defender" then
        p_obj.state = "successful"
      end
    end
  end
end

function _check_attacker_hit_piece(attacker_obj, target_obj, player_manager_param, ray_segment_intersect_func, current_laser_len, add_func)
  local attacker_vertices = attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices == 0 then return end
  local apex = attacker_vertices[1]
  local dir_x = cos(attacker_obj.orientation)
  local dir_y = sin(attacker_obj.orientation)

  local target_corners = target_obj:get_draw_vertices()
  if not target_corners or #target_corners == 0 then return end

  for j = 1, #target_corners do
    local k = (j % #target_corners) + 1
    local ix, iy, t = ray_segment_intersect_func(apex.x, apex.y, dir_x, dir_y,
                                                 target_corners[j].x, target_corners[j].y,
                                                 target_corners[k].x, target_corners[k].y)
    if t and t >= 0 and t <= current_laser_len then
      target_obj.hits = (target_obj.hits or 0) + 1
      target_obj.targeting_attackers = target_obj.targeting_attackers or {}
      add_func(target_obj.targeting_attackers, attacker_obj)

      local attacker_player = player_manager_param.get_player(attacker_obj.owner_id)
      local target_player = player_manager_param.get_player(target_obj.owner_id)

      if attacker_player and target_player and attacker_obj.owner_id ~= target_obj.owner_id then
        attacker_player:add_score(1)
      end

      if target_obj.type == "defender" then
        if target_obj.hits >= 3 then
          target_obj.state = "overcharged"
        elseif target_obj.hits == 2 then
          target_obj.state = "unsuccessful"
        elseif target_obj.hits == 1 then
          target_obj.state = "successful"
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
Piece = {}
Piece.__index = Piece

Attacker = {}
Attacker.__index = Attacker
setmetatable(Attacker, {__index = Piece})

Defender = {}
Defender.__index = Defender
setmetatable(Defender, {__index = Piece})

DEFENDER_WIDTH = 8
DEFENDER_HEIGHT = 8
local ATTACKER_TRIANGLE_HEIGHT = 8
local ATTACKER_TRIANGLE_BASE = 6

local cos, sin = cos, sin
local max, min = max, min
local sqrt, abs = sqrt, abs

function Piece:new(o)
  o = o or {}
  o.position = o.position or {x=64, y=64}
  o.orientation = o.orientation or 0
  setmetatable(o, self)
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
    local owner_player = player_manager.get_player(self.owner_id)
    if owner_player then
      return owner_player:get_color()
    end
  end
  return 7
end

function Piece:get_draw_vertices()
  local o = self.orientation
  local cx = self.position.x
  local cy = self.position.y
  local local_corners = {}

  if self.type == "attacker" then
    local h = ATTACKER_TRIANGLE_HEIGHT
    local b = ATTACKER_TRIANGLE_BASE
    add(local_corners, {x = h/2, y = 0})
    add(local_corners, {x = -h/2, y = b/2})
    add(local_corners, {x = -h/2, y = -b/2})
  else
    local w, h = DEFENDER_WIDTH, DEFENDER_HEIGHT
    local hw = w / 2
    local hh = h / 2
    add(local_corners, {x = -hw, y = -hh})
    add(local_corners, {x = hw, y = -hh})
    add(local_corners, {x = hw, y = hh})
    add(local_corners, {x = -hw, y = hh})
  end

  local world_corners = {}
  for lc in all(local_corners) do
    local rotated_x = lc.x * cos(o) - lc.y * sin(o)
    local rotated_y = lc.x * sin(o) + lc.y * cos(o)
    add(world_corners, {x = cx + rotated_x, y = cy + rotated_y})
  end
  return world_corners
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

  local vertices = self:get_draw_vertices()
  if not vertices or #vertices == 0 then return end
  local apex = vertices[1]

  local dir_x = cos(self.orientation)
  local dir_y = sin(self.orientation)
  local laser_color = self:get_color()
  local laser_end_x = apex.x + dir_x * LASER_LEN
  local laser_end_y = apex.y + dir_y * LASER_LEN
  local closest_hit_t = LASER_LEN

  local hit_piece_state = nil
  local hit_piece_type = nil

  if pieces then
    for _, other_piece in ipairs(pieces) do
      if other_piece ~= self then
        local piece_corners = other_piece:get_draw_vertices()
        for j = 1, #piece_corners do
          local k = (j % #piece_corners) + 1
          local ix, iy, t = ray_segment_intersect(
            apex.x, apex.y, dir_x, dir_y,
            piece_corners[j].x, piece_corners[j].y, piece_corners[k].x, piece_corners[k].y
          )
          if t and t >= 0 and t < closest_hit_t then
            closest_hit_t = t
            laser_end_x = ix
            laser_end_y = iy
            hit_piece_state = other_piece.state
            hit_piece_type = other_piece.type
          end
        end
      end
    end
  end

  if hit_piece_state == "unsuccessful" then
    laser_color = 8
  elseif hit_piece_state == "overcharged" then
    laser_color = 10
  end

  local ant_spacing = 4
  local ant_length = 2
  local num_ants = flr(closest_hit_t / ant_spacing)
  local time_factor = time() * 20

  for i = 0, num_ants - 1 do
    local ant_start_t = (i * ant_spacing + time_factor) % closest_hit_t
    local ant_end_t = ant_start_t + ant_length
    
    if ant_end_t <= closest_hit_t then
      local ant_start_x = apex.x + dir_x * ant_start_t
      local ant_start_y = apex.y + dir_y * ant_start_t
      local ant_end_x = apex.x + dir_x * ant_end_t
      local ant_end_y = apex.y + dir_y * ant_end_t
      line(ant_start_x, ant_start_y, ant_end_x, ant_end_y, laser_color)
    else
      local segment1_end_t = closest_hit_t
      local segment1_start_x = apex.x + dir_x * ant_start_t
      local segment1_start_y = apex.y + dir_y * ant_start_t
      local segment1_end_x = apex.x + dir_x * segment1_end_t
      local segment1_end_y = apex.y + dir_y * segment1_end_t
      line(segment1_start_x, segment1_start_y, segment1_end_x, segment1_end_y, laser_color)
      
      local segment2_len = ant_end_t - closest_hit_t
      if segment2_len > 0 then
        local segment2_start_x = apex.x
        local segment2_start_y = apex.y
        local segment2_end_x = apex.x + dir_x * segment2_len
        local segment2_end_y = apex.y + dir_y * segment2_len
        line(segment2_start_x, segment2_start_y, segment2_end_x, segment2_end_y, laser_color)
      end
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
  local vertices = self:get_draw_vertices()
  local color = self:get_color()
  if #vertices == 4 then
    line(vertices[1].x, vertices[1].y, vertices[2].x, vertices[2].y, color)
    line(vertices[2].x, vertices[2].y, vertices[3].x, vertices[3].y, color)
    line(vertices[3].x, vertices[3].y, vertices[4].x, vertices[4].y, color)
    line(vertices[4].x, vertices[4].y, vertices[1].x, vertices[1].y, color)
  end

  -- draw status indicator in the center
  local cx = self.position.x
  local cy = self.position.y
  local status_col
  if self.state == "successful" then
    status_col = 11 -- green
  elseif self.state == "unsuccessful" then
    status_col = 8 -- red
  elseif self.state == "overcharged" then
    status_col = 13 -- purple
  else
    status_col = 5 -- neutral/gray if state is missing
  end
  circfill(cx, cy, 2, status_col)
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
  local ui_zones = {
    {x1=0, y1=0, x2=15, y2=23},    -- Top left: 2x3 tiles
    {x1=112, y1=0, x2=127, y2=23}, -- Top right: 2x3 tiles  
    {x1=0, y1=104, x2=15, y2=127}, -- Bottom left: 2x3 tiles
    {x1=112, y1=104, x2=127, y2=127} -- Bottom right: 2x3 tiles
  }

  local bw, bh = 128, 128
  local temp_piece_obj = create_piece(piece_params)
  if not temp_piece_obj then return false end

  local function vec_sub(a, b) return {x = a.x - b.x, y = a.y - b.y} end
  local function vec_dot(a, b) return a.x * b.x + a.y * b.y end
  local function project(vs, ax)
    if not vs or #vs == 0 then return 0,0 end
    local mn, mx = vec_dot(vs[1], ax), vec_dot(vs[1], ax)
    for i = 2, #vs do
      local pr = vec_dot(vs[i], ax)
      mn, mx = min(mn, pr), max(mx, pr)
    end
    return mn, mx
  end
  local function get_axes(vs)
    local ua = {}
    if not vs or #vs < 2 then return ua end
    for i = 1, #vs do
      local p1 = vs[i]
      local p2 = vs[(i % #vs) + 1]
      local e = vec_sub(p2, p1)
      local n = {x = -e.y, y = e.x}
      local l = sqrt(n.x^2 + n.y^2)
      if l > 0.0001 then
        n.x, n.y = n.x / l, n.y / l
        local uniq = true
        for ea in all(ua) do if abs(vec_dot(ea, n)) > 0.999 then uniq = false; break end end
        if uniq then add(ua, n) end
      end
    end
    return ua
  end

  local corners = temp_piece_obj:get_draw_vertices()
  if not corners or #corners == 0 then return false end
  for c in all(corners) do
    if c.x < 0 or c.x > bw or c.y < 0 or c.y > bh then return false end
    for z in all(ui_zones) do
      if c.x >= z.x1 and c.x <= z.x2 and c.y >= z.y1 and c.y <= z.y2 then
        return false
      end
    end
  end

  for _, ep_obj in ipairs(pieces) do
    local ep_corners = ep_obj:get_draw_vertices()
    if not ep_corners or #ep_corners == 0 then goto next_ep_check end

    local combined_axes = {}
    for ax_piece in all(get_axes(corners)) do add(combined_axes, ax_piece) end
    for ax_ep in all(get_axes(ep_corners)) do add(combined_axes, ax_ep) end
    
    if #combined_axes == 0 then
        local min_x1, max_x1, min_y1, max_y1 = bw, 0, bh, 0
        for c in all(corners) do min_x1=min(min_x1,c.x) max_x1=max(max_x1,c.x) min_y1=min(min_y1,c.y) max_y1=max(max_y1,c.y) end
        local min_x2, max_x2, min_y2, max_y2 = bw, 0, bh, 0
        for c in all(ep_corners) do min_x2=min(min_x2,c.x) max_x2=max(max_x2,c.x) min_y2=min(min_y2,c.y) max_y2=max(max_y2,c.y) end
        if not (max_x1 < min_x2 or max_x2 < min_x1 or max_y1 < min_y2 or max_y2 < min_y1) then
            return false 
        end
        goto next_ep_check 
    end

    local collision_with_ep = true
    for ax in all(combined_axes) do
      local min1, max1 = project(corners, ax)
      local min2, max2 = project(ep_corners, ax)
      if max1 < min2 or max2 < min1 then
        collision_with_ep = false
        break
      end
    end
    if collision_with_ep then return false end
    ::next_ep_check::
  end

  if piece_params.type == "attacker" then
    local apex = corners[1]
    local dir_x = cos(piece_params.orientation)
    local dir_y = sin(piece_params.orientation)
    local laser_hits_defender = false
    for _, ep_obj in ipairs(pieces) do
      if ep_obj.type == "defender" then
        local def_corners = ep_obj:get_draw_vertices()
        if not def_corners or #def_corners == 0 then goto next_laser_target_check end
        for j = 1, #def_corners do
          local k = (j % #def_corners) + 1
          local ix, iy, t = ray_segment_intersect(
            apex.x, apex.y, dir_x, dir_y,
            def_corners[j].x, def_corners[j].y, def_corners[k].x, def_corners[k].y
          )
          if t and t >= 0 and t <= LASER_LEN then
            laser_hits_defender = true
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

function place_piece(piece_params, player_obj)
  if legal_placement(piece_params) then
    local piece_color_to_place = piece_params.color

    if piece_color_to_place == nil then
      return false
    end
    
    if player_obj:use_piece_from_stash(piece_color_to_place) then
      local new_piece_obj = create_piece(piece_params) 
      if new_piece_obj then
        add(pieces, new_piece_obj)
        -- play defender or attacker placement sfx
        if piece_params.type == "defender" and effects and effects.defender_placement then
          sfx(effects.defender_placement)
        elseif piece_params.type == "attacker" and effects and effects.attacker_placement then
          sfx(effects.attacker_placement)
        end
        score_pieces()
        return true
      else
        player_obj:add_captured_piece(piece_color_to_place)
        return false
      end
    else
      -- Player doesn't have this color in stash
      printh("P"..player_obj.id.." doesn't have color "..piece_color_to_place.." in stash")
      if effects and effects.bad_placement then
        sfx(effects.bad_placement)
      end
      return false
    end
  else
    printh("Placement not legal for P"..player_obj.id)
    -- Play bad placement sound effect
    if effects and effects.bad_placement then
      sfx(effects.bad_placement)
    end
    return false
  end
end
-->8
-- Converted Controls Module for Multi-Cursor Support
-- Handles player input and updates control-related game state for each cursor.
--#globals player_manager cursors place_piece attempt_capture original_update_game_logic_func pieces
--#globals max min btn btnp
-- Constants for control states (optional)
local CSTATE_MOVE_SELECT = 0
local CSTATE_ROTATE_PLACE = 1
local CSTATE_COOLDOWN = 2

function update_controls()
  local cursor_speed = 2        -- pixels per frame; adjust as needed
  local rotation_speed = 0.02   -- rotation amount per frame; adjust

  -- Iterate through each player's cursor in the global 'cursors' table.
  for i, cur in ipairs(cursors) do
    local current_player_obj = player_manager.get_player(i)


    if not current_player_obj then goto next_cursor_ctrl end

    -- Determine Player Status and Forced Action State
    local player_has_empty_stash = true
    if current_player_obj and current_player_obj.stash then
      for _color_id, count in pairs(current_player_obj.stash) do
        if count > 0 then
          player_has_empty_stash = false
          break -- Found a piece, stash is not empty
        end
      end
    else
      -- If current_player_obj is nil or stash is nil, it's effectively empty for this check
      player_has_empty_stash = true
    end

    local player_has_successful_defender = false
    if pieces then -- Ensure pieces table exists
      for piece_idx, p_obj in pairs(pieces) do -- Changed to pairs to get index for print

        if p_obj.owner_id == i and p_obj.type == "defender" and p_obj.state == "successful" then
          player_has_successful_defender = true
          break
        end
      end
    end

    local forced_action_state = "normal" -- "normal", "capture_only", "must_place_defender"

    if player_has_empty_stash then
      cur.pending_type = "capture"
      forced_action_state = "capture_only"
    elseif not player_has_successful_defender then
      cur.pending_type = "defender"
      cur.pending_color = current_player_obj:get_color()
      forced_action_state = "must_place_defender"
    end

    -- Handle player cycling piece/action type if in normal state and CSTATE_MOVE_SELECT
    if cur.control_state == CSTATE_MOVE_SELECT and btnp(🅾️, i - 1) and forced_action_state == "normal" then
        local current_orientation = cur.pending_orientation
        if cur.pending_type == "defender" then
            cur.pending_type = "attacker"
        elseif cur.pending_type == "attacker" then
            cur.pending_type = "capture"
        elseif cur.pending_type == "capture" then
            cur.pending_type = "defender"
        end
        cur.pending_orientation = current_orientation
        -- play switch mode sfx
        if effects and effects.switch_mode then
          sfx(effects.switch_mode)
        end
    end

    -- Set player's capture_mode based on the FINAL cur.pending_type for this frame
    if current_player_obj then
        current_player_obj.capture_mode = (cur.pending_type == "capture")
    end

    if cur.control_state == CSTATE_MOVE_SELECT then
      -- Continuous movement with the d-pad.
      if btn(⬅️, i - 1) then cur.x = max(0, cur.x - cursor_speed) end
      if btn(➡️, i - 1) then cur.x = min(cur.x + cursor_speed, 128 - 8) end
      if btn(⬆️, i - 1) then cur.y = max(0, cur.y - cursor_speed) end
      if btn(⬇️, i - 1) then cur.y = min(cur.y + cursor_speed, 128 - 8) end

      -- Initiate placement/rotation/capture with Button X.
      if btnp(❎, i - 1) then
        if cur.pending_type == "capture" then -- If pending type is capture (either forced or selected)
          if attempt_capture(current_player_obj, cur) then
            cur.control_state = CSTATE_COOLDOWN; cur.return_cooldown = 6
            if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate immediately
          end
        else -- pending_type is "defender" or "attacker"
          cur.control_state = CSTATE_ROTATE_PLACE
          -- play enter rotation sfx
          if effects and effects.enter_rotation then
            sfx(effects.enter_rotation)
          end
          -- Orientation and color will be handled in CSTATE_ROTATE_PLACE
          -- No longer resetting orientation when starting placement
        end
      end


    elseif cur.control_state == CSTATE_ROTATE_PLACE then
      local available_colors = {}
      if forced_action_state == "must_place_defender" then
        -- Only player's own color is available
        add(available_colors, current_player_obj:get_color())
        cur.color_select_idx = 1 -- Ensure it's selected
      else
        -- Gather available colors in stash (player's own and captured)
        if current_player_obj and current_player_obj.stash then -- Ensure player and stash exist
          for color, count in pairs(current_player_obj.stash) do
            if count > 0 then add(available_colors, color) end
          end
        end
      end
      
      -- If no colors were added (e.g., stash is completely empty, which shouldn't happen if forced_action_state isn's capture_only),
      -- or if in a state where only own color is allowed but not present (edge case).
      -- Fallback to player's own color if available_colors is still empty.
      -- This handles the scenario where a player might have 0 of their own color but prisoners.
      if #available_colors == 0 and current_player_obj and current_player_obj:has_piece_in_stash(current_player_obj:get_color()) then
         add(available_colors, current_player_obj:get_color())
      elseif #available_colors == 0 then
        -- If truly no pieces are placeable (e.g. empty stash and not forced to place defender)
        -- this situation should ideally be handled by `forced_action_state` pushing to "capture_only"
        -- or preventing entry into CSTATE_ROTATE_PLACE.
        -- For safety, if we reach here with no available colors, revert to move/select.
        cur.control_state = CSTATE_MOVE_SELECT
        goto next_cursor_ctrl -- Skip further processing for this cursor this frame
      end

      -- Clamp color_select_idx
      if cur.color_select_idx > #available_colors then cur.color_select_idx = 1 end
      if cur.color_select_idx < 1 then cur.color_select_idx = #available_colors end

      -- Cycle color selection with up/down
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

      -- Set pending_color to selected color
      if forced_action_state == "must_place_defender" then
        cur.pending_color = current_player_obj:get_color()
      else
        -- Ensure available_colors has entries before trying to access
        if #available_colors > 0 then
            cur.pending_color = available_colors[cur.color_select_idx] or current_player_obj:get_ghost_color() -- Fallback to ghost color
        else
            -- This case should ideally be prevented by earlier checks.
            -- If somehow reached, use player's ghost color as a safe default.
            cur.pending_color = current_player_obj:get_ghost_color() 
        end
      end

      -- Confirm placement with Button X.
      if btnp(❎, i - 1) then
        local piece_params = {
          owner_id = i, -- Use player index as owner_id
          type = cur.pending_type,
          position = { x = cur.x + 4, y = cur.y + 4 },
          orientation = cur.pending_orientation,
          color = cur.pending_color -- Add the selected color to piece_params
        }
        if place_piece(piece_params, current_player_obj) then
          cur.control_state = CSTATE_COOLDOWN
          cur.return_cooldown = 6  -- 6-frame cooldown after placement
          if original_update_game_logic_func then original_update_game_logic_func() end -- Recalculate board state
        end
      end


      -- Cancel placement with Button O.
      if btnp(🅾️, i - 1) then
        cur.control_state = CSTATE_MOVE_SELECT
        -- play exit rotation sfx
        if effects and effects.exit_rotation then
          sfx(effects.exit_rotation)
        end
      end

    elseif cur.control_state == CSTATE_COOLDOWN then
      -- Decrement cooldown timer and snap cursor back to spawn when done.
      cur.return_cooldown = cur.return_cooldown - 1
      if cur.return_cooldown <= 0 then
        cur.x = cur.spawn_x
        cur.y = cur.spawn_y
        cur.control_state = CSTATE_MOVE_SELECT
        -- The status checks at the start of CSTATE_MOVE_SELECT will handle pending_type and pending_color
        -- So, we can reset to a sensible default or leave as is,
        -- as it will be overridden if a forced state is active.
        cur.pending_type = "defender" -- Default, will be overridden if needed
        cur.pending_color = (current_player_obj and current_player_obj:get_ghost_color()) or 7
      end
    end
    ::next_cursor_ctrl::
  end
end
-->8
--cursor
local default_cursor_props={
  control_state=0,
  pending_type="defender",
  pending_orientation=0.25, -- Start with a useful default angle
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
      local current_player
      if player_manager and player_manager.get_player then
        current_player = player_manager.get_player(self.id)
        if current_player and current_player.get_color then
          cursor_color=current_player:get_color()
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

      -- Draw purple circles around capturable ships if in capture mode
      if current_player and current_player:is_in_capture_mode() then
        if pieces then
          local found_overcharged_defender_for_player = false
          for _, my_piece in ipairs(pieces) do
            -- Condition 1: Is it MY piece, is it a DEFENDER, and is it OVERCHARGED?
            if my_piece.owner_id == self.id and my_piece.type == "defender" and my_piece.state == "overcharged" then
              found_overcharged_defender_for_player = true
              
              if my_piece.targeting_attackers and #my_piece.targeting_attackers > 0 then
                for _, attacker_to_capture in ipairs(my_piece.targeting_attackers) do
                  if attacker_to_capture and attacker_to_capture.position then
                    -- Condition 2: Is the targeting piece an ATTACKER? (Owner doesn't matter for highlighting)
                    if attacker_to_capture.type == "attacker" then -- Removed owner check attacker_to_capture.owner_id ~= self.id
                      local piece_pos = attacker_to_capture.position
                      local radius = 5 -- Attackers are triangles, 5 should be a decent radius
                      circ(piece_pos.x, piece_pos.y, radius, 14) -- Pico-8 color 14 is purple
                    end
                  end
                end
              end
            end
          end
        end
      else
        if current_player and not current_player:is_in_capture_mode() then
           -- This log can be very spammy, enable if specifically debugging capture mode toggle
        end
      end
    end
  }
  return cur
end
__gfx__
000000007777777777777777777777770000000000eeee0000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000007666666666666666666666670000000b0e0000e000000000000000000000000000000000000000000000000000000000000000000000000100000000
00000000761111111111111111111167000000bbe000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000076111111111111111111116700000bb0e000000e000000000000000000000000000000000000000000000000000037000000000000d0000000006600
00000000761111111111111111111167bb00bb00e000000e00000000000000000000000000000000000000000000000000000300005000000010000000000600
000000007611111111111111111111670bbbb000e000000e00000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000076111111111111111111116700bb00000e0000e000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000007611111111111111111111670000000000eeee0000000000000000000000000000000000000000000000000000000000000000500000000000000000
000000007611111111111111111111670080000800eeee0000000000000000000000000000000000000000000000000000000000000000555555555000000000
00000000761111111111111111111167008800880e0000e000000000000000000000000000000000000000000000000000000000000055111111111550020000
0000000076111111111111111111116700088880edd0000e00000000000000000000000000000000000000000000000000000000005511111111115515500000
0000000076111111111111111111116700008800edddd00e00000000000000000000000000000000000000000000000000000000551111111111222511155000
0000000076111111111111111111116700088880e00ddd0e00000000000000000000000000000000000000000000000000000005111111112222555511111500
0000000076111111111111111111116700880088e0ddddde00000000000000000000000000000000000000000000000000000051111555522555555111221150
00000000761111111111111111111167008000080edddde000000000000000000000000000000000000000000000000000000511111552255555555522211115
000000007611111111111111111111670000000000eeee0000000000000000000000000000000000000000000000000000005111111222222222255241112211
000000007611111111111111111111670000000000eeee000000000000000000000000000000000000000000000000000000511ee11122111155555441222211
00000000761111111111111111111167000000000e6666e000000000000000000000000000000000000000222220000000051111eee225555555554442222551
0000000076111111111111111111116700000000eee0006e00000000000000000000000000000000000022555552200000051111122555552255444122222551
0000000076111111111111111111116700000000eeeee06e00000000000000000000000000000000000255555225520000051111225522222444112255225551
0000000076111111111111111111116700000000e66eee6e00000000000000000000000000000000002522222255552000511152222214222111155552255551
0000000076111111111111111111116700000000e6eeeeee0000000000000000000000000000000000255c555555552000511155555122122255522225555511
00000000766666666666666666666667000000000eeeeee00000000000000000000000000000000002555555222555c200511155555555555522222255555ee1
000000007777777777777777777777770000000000eeee00000000000000000000000000000000000255222225555252005155111555555555555555555ee111
000000001111116776111111111111110000000000eeee0000000000000000000000000000000000025555555332225200515511111111222222221581115555
00000000111111677611111111111111000000000e7777e000000000000000000000000000000000025335c52222555200515555111111222221115111555255
0000000015111167761115111111111100000000eff6667e0000000000000000000000000000000002553222225c555200515555551111111115555555552211
000000001d51116776115d111111111100000000effff67e00000000000000000000000000000000002552555555552000511155555528222552555552222111
0000000011111167761111111111d11100000000e77fff7e00000000000000000000000000000000002555555555252000051111552255555555555222221111
000000001111116776111111111d111100000000e77ffffe0000000000000000000000000000000000025ee52222220000051111111155225555511111111eee
00000000111111677611111111111111000000000effffe0000000000000000000000000000000000000222255522000000511112555211111118111111eee11
000000001111116776111111111111110000000000eeee0000000000000000000000000000000000000000222220000000005111111111111111111111111111
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

