-- src/5.menu.lua

menu_active = true
selected_players = 3 -- Default to 3 players
min_players = 3
max_players = 4

selected_stash_size = 6 -- Default to 6
min_stash_size = 3
max_stash_size = 10

menu_options = {
  {text = "Players", value_key = "selected_players", min_val = min_players, max_val = max_players},
  {text = "Stash Size", value_key = "selected_stash_size", min_val = min_stash_size, max_val = max_stash_size},
  {text = "Start Game"}
}
current_menu_selection_index = 1 -- 1-based index

function _update_menu_controls()
  if not menu_active then return end

  local option_changed = false

  -- Navigate menu options (using player 0 controls: d-pad buttons 2 for up, 3 for down)
  if btnp(2) then -- Up
    current_menu_selection_index = current_menu_selection_index - 1
    if current_menu_selection_index < 1 then
      current_menu_selection_index = #menu_options
    end
  elseif btnp(3) then -- Down
    current_menu_selection_index = current_menu_selection_index + 1
    if current_menu_selection_index > #menu_options then
      current_menu_selection_index = 1
    end
  end

  local current_option = menu_options[current_menu_selection_index]

  -- Change option values or start game
  if current_option.value_key then -- This option has a value to change (Players or Stash Size)
    local current_value_for_option
    if current_option.value_key == "selected_players" then
      current_value_for_option = selected_players
    elseif current_option.value_key == "selected_stash_size" then
      current_value_for_option = selected_stash_size
    end

    -- Use d-pad buttons 0 for left, 1 for right
    if btnp(0) then -- Left
      current_value_for_option = current_value_for_option - 1
      if current_value_for_option < current_option.min_val then
        current_value_for_option = current_option.min_val
      end
      option_changed = true
    elseif btnp(1) then -- Right
      current_value_for_option = current_value_for_option + 1
      if current_value_for_option > current_option.max_val then
        current_value_for_option = current_option.max_val
      end
      option_changed = true
    end

    if option_changed then
      if current_option.value_key == "selected_players" then
        selected_players = current_value_for_option
      elseif current_option.value_key == "selected_stash_size" then
        selected_stash_size = current_value_for_option
      end
    end
  elseif current_option.text == "Start Game" then -- This is the "Start Game" option
    -- Use action buttons 4 (O) or 5 (X)
    if btnp(4) or btnp(5) then
      menu_active = false
      -- Game will start on the next frame because menu_active is false.
      -- Game initialization logic (e.g. creating cursors)
      -- will need to read selected_players and selected_stash_size.
    end
  end
end

function _draw_main_menu()
  if not menu_active then return end

  cls(1) -- Dark blue background (PICO-8 color 1)

  -- Title
  print("p8panic", 48, 10, 7) -- White text (PICO-8 color 7)

  local menu_start_y = 30
  local line_height = 10

  for i, option in ipairs(menu_options) do
    local color = 7 -- Default color: White
    local prefix = "  "
    if i == current_menu_selection_index then
      color = 8 -- Highlight color: Red (PICO-8 color 8)
      prefix = "> "
    end

    local text_to_draw = prefix .. option.text
    if option.value_key then
      local value_display
      if option.value_key == "selected_players" then
        value_display = selected_players
      elseif option.value_key == "selected_stash_size" then
        value_display = selected_stash_size
      end
      text_to_draw = text_to_draw .. ": < " .. value_display .. " >"
    end

    print(text_to_draw, 20, menu_start_y + (i-1)*line_height, color)
  end

  -- Instructions
  local instruction_y = 100
  print("use d-pad to navigate", 10, instruction_y, 6)       -- Light grey (PICO-8 color 6)
  print("left/right to change", 10, instruction_y + 8, 6)
  print("o/x to start", 10, instruction_y + 16, 6)
end
