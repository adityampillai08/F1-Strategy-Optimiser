function ok = is_valid_pit_plan(pitLaps, numLaps, minStint)
% Pit laps strictly increasing, inside the race, and every stint long enough.
  edges = [0, pitLaps, numLaps];
  ok = all(diff(edges) >= minStint);            % diff>=minStint>=1 => increasing
end


%% =====================================================================
%%  MEMBER 4 - SHARED PARAMETERS AND HELPERS
%% =====================================================================
