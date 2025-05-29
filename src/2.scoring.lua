function reset_player_scores()
  if player_manager and player_manager.current_players then
    for _,player_obj in ipairs(player_manager.current_players)do
      if player_obj then
        player_obj.score=0
      end
    end
  end
end

function reset_piece_states_for_scoring()
  for _,p_obj in ipairs(pieces)do
    if p_obj then
      p_obj.hits=0
      p_obj.targeting_attackers={}
    end
  end
end

function _check_attacker_hit_defender(attacker_obj,defender_obj,player_manager_param,ray_segment_intersect_func,current_laser_len,add_func)
  local attacker_vertices=attacker_obj:get_draw_vertices()
  if not attacker_vertices or #attacker_vertices==0 then return end
  local apex=attacker_vertices[1]
  local dir_x=cos(attacker_obj.orientation)
  local dir_y=sin(attacker_obj.orientation)

  local defender_corners=defender_obj:get_draw_vertices()
  if not defender_corners or #defender_corners==0 then return end

  for j=1,#defender_corners do
    local k=(j%#defender_corners)+1
    local ix,iy,t=ray_segment_intersect_func(apex.x,apex.y,dir_x,dir_y,
                                             defender_corners[j].x,defender_corners[j].y,
                                             defender_corners[k].x,defender_corners[k].y)
    if t and t>=0 and t<=current_laser_len then
      defender_obj.hits=(defender_obj.hits or 0)+1
      defender_obj.targeting_attackers=defender_obj.targeting_attackers or{}
      add_func(defender_obj.targeting_attackers,attacker_obj)

      local attacker_player=player_manager_param.get_player(attacker_obj.owner_id)
      local defender_player=player_manager_param.get_player(defender_obj.owner_id)

      if attacker_player and defender_player and attacker_obj.owner_id~=defender_obj.owner_id then
        attacker_player:add_score(1)
      end

      if defender_obj.hits==1 then
        defender_obj.state="successful"
      elseif defender_obj.hits==2 then
        defender_obj.state="unsuccessful"
      elseif defender_obj.hits>=3 then
        defender_obj.state="overcharged"
      end
      return true
    end
  end
  return false
end

function _score_defender(p_obj,player_manager_param)
  if p_obj and p_obj.type=="defender"then
    local num_total_attackers_targeting=0
    if p_obj.targeting_attackers then
      num_total_attackers_targeting=#p_obj.targeting_attackers
    end
    p_obj.dbg_target_count=num_total_attackers_targeting

    if num_total_attackers_targeting<=1 then
      local defender_player=player_manager_param.get_player(p_obj.owner_id)
      if defender_player then
        defender_player:add_score(1)
      end
    end
  end
end

function score_pieces()
  reset_player_scores()
  reset_piece_states_for_scoring()

  for _,attacker_obj in ipairs(pieces)do
    if attacker_obj and attacker_obj.type=="attacker"then
      for _,defender_obj in ipairs(pieces)do
        if defender_obj and defender_obj.type=="defender"then
          _check_attacker_hit_defender(attacker_obj,defender_obj,player_manager,ray_segment_intersect,LASER_LEN,add)
        end
      end
    end
  end

  for _,p_obj in ipairs(pieces)do
    _score_defender(p_obj,player_manager)
  end

  local remaining_pieces={}
  for _,p_obj in ipairs(pieces)do
    if not p_obj.captured_flag then
      add(remaining_pieces,p_obj)
    else
      printh("Piece removed due to overcharge capture: P"..p_obj.owner_id.." "..p_obj.type)
    end
  end
  pieces=remaining_pieces
end

function calculate_final_scores()
  score_pieces()
end

update_game_state=score_pieces