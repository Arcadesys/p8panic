--p8panic
--A game of tactical geometry.

-- luacheck: globals cls btn btnp rect rectfill add all max min
cursor_x=64-4
cursor_y=64-4
pieces={}

-- delegate all input/interaction to controls.lua
function _update()
  update_controls()
end

function _draw()
  cls(0)
  -- draw defenders
  for p in all(pieces) do
    if p.type=="defender" then
      local x=p.position.x
      local y=p.position.y
        -- draw a defender as a white square
      rect(x, y, x+7, y+7, 7)
    end
  end
  -- draw cursor outline
  rect(cursor_x,cursor_y,cursor_x+7,cursor_y+7,7)
end
