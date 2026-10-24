function pitMat = pit_laps_three_stop(numLaps, minStint)
% PIT_LAPS_THREE_STOP Generate pit laps for a valid three-stop strategy.
% Each of the four resulting stints must contain at least minStint laps.
  pitMat = zeros(0, 3);
  for p1 = minStint : (numLaps - 3*minStint)
    for p2 = (p1 + minStint) : (numLaps - 2*minStint)
      for p3 = (p2 + minStint) : (numLaps - minStint)
        pitMat(end+1, :) = [p1, p2, p3]; %#ok<AGROW>
      end
    end
  end
end
