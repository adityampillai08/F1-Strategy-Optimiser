function pitMat = pit_laps_one_stop(numLaps, minStint)
% All p1 with p1 >= minStint and numLaps - p1 >= minStint.
  p1 = minStint : (numLaps - minStint);
  pitMat = p1(:);                               % one column, ascending
end
