-- luacheck: globals pieces add all cos sin sqrt abs

function legal_placement(piece_to_place)
    -- Configuration for placement logic
    local defender_width = 8
    local defender_height = 8
    local attacker_triangle_height = 8
    local attacker_triangle_base = 6
    local board_w = 128
    local board_h = 128
    local laser_length = board_w -- Define laser length

    -- Helper: Vector subtraction v1 - v2
    local function vec_sub(v1, v2)
        return {x = v1.x - v2.x, y = v1.y - v2.y}
    end

    -- Helper: Vector dot product
    local function vec_dot(v1, v2)
        return v1.x * v2.x + v1.y * v2.y
    end

    -- Helper: Vector normalization
    local function vec_normalize(v)
        local len = sqrt(v.x^2 + v.y^2)
        if len > 0.0001 then
            return {x = v.x / len, y = v.y / len}
        else
            return {x = 0, y = 0} -- Return zero vector if length is very small
        end
    end

    -- Helper: Distance squared between two points
    local function vec_dist_sq(p1, p2)
        local dx = p1.x - p2.x
        local dy = p1.y - p2.y
        return dx*dx + dy*dy
    end

    -- Helper: Get the world-space coordinates of a piece's corners
    local function get_rotated_vertices(piece)
        local o = piece.orientation
        local cx = piece.position.x
        local cy = piece.position.y
        local local_corners = {}

        if piece.type == "attacker" then
            local h = attacker_triangle_height
            local b = attacker_triangle_base
            add(local_corners, {x = h/2, y = 0})      -- Apex
            add(local_corners, {x = -h/2, y = b/2})   -- Base corner 1
            add(local_corners, {x = -h/2, y = -b/2})  -- Base corner 2
        else -- Defender (square)
            local w, h = defender_width, defender_height
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

    -- Helper: Project vertices onto an axis and return min/max projection
    local function project_vertices(vertices, axis)
        if not vertices or #vertices == 0 then 
            return 0,0 -- Should not happen with valid shapes/segments
        end
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

    -- Helper to get unique normalized axes perpendicular to edges for a shape
    local function get_axes_for_shape(shape_vertices)
        local unique_axes = {}
        local num_shape_verts = #shape_vertices
        if num_shape_verts < 2 then return unique_axes end

        for i_vert = 1, num_shape_verts do
            local p1 = shape_vertices[i_vert]
            local p2 = shape_vertices[(i_vert % num_shape_verts) + 1]
            local edge = vec_sub(p2, p1)
            local normal = {x = -edge.y, y = edge.x}
            
            local len = sqrt(normal.x^2 + normal.y^2)
            if len > 0.0001 then
                normal.x = normal.x / len
                normal.y = normal.y / len
            else
                goto continue_axis_loop -- Skip degenerate edge
            end

            local is_unique = true
            for existing_axis in all(unique_axes) do
                local dot_p = vec_dot(existing_axis, normal)
                if abs(dot_p) > 0.999 then 
                    is_unique = false
                    break
                end
            end
            if is_unique then
                add(unique_axes, normal)
            end
            ::continue_axis_loop::
        end
        return unique_axes
    end

    -- Helper: Check for Oriented Bounding Box (OBB) collision using Separating Axis Theorem (SAT)
    local function check_obb_collision(piece1, piece2)
        local vertices1 = get_rotated_vertices(piece1)
        local vertices2 = get_rotated_vertices(piece2)

        if #vertices1 < 2 or #vertices2 < 2 then return false end -- Not enough vertices for a shape

        local all_projection_axes = {}
        local axes1 = get_axes_for_shape(vertices1)
        local axes2 = get_axes_for_shape(vertices2)

        for ax in all(axes1) do add(all_projection_axes, ax) end
        for ax in all(axes2) do
            local is_unique_overall = true
            for existing_ax_overall in all(axes1) do
                 local dot_prod_overall = vec_dot(existing_ax_overall, ax)
                 if abs(dot_prod_overall) > 0.999 then
                    is_unique_overall = false
                    break
                 end
            end
            if is_unique_overall then
                add(all_projection_axes, ax)
            end
        end
        
        if #all_projection_axes == 0 then return true end -- Or handle as error/no separation

        for axis in all(all_projection_axes) do
            local min1, max1 = project_vertices(vertices1, axis)
            local min2, max2 = project_vertices(vertices2, axis)
            if max1 < min2 or max2 < min1 then
                return false -- Separating axis found
            end
        end
        return true -- No separating axis found
    end

    -- Helper: Check if a point is inside an OBB (defined by its piece structure)
    local function is_point_in_obb(point, obb_piece_struct)
        local obb_vertices = get_rotated_vertices(obb_piece_struct)
        if not obb_vertices or #obb_vertices < 2 then return false end
        
        local obb_axes = get_axes_for_shape(obb_vertices)
        if #obb_axes == 0 then return false end 

        for axis in all(obb_axes) do
            local min_obb, max_obb = project_vertices(obb_vertices, axis)
            local point_proj = vec_dot(point, axis)
            if point_proj < min_obb - 0.001 or point_proj > max_obb + 0.001 then -- Add tolerance
                return false 
            end
        end
        return true 
    end

    -- Helper: Check for Line Segment vs OBB intersection using SAT
    local function check_line_segment_obb_intersection(line_p0, line_p1, obb_piece_struct)
        local obb_vertices = get_rotated_vertices(obb_piece_struct)
        if not obb_vertices or #obb_vertices < 2 then return false end

        -- If line segment is effectively a point, check if point is in OBB
        if vec_dist_sq(line_p0, line_p1) < 0.0001 then
            return is_point_in_obb(line_p0, obb_piece_struct)
        end
        local line_segment_vertices = {line_p0, line_p1}

        local axes = {}
        -- 1. Axes from OBB
        local obb_axes = get_axes_for_shape(obb_vertices)
        for ax in all(obb_axes) do add(axes, ax) end

        -- 2. Axis normal to the line segment
        local line_vec = vec_sub(line_p1, line_p0)
        local line_normal = vec_normalize({x = -line_vec.y, y = line_vec.x})
        
        if line_normal.x ~= 0 or line_normal.y ~= 0 then -- If valid normal
            local is_unique = true
            for existing_axis in all(obb_axes) do
                if abs(vec_dot(existing_axis, line_normal)) > 0.999 then
                    is_unique = false
                    break
                end
            end
            if is_unique then
                add(axes, line_normal)
            end
        end
        
        if #axes == 0 then return true end -- Should not happen with valid inputs; fail safe to collision

        for axis in all(axes) do
            local min_obb, max_obb = project_vertices(obb_vertices, axis)
            local min_seg, max_seg = project_vertices(line_segment_vertices, axis)

            if max_obb < min_seg - 0.001 or max_seg < min_obb - 0.001 then -- Add tolerance
                return false -- Separating axis found
            end
        end
        return true -- No separating axis found
    end

    -- Main logic for legal_placement:

    -- 1. Boundary Check: Ensure all corners of the piece are within board limits
    local world_corners = get_rotated_vertices(piece_to_place)
    if not world_corners or #world_corners < 1 then return false end -- Not enough vertices

    for corner in all(world_corners) do
        if corner.x < 0 or corner.x > board_w or
           corner.y < 0 or corner.y > board_h then
            return false -- Piece is out of bounds
        end
    end

    -- 2. Intersection Check: Ensure the piece doesn't collide with existing pieces
    if pieces then 
        for existing_piece in all(pieces) do
            if existing_piece ~= piece_to_place then 
                if check_obb_collision(piece_to_place, existing_piece) then
                    return false -- Collides with an existing piece
                end
            end
        end
    end

    -- 3. Attacker Laser Check (if piece is an attacker)
    if piece_to_place.type == "attacker" then
        local laser_hits_defender = false
        
        -- Attacker's apex is the first vertex from get_rotated_vertices
        -- Ensure world_corners is populated (it is from boundary check)
        if #world_corners == 0 then return false end -- Should have been caught by boundary check
        local attacker_apex = world_corners[1] 
        
        local orientation_angle = piece_to_place.orientation
        local attacker_orientation_vec = vec_normalize({x = cos(orientation_angle), y = sin(orientation_angle)})

        local laser_end_point = {
            x = attacker_apex.x + attacker_orientation_vec.x * laser_length,
            y = attacker_apex.y + attacker_orientation_vec.y * laser_length
        }

        if pieces then
            for defender_candidate in all(pieces) do
                if defender_candidate.type == "defender" then
                    if check_line_segment_obb_intersection(attacker_apex, laser_end_point, defender_candidate) then
                        laser_hits_defender = true
                        break -- Found a defender hit by the laser
                    end
                end
            end
        end
        
        if not laser_hits_defender then
            return false -- Attacker's laser must hit a defender
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