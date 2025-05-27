--cursor.lua

handles cursor movement, mode changes, and piece selection
local cursor = {
    position = { x = 0, y = 0 },
    mode = "defender", -- "attacker", "defender", or "capture"
    selected_piece = nil
}