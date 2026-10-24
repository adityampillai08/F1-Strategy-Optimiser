function [bestStrategy, bestTime, results] = optimize_strategy(params)
% OPTIMIZE_STRATEGY  Exhaustive search for the fastest 1-stop / 2-stop / 3-stop strategy.
%
%   [bestStrategy, bestTime, results] = optimize_strategy(params)
%
% INPUT  params (struct) - the shared parameter struct used by simulate_strategy.
%   Fields read by this optimizer (all optional except the race length;
%   everything else in params is passed straight to simulate_strategy):
%     params.nLaps                race length in laps - the shared project name
%                                 (aliases still accepted: numLaps, totalLaps,
%                                 raceLaps)
%     params.minStintLength       minimum laps per stint          (default 3)
%     params.availableCompounds   tyre codes allowed, e.g. [1 2 3] (default [1 2 3])
%                                 1 = Soft, 2 = Medium, 3 = Hard
%     params.requireTwoCompounds  true -> reject strategies that use only one
%                                 compound (F1 dry-race rule)     (default false)
%
% OUTPUT
%   bestStrategy.pitLaps    row vector, laps AFTER which the car pits
%   bestStrategy.compounds  row vector, one tyre code per stint
%   bestTime                simulated total race time of bestStrategy
%   results                 struct array (1 x nCandidates) with fields
%                           pitLaps, compounds, totalTime for EVERY candidate
%
% ALGORITHM (deterministic exhaustive search)
%   For numStops = 1, 2, and 3:
%     1. Generate every increasing pit-lap vector whose stints are all
%        >= minStintLength, using nested for-loops in ascending order.
%     2. Generate every compound sequence (C^(numStops+1) combinations,
%        repetition allowed) in lexicographic order.
%     3. For every (pitLaps, compounds) pair call simulate_strategy and store
%        the total time.
%   The best candidate is the one with the smallest finite total time.
%   Ties keep the FIRST candidate found (strict "<"), so results are
%   reproducible: fewer stops, earlier pit laps, lower compound codes win.
%
% COMPLEXITY (N = laps, C = compounds, m = minimum stint length)
%   One-stop candidates : (N-2m+1) * C^2           ~ O(N * C^2)
%   Two-stop candidates : nchoosek(N-3m+2, 2) * C^3 ~ O(N^2 * C^3)
%   Each candidate costs one simulation, O(N) laps, so total work is
%   O(N^3 * C^3). For N = 30, C = 3, m = 3: 25*9 + 253*27 = 7056 simulations.
%
% This function does NOT contain the tyre model, race simulator or plots;
% it only calls simulate_strategy(strategy, params).

  % ---------- 1. read and validate inputs -----------------------------
  if ~isstruct(params)
    error('optimize_strategy:badInput', 'params must be a struct.');
  end

  numLaps   = get_num_laps(params);
  minStint  = get_param(params, 'minStintLength', 3);
  compounds = get_param(params, 'availableCompounds', [1 2 3]);
  compounds = compounds(:).';                    % force row vector
  needTwo   = get_param(params, 'requireTwoCompounds', false);

  if ~(isscalar(minStint) && minStint >= 1 && minStint == fix(minStint))
    error('optimize_strategy:badInput', ...
          'minStintLength must be a positive integer.');
  end
  if isempty(compounds)
    error('optimize_strategy:badInput', 'availableCompounds is empty.');
  end

  % ---------- 2. build the list of candidates (no simulation yet) -----
  % Each row of pitSets{k} is one pit-lap vector for k stops.
  pitSets = cell(1, 3);
  pitSets{1} = pit_laps_one_stop(numLaps, minStint);
  pitSets{2} = pit_laps_two_stop(numLaps, minStint);
  pitSets{3} = pit_laps_three_stop(numLaps, minStint);

  % Upper bound on number of candidates, used to pre-allocate results.
  maxCand = 0;
  for numStops = 1:3
    maxCand = maxCand + size(pitSets{numStops}, 1) * ...
              numel(compounds)^(numStops + 1);
  end

  emptyEntry = struct('pitLaps', [], 'compounds', [], 'totalTime', Inf);
  results = repmat(emptyEntry, 1, max(maxCand, 1));

  bestTime     = Inf;
  bestStrategy = struct('pitLaps', [], 'compounds', []);
  count = 0;

  % ---------- 3. exhaustive search ------------------------------------
  for numStops = 1:3
    pitMat  = pitSets{numStops};
    combMat = compound_combinations(compounds, numStops + 1);

    for i = 1:size(pitMat, 1)
      pitLaps = pitMat(i, :);

      % Safety check: increasing laps and every stint >= minStint.
      if ~is_valid_pit_plan(pitLaps, numLaps, minStint)
        continue;
      end

      for j = 1:size(combMat, 1)
        tyres = combMat(j, :);

        % Optional rule: at least two different compounds.
        if needTwo && numel(unique(tyres)) < 2
          continue;
        end

        strategy.pitLaps    = pitLaps;
        strategy.compounds  = tyres;
        totalTime = simulate_strategy(strategy, params);   % first output only

        count = count + 1;
        results(count).pitLaps   = pitLaps;
        results(count).compounds = tyres;
        results(count).totalTime = totalTime;

        % Only finite times are feasible; strict "<" keeps first on ties.
        if isfinite(totalTime) && totalTime < bestTime
          bestTime               = totalTime;
          bestStrategy.pitLaps   = pitLaps;
          bestStrategy.compounds = tyres;
        end
      end
    end
  end

  % Trim unused pre-allocated entries.
  results = results(1:count);

  % ---------- 4. no feasible candidate? -------------------------------
  if ~isfinite(bestTime)
    warning('optimize_strategy:noFeasible', ...
            ['No feasible strategy found (nLaps = %d, minStintLength = %d). ', ...
             'Returning empty bestStrategy and bestTime = Inf.'], ...
            numLaps, minStint);
    bestTime = Inf;
  end
end

% =====================================================================
%                          LOCAL HELPER FUNCTIONS
% =====================================================================
