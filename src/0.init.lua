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

function finish_game_menuitem()
  if current_game_state == GAME_STATE_PLAYING then
    if score_pieces then score_pieces() end
    current_game_state = GAME_STATE_GAMEOVER
    GAME_TIMER = 0
    gameover_timer = 2
    -- play gameover sound and start music fade
    sfx(effects.gameover_timer)
    gameover_music_fade_start = true
  end
end

gameover_timer = 2
gameover_music_fade_start = false

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
    draw_menu_state()
  elseif current_game_state == GAME_STATE_PLAYING then
    map(0, 0, 0, 0, 16, 16)
    draw_playing_state_elements()
  elseif current_game_state == GAME_STATE_GAMEOVER then
    draw_gameover_state() -- This function handles its own map drawing
  elseif current_game_state == GAME_STATE_TUTORIAL then -- New state draw
    draw_tutorial_state() -- This function handles its own map drawing
  end
end
