-- src/scoring.lua

local scoring = {}

--[[
  Counts the number of attackers targeting a specific defender.
  
  Parameters:
  - defender_id: The unique identifier of the defender piece.
  - pieces: A table containing all game pieces currently in play.
            Each piece is expected to be a table with at least:
            - type: string, "attacker" or "defender"
            - target_defender_id: (for attackers) the id of the defender they are targeting
            
  Returns:
  - number: The count of attackers targeting the specified defender.
--]]
function scoring.count_attackers_on_defender(defender_id, pieces)
  local count = 0
  if pieces then
    for _, piece in ipairs(pieces) do
      if piece.type == "attacker" and piece.target_defender_id == defender_id then
        count = count + 1
      end
    end
  end
  return count
end

--[[
  Recalculates the scores for all players based on the current state of pieces.
  
  Parameters:
  - pieces: A table containing all game pieces currently in play.
            Each piece is expected to be a table with at least:
            - id: unique identifier for the piece
            - type: string, "attacker" or "defender"
            - player_id: identifier for the player who owns this piece
            - target_defender_id: (for attackers) the id of the defender they are targeting
  - players: A table (array-like, 1-indexed) of player objects. 
             Each player object should have a 'score' field that will be updated.

  Side Effects:
  - Modifies the 'score' field of each player object in the 'players' table.
--]]
function scoring.recalculate_player_scores(pieces, players)
  if not pieces or not players then
    -- Or handle error appropriately
    return 
  end

  -- Reset scores for all players
  for i = 1, #players do
    if players[i] then
      players[i].score = 0
    end
  end

  -- Calculate scores based on current pieces
  for _, piece in ipairs(pieces) do
    if piece.player_id and players[piece.player_id] then -- Ensure piece owner and player entry exist
      if piece.type == "attacker" then
        local target_defender = nil
        local target_defender_owner_id = nil

        -- Find the defender this attacker is pointing to and its owner
        if piece.target_defender_id then
          for _, p_defender_check in ipairs(pieces) do
            if p_defender_check.id == piece.target_defender_id and p_defender_check.type == "defender" then
              target_defender = p_defender_check
              target_defender_owner_id = p_defender_check.player_id
              break
            end
          end
        end

        if target_defender then
          -- Rule: "if that attacker is pointed at a defender of its own color, it scores no points."
          if piece.player_id == target_defender_owner_id then
            -- Attacker scores 0 points
          else
            local attackers_on_target = scoring.count_attackers_on_defender(piece.target_defender_id, pieces)
            -- Rule: "attackers succeed if there are 2+ attackers pointed toward the same defender"
            if attackers_on_target >= 2 then
              players[piece.player_id].score = players[piece.player_id].score + 1
            end
          end
        end
      elseif piece.type == "defender" then
        local attackers_on_this_defender = scoring.count_attackers_on_defender(piece.id, pieces)
        -- Rule: "Defenders succeed if there are 0-1 attackers pointed at the same defender."
        if attackers_on_this_defender < 2 then
          players[piece.player_id].score = players[piece.player_id].score + 1
        end
      end
    end
  end
end

return scoring
