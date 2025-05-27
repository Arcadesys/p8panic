function legal_placement(piece_to_place)
    -- Configuration for placement logic (adjust if necessary)
    local piece_width = 8
    local piece_height = 8
    local board_w = 128 -- Assuming 128x128 board
    local board_h = 128

    -- Helper: Vector subtraction v1 - v2
    function vec_sub(v1, v2)
        return {x = v1.x - v2.x, y = v1.y - v2.y}
    end

    -- Helper: Vector dot product
    function vec_dot(v1, v2)
        return v1.x * v2.x + v1.y * v2.y
    end

    -- Helper: Get the world-space coordinates of a piece's corners
    function get_rotated_vertices(piece)
        local w, h = piece_width, piece_height -- Or from piece.type if dynamic
        local x, y = piece.position.x, piece.position.y
        local o = piece.orientation -- PICO-8 orientation (0-1)

        -- Center of the piece
        local cx = x + w / 2
        local cy = y + h / 2

        -- Half-width and half-height
        local hw = w / 2
        local hh = h / 2

        -- Local corner coordinates (relative to center, before rotation)
        -- Order: top-left, top-right, bottom-right, bottom-left
        local local_corners = {
            {x = -hw, y = -hh}, {x = hw, y = -hh},
            {x = hw, y = hh},   {x = -hw, y = hh}
        }

        local world_corners = {}
        for lc in all(local_corners) do
            -- PICO-8 cos/sin use 0..1 for angle
            local rotated_x = lc.x * cos(o) - lc.y * sin(o)
            local rotated_y = lc.x * sin(o) + lc.y * cos(o)
            add(world_corners, {x = cx + rotated_x, y = cy + rotated_y})
        end
        return world_corners
    end

    -- Helper: Project vertices onto an axis and return min/max projection
    function project_vertices(vertices, axis)
        local min_proj = vec_dot(vertices[1], axis)
        local max_proj = min_proj
        for i = 2, #vertices do
            local proj = vec_dot(vertices[i], axis)
            if proj < min_proj then min_proj = proj
            elseif proj > max_proj then max_proj = proj
            end
        end
        return min_proj, max_proj
    end

    -- Helper: Check for Oriented Bounding Box (OBB) collision using Separating Axis Theorem (SAT)
    function check_obb_collision(piece1, piece2)
        local vertices1 = get_rotated_vertices(piece1)
        local vertices2 = get_rotated_vertices(piece2)

        local axes = {}
        -- Axes from piece1 (normals to edges)
        -- Edge from v1 to v2: (v2.x - v1.x, v2.y - v1.y)
        -- Normal: (-(v2.y - v1.y), v2.x - v1.x)
        local edge1_1 = vec_sub(vertices1[2], vertices1[1])
        add(axes, {x = -edge1_1.y, y = edge1_1.x}) -- Normal to first edge
        local edge1_2 = vec_sub(vertices1[4], vertices1[1]) -- Use adjacent edge for the other normal
        add(axes, {x = -edge1_2.y, y = edge1_2.x}) -- Normal to second edge

        -- Axes from piece2
        local edge2_1 = vec_sub(vertices2[2], vertices2[1])
        add(axes, {x = -edge2_1.y, y = edge2_1.x})
        local edge2_2 = vec_sub(vertices2[4], vertices2[1])
        add(axes, {x = -edge2_2.y, y = edge2_2.x})

        for axis in all(axes) do
            -- Normalize axis (optional for SAT, but good for consistency if using penetration depth)
            -- local len = sqrt(axis.x^2 + axis.y^2)
            -- if len > 0 then axis.x /= len; axis.y /= len end

            local min1, max1 = project_vertices(vertices1, axis)
            local min2, max2 = project_vertices(vertices2, axis)

            -- Check for non-overlap
            if max1 < min2 or max2 < min1 then
                return false -- Separating axis found, no collision
            end
        end
        return true -- No separating axis found, collision
    end

    -- 1. Boundary Check: Ensure all corners of the piece are within board limits
    local world_corners = get_rotated_vertices(piece_to_place)
    for corner in all(world_corners) do
        if corner.x < 0 or corner.x > board_w or
           corner.y < 0 or corner.y > board_h then
            -- flr.print("Boundary fail: x="..corner.x.." y="..corner.y,0,0,7) -- Debug
            return false -- Piece is out of bounds
        end
    end

    -- 2. Intersection Check: Ensure the piece doesn't collide with existing pieces
    -- 'pieces' is assumed to be a global table of already placed pieces
    if pieces then -- Check if the 'pieces' table exists and has items
        for existing_piece in all(pieces) do
            -- No need to check piece_to_place against itself if it were already in 'pieces',
            -- but for a new placement, it won't be.
            if check_obb_collision(piece_to_place, existing_piece) then
                -- flr.print("Collision fail",0,8,7) -- Debug
                return false -- Collides with an existing piece
            end
        end
    end

    return true -- Placement is legal
end

function redraw_lasers()
    --when we place a new piece, we need to recalculate the score.
end

function place_piece(piece)
    if legal_placement(piece) then
        add(pieces, piece)
        redraw_lasers()
    end
end