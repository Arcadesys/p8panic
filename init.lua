-- Game state structure for Pyramid Panic
-- luacheck: globals cls btn btnp tri rect add all max min
gamestate = {
    players = {
        [1] = {
            score = 0,
            pieces_remaining = 6,
            has_defender = false,
            defender_loss_timer = 0, -- timer for 10 second rule
            is_eliminated = false
        },
        [2] = { score = 0, pieces_remaining = 6, has_defender = false, defender_loss_timer = 0, is_eliminated = false },
        [3] = { score = 0, pieces_remaining = 6, has_defender = false, defender_loss_timer = 0, is_eliminated = false },
        [4] = { score = 0, pieces_remaining = 6, has_defender = false, defender_loss_timer = 0, is_eliminated = false }
    },
    
    current_player = 1,
    game_timer = 180, -- 3 minutes in seconds
    game_active = true,
    end_game_timer = 0, -- for 5 second hold to end early
    
    cursor_modes = {
        attacker = 1,
        defender = 2,
        capture = 3
    },
    current_cursor_mode = 2, -- start with defender mode
    
    board_size = { width = 128, height = 128 }, -- adjust as needed
}

-- Your existing piece structure is good but needs type clarification
piece = {
    owner = 0, -- owner of the piece, player 1-4
    type = "defender", -- "attacker" or "defender" 
    position = { x = 0, y = 0 },
    orientation = 0, -- for attackers: 0-3 (0 = up, 1 = right, 2 = down, 3 = left)
}

pieces = {} -- array to hold all placed pieces

-- player 1 cursor
cursor = { x = gamestate.board_size.width//2 - 4, y = gamestate.board_size.height//2 - 4 }

function _init()
    cls()                     -- clear to black
    pieces = {}               -- reset any placed pieces
    gamestate.game_timer = 180
    cursor.x = gamestate.board_size.width//2 - 4
    cursor.y = gamestate.board_size.height//2 - 4
end

function _update60()
    -- move cursor with dpad, clamped to screen
    if btn(0) then cursor.x = max(cursor.x-1, 0) end
    if btn(1) then cursor.x = min(cursor.x+1, gamestate.board_size.width-8) end
    if btn(2) then cursor.y = max(cursor.y-1, 0) end
    if btn(3) then cursor.y = min(cursor.y+1, gamestate.board_size.height-8) end

    -- place a defender pyramid
    if btnp(4) then
        add(pieces, {
            owner       = 1,
            type        = "defender",
            position    = { x = cursor.x, y = cursor.y },
            orientation = 0
        })
    end
end

function _draw()
    cls(0)  -- fill black

    -- draw all defenders as white triangles (8px base, 8px height)
    for p in all(pieces) do
        if p.type == "defender" then
            local x,y = p.position.x, p.position.y
            tri(x,   y,
                x+8, y,
                x+4, y-8,
                7)
        end
    end

    -- draw P1 cursor as white 8×8 outline
    rect(cursor.x, cursor.y,
         cursor.x+7, cursor.y+7,
         7)
end