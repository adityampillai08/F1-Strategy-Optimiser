function pitMat = pit_laps_two_stop(numLaps, minStint)
% All (p1, p2): stint1 = p1, stint2 = p2-p1, stint3 = numLaps-p2, each >= minStint.
  pitMat = zeros(0, 2);
  for p1 = minStint : (numLaps - 2*minStint)
    for p2 = (p1 + minStint) : (numLaps - minStint)
      pitMat(end+1, :) = [p1, p2];              %#ok<AGROW> small (hundreds of rows)
    end
  end
end
