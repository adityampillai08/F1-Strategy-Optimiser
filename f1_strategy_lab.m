1;  % <- marks this file as a SCRIPT file (not a function file), so it can hold many functions
%% =====================================================================
%  F1 STRATEGY LAB: A GNU Octave-Based Race Simulation and Pit-Stop
%  Optimization System          --  ONE-FILE INTEGRATED VERSION
%  =====================================================================
%  Core question: given tyre degradation, fuel consumption and pit-stop
%  time loss, which feasible 1-stop or 2-stop strategy gives the lowest
%  simulated race time?
%
%  HOW TO RUN (GNU Octave command window):
%      >> cd   <folder containing this file>
%      >> f1_strategy_lab                 % run the application
%
%      >> F1_RUN_TEST = true;  f1_strategy_lab    % run the built-in self-test
%      >> clear F1_RUN_TEST                       % back to normal mode
%
%  FILE LAYOUT (top to bottom, each part = one team member's module):
%      1. calculate_lap_time   Member 1  tyre + fuel lap-time model
%      2. simulate_strategy    Member 2  lap-by-lap race simulator
%      3. optimize_strategy    Member 3  exhaustive 1-/2-stop optimizer
%      4. default_params, strategy_to_string, plot_results, f1_main
%                              Member 4  parameters, main program, plots
%      5. f1_self_test         integration test
%
%  SHARED PARAMETER NAMES (identical everywhere):
%      nLaps, pitLoss, fuelInitial, fuelPerLap, baseTime, degradationA,
%      degradationB, fuelCoeff   (+ optimizer options minStintLength,
%      availableCompounds, requireTwoCompounds)
%  Per-compound values are 1x3 vectors: index 1 = Soft, 2 = Medium, 3 = Hard.
%
%  INTEGRATION FIXES MADE (all marked "INTEGRATION FIX" in the code):
%      - simulate_strategy: baseTime/degradationA/degradationB accepted as
%        1x3 per-compound vectors (they were validated as scalars).
%      - simulate_strategy: clear error if fuelInitial is too small.
%      - optimize_strategy: uses the shared name params.nLaps.
%      - main/plot: results entries are results(i).pitLaps / .compounds /
%        .totalTime (there is no results(i).strategy field).
%      - main/plot: candidates are SORTED before "top N" is shown (the
%        optimizer returns them in search order, not best-first).
%      - fuelInitial now scales with race length (no negative fuel).
%      - Removed: sgtitle and XTickLabelRotation (not reliable in Octave).
%% =====================================================================


%% =====================================================================
%%  MEMBER 1 - TYRE AND FUEL LAP-TIME MODEL
%% =====================================================================

function lapTime = calculate_lap_time(tyreAge, fuelLoad, compound, params)
% CALCULATE_LAP_TIME Estimate lap time from tyre age and fuel load.
%
% Syntax:
%   lapTime = calculate_lap_time(tyreAge, fuelLoad, compound, params)
%
% Inputs:
%   tyreAge  - Number of completed laps on the current tyre set (laps)
%   fuelLoad - Remaining fuel at the beginning of the lap (kg)
%   compound - Tyre code: 1 = Soft, 2 = Medium, 3 = Hard
%   params   - Structure containing:
%              baseTime     : Initial lap time for each compound (s)
%              degradationA : Linear degradation coefficient (s/lap)
%              degradationB : Quadratic degradation coefficient (s/lap^2)
%              fuelCoeff    : Lap-time increase per kg of fuel (s/kg)
%
% Output:
%   lapTime  - Estimated lap time in seconds
%
% Model:
%   lapTime = baseTime(compound) ...
%           + degradationA(compound) * tyreAge ...
%           + degradationB(compound) * tyreAge^2 ...
%           + fuelCoeff * fuelLoad

    % Validate the tyre compound code.
    if ~isnumeric(compound) || ~isscalar(compound) || ...
            ~isreal(compound) || ~isfinite(compound) || ...
            compound ~= fix(compound) || ...
            compound < 1 || compound > 3
        error('calculate_lap_time:InvalidCompound', ...
              'Compound must be 1 (Soft), 2 (Medium), or 3 (Hard).');
    end

    % Validate tyre age and fuel load.
    if ~isnumeric(tyreAge) || ~isscalar(tyreAge) || ...
            ~isreal(tyreAge) || ~isfinite(tyreAge) || tyreAge < 0
        error('calculate_lap_time:InvalidTyreAge', ...
              'Tyre age must be a finite, non-negative scalar.');
    end

    if ~isnumeric(fuelLoad) || ~isscalar(fuelLoad) || ...
            ~isreal(fuelLoad) || ~isfinite(fuelLoad) || fuelLoad < 0
        error('calculate_lap_time:InvalidFuelLoad', ...
              'Fuel load must be a finite, non-negative scalar.');
    end

    % Check that all required parameters are provided.
    requiredFields = {'baseTime', 'degradationA', ...
                      'degradationB', 'fuelCoeff'};

    for k = 1:length(requiredFields)
        if ~isfield(params, requiredFields{k})
            error('calculate_lap_time:MissingParameter', ...
                  'Missing required parameter: %s', ...
                  requiredFields{k});
        end
    end

    % Each compound-specific parameter must have three values.
    if ~isnumeric(params.baseTime) || ...
            ~isreal(params.baseTime) || ...
            numel(params.baseTime) ~= 3 || ...
            any(~isfinite(params.baseTime(:)))
        error('calculate_lap_time:InvalidBaseTime', ...
              'baseTime must contain three finite real values.');
    end

    if ~isnumeric(params.degradationA) || ...
            ~isreal(params.degradationA) || ...
            numel(params.degradationA) ~= 3 || ...
            any(~isfinite(params.degradationA(:)))
        error('calculate_lap_time:InvalidDegradationA', ...
              'degradationA must contain three finite real values.');
    end

    if ~isnumeric(params.degradationB) || ...
            ~isreal(params.degradationB) || ...
            numel(params.degradationB) ~= 3 || ...
            any(~isfinite(params.degradationB(:)))
        error('calculate_lap_time:InvalidDegradationB', ...
              'degradationB must contain three finite real values.');
    end

    if ~isnumeric(params.fuelCoeff) || ...
            ~isscalar(params.fuelCoeff) || ...
            ~isreal(params.fuelCoeff) || ...
            ~isfinite(params.fuelCoeff) || params.fuelCoeff < 0
        error('calculate_lap_time:InvalidFuelCoeff', ...
              'fuelCoeff must be a finite, non-negative scalar.');
    end

    % Calculate the estimated lap time.
    lapTime = params.baseTime(compound) ...
            + params.degradationA(compound) * tyreAge ...
            + params.degradationB(compound) * tyreAge^2 ...
            + params.fuelCoeff * fuelLoad;

end


%% =====================================================================
%%  MEMBER 2 - RACE SIMULATION ENGINE
%% =====================================================================

function [totalTime, lapTimes, tyreAges, fuelLoads] = simulate_strategy(strategy, params)
% SIMULATE_STRATEGY Simulate an F1 race using a supplied tyre strategy.
%
% Inputs:
%   strategy.pitLaps  - Row vector of laps after which a pit stop occurs
%   strategy.compounds - Numeric tyre code per stint:
%                         1 = Soft, 2 = Medium, 3 = Hard
%   params.nLaps       - Total number of race laps
%   params.pitLoss     - Time lost per pit stop
%   params.fuelInitial - Initial fuel load
%   params.fuelPerLap  - Fuel consumed per lap
%   params.baseTime    - Base lap time (used by lap-time model)
%   params.degradationA - Degradation parameter A
%   params.degradationB - Degradation parameter B
%   params.fuelCoeff   - Fuel effect coefficient
%
% Outputs:
%   totalTime - Total race time, including pit-stop losses
%   lapTimes  - Lap times including pit-stop losses on pit laps
%   tyreAges  - Tyre age used for each lap
%   fuelLoads - Fuel load at the start of each lap
%
% Note:
%   Pit lap L means the stop occurs after completing lap L.
%   Its time loss is included in lapTimes(L). New tyres are used
%   starting from lap L+1. Fuel is never reset at a pit stop.

    % ---------- Validate required strategy fields ----------
    if ~isstruct(strategy) || ...
       ~isfield(strategy, 'pitLaps') || ...
       ~isfield(strategy, 'compounds')
        error('strategy must contain pitLaps and compounds.');
    end

    % ---------- Validate required parameter fields ----------
    requiredParams = {
        'nLaps', 'pitLoss', 'fuelInitial', 'fuelPerLap', ...
        'baseTime', 'degradationA', 'degradationB', 'fuelCoeff'
    };

    if ~isstruct(params)
        error('params must be a structure.');
    end

    for k = 1:numel(requiredParams)
        if ~isfield(params, requiredParams{k})
            error('Missing params field: %s', requiredParams{k});
        end
    end

    % ---------- Validate race length ----------
    if ~isnumeric(params.nLaps) || ...
       ~isscalar(params.nLaps) || ...
       ~isfinite(params.nLaps) || ...
       params.nLaps < 1 || ...
       params.nLaps ~= fix(params.nLaps)
        error('params.nLaps must be a positive integer.');
    end

    nLaps = params.nLaps;

    % ---------- Normalize strategy vectors ----------
    pitLaps = strategy.pitLaps(:).';
    compounds = strategy.compounds(:).';

    if ~isnumeric(pitLaps) || ...
       any(~isfinite(pitLaps)) || ...
       any(pitLaps ~= fix(pitLaps))
        error('pitLaps must contain finite integer lap numbers.');
    end

    if ~isnumeric(compounds) || ...
       any(~isfinite(compounds)) || ...
       any(compounds ~= fix(compounds)) || ...
       any(compounds < 1 | compounds > 3)
        error('Tyre compounds must be integer codes 1, 2, or 3.');
    end

    % ---------- Validate pit laps ----------
    if any(diff(pitLaps) <= 0)
        error('pitLaps must be strictly increasing.');
    end

    if any(pitLaps < 1 | pitLaps >= nLaps)
        error('Pit laps must be between 1 and nLaps-1.');
    end

    % One more stint than the number of pit stops.
    nStints = numel(pitLaps) + 1;

    if numel(compounds) ~= nStints
        error('Number of compounds must equal number of stints (%d).', ...
              nStints);
    end

    % ---------- Validate numerical model parameters ----------
    % INTEGRATION FIX: baseTime, degradationA and degradationB are
    % per-compound vectors [Soft Medium Hard] (calculate_lap_time indexes
    % them with the compound code), so they must have 3 values, not 1.
    scalarParams = {'pitLoss', 'fuelInitial', 'fuelPerLap', 'fuelCoeff'};
    vectorParams = {'baseTime', 'degradationA', 'degradationB'};

    for k = 1:numel(scalarParams)
        value = params.(scalarParams{k});

        if ~isnumeric(value) || ~isscalar(value) || ...
           ~isreal(value) || ~isfinite(value)
            error('params.%s must be a finite real scalar.', ...
                  scalarParams{k});
        end
    end

    for k = 1:numel(vectorParams)
        value = params.(vectorParams{k});

        if ~isnumeric(value) || numel(value) ~= 3 || ...
           ~isreal(value) || any(~isfinite(value(:)))
            error(['params.%s must hold 3 finite real values ', ...
                   '[Soft Medium Hard].'], vectorParams{k});
        end
    end

    if params.pitLoss < 0 || params.fuelPerLap < 0
        error('pitLoss and fuelPerLap must be non-negative.');
    end

    % INTEGRATION FIX: fail early with a clear message if the tank would
    % run dry (calculate_lap_time rejects negative fuel).
    if params.fuelInitial - params.fuelPerLap * (nLaps - 1) < 0
        error(['Fuel runs out before lap %d: increase params.fuelInitial ', ...
               'or reduce params.fuelPerLap.'], nLaps);
    end

    % ---------- Initialize output vectors ----------
    lapTimes = zeros(1, nLaps);
    tyreAges = zeros(1, nLaps);
    fuelLoads = zeros(1, nLaps);

    fuelLoad = params.fuelInitial;
    tyreAge = 0;
    stintIndex = 1;
    pitIndex = 1;

    % ---------- Simulate each race lap ----------
    for lap = 1:nLaps

        % Record the fuel load at the start of this lap.
        fuelLoads(lap) = fuelLoad;

        % Age the tyre by one lap before calculating lap time.
        tyreAge = tyreAge + 1;
        tyreAges(lap) = tyreAge;

        % Current stint's tyre compound.
        compound = compounds(stintIndex);

        % Calculate lap time using the shared project function.
        lapTime = calculate_lap_time( ...
            tyreAge, fuelLoad, compound, params);

        % Pit-stop loss is charged once, on the scheduled pit lap.
        if pitIndex <= numel(pitLaps) && lap == pitLaps(pitIndex)
            lapTime = lapTime + params.pitLoss;

            % The new stint starts on the following lap.
            tyreAge = 0;
            stintIndex = stintIndex + 1;
            pitIndex = pitIndex + 1;
        end

        lapTimes(lap) = lapTime;

        % Consume fuel after completing the lap.
        % Fuel is not reset during pit stops.
        fuelLoad = fuelLoad - params.fuelPerLap;
    end

    % ---------- Calculate total race time ----------
    totalTime = sum(lapTimes);

end


%% =====================================================================
%%  MEMBER 3 - STRATEGY OPTIMIZER
%% =====================================================================

function [bestStrategy, bestTime, results] = optimize_strategy(params)
% OPTIMIZE_STRATEGY  Exhaustive search for the fastest 1-stop / 2-stop strategy.
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
%   For numStops = 1 and 2:
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
  pitSets = cell(1, 2);
  pitSets{1} = pit_laps_one_stop(numLaps, minStint);
  pitSets{2} = pit_laps_two_stop(numLaps, minStint);

  % Upper bound on number of candidates, used to pre-allocate results.
  maxCand = 0;
  for numStops = 1:2
    maxCand = maxCand + size(pitSets{numStops}, 1) * ...
              numel(compounds)^(numStops + 1);
  end

  emptyEntry = struct('pitLaps', [], 'compounds', [], 'totalTime', Inf);
  results = repmat(emptyEntry, 1, max(maxCand, 1));

  bestTime     = Inf;
  bestStrategy = struct('pitLaps', [], 'compounds', []);
  count = 0;

  % ---------- 3. exhaustive search ------------------------------------
  for numStops = 1:2
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

function value = get_param(params, name, defaultValue)
% Return params.(name) if present and non-empty, otherwise the default.
  if isfield(params, name) && ~isempty(params.(name))
    value = params.(name);
  else
    value = defaultValue;
  end
end

function numLaps = get_num_laps(params)
% Find the race length under any of the agreed field names.
  names = {'nLaps', 'numLaps', 'totalLaps', 'raceLaps'};   % nLaps = shared name
  numLaps = [];
  for k = 1:numel(names)
    if isfield(params, names{k}) && ~isempty(params.(names{k}))
      numLaps = params.(names{k});
      break;
    end
  end
  if isempty(numLaps) || ~isscalar(numLaps) || numLaps < 1 || ...
     numLaps ~= fix(numLaps)
    error('optimize_strategy:badInput', ...
          'params must contain a positive integer race length (params.nLaps).');
  end
end

function pitMat = pit_laps_one_stop(numLaps, minStint)
% All p1 with p1 >= minStint and numLaps - p1 >= minStint.
  p1 = minStint : (numLaps - minStint);
  pitMat = p1(:);                               % one column, ascending
end

function pitMat = pit_laps_two_stop(numLaps, minStint)
% All (p1, p2): stint1 = p1, stint2 = p2-p1, stint3 = numLaps-p2, each >= minStint.
  pitMat = zeros(0, 2);
  for p1 = minStint : (numLaps - 2*minStint)
    for p2 = (p1 + minStint) : (numLaps - minStint)
      pitMat(end+1, :) = [p1, p2];              %#ok<AGROW> small (hundreds of rows)
    end
  end
end

function combMat = compound_combinations(compounds, nStints)
% Every sequence of length nStints over the compound list (repetition allowed),
% in lexicographic order. Result size: numel(compounds)^nStints  x  nStints.
  nC    = numel(compounds);
  nRows = nC ^ nStints;
  rowId = (0 : nRows - 1).';
  idx   = zeros(nRows, nStints);
  for col = 1:nStints
    % Digit 'col' of rowId written in base nC (most significant digit first).
    idx(:, col) = mod(floor(rowId / nC^(nStints - col)), nC) + 1;
  end
  combMat = compounds(idx);
end

function ok = is_valid_pit_plan(pitLaps, numLaps, minStint)
% Pit laps strictly increasing, inside the race, and every stint long enough.
  edges = [0, pitLaps, numLaps];
  ok = all(diff(edges) >= minStint);            % diff>=minStint>=1 => increasing
end


%% =====================================================================
%%  MEMBER 4 - SHARED PARAMETERS AND HELPERS
%% =====================================================================

function params = default_params(nLaps, pitLoss)
% DEFAULT_PARAMS  Single source of truth for the F1 STRATEGY LAB parameters.
%
%   params = default_params()                 30 laps, 22.0 s pit loss
%   params = default_params(nLaps)
%   params = default_params(nLaps, pitLoss)
%
% Every number below is HYPOTHETICAL (educational model, not real F1 data).
% Per-compound values are 1x3 vectors indexed by tyre code:
%   index 1 = Soft, 2 = Medium, 3 = Hard.
% main.m and all integration tests call this function, so the parameter
% names and values can never drift apart between files.

  if nargin < 1 || isempty(nLaps),   nLaps   = 30;   end
  if nargin < 2 || isempty(pitLoss), pitLoss = 22.0; end

  % ---- race ------------------------------------------------------------
  params.nLaps   = nLaps;                    % race distance            [laps]
  params.pitLoss = pitLoss;                  % time lost per pit stop   [s]

  % ---- fuel ------------------------------------------------------------
  params.fuelPerLap  = 1.8;                  % fuel burnt per lap       [kg/lap]
  params.fuelInitial = params.fuelPerLap * nLaps;   % start fuel, scales with
                                             % race length so the tank never
                                             % goes negative            [kg]
  params.fuelCoeff   = 0.03;                 % lap-time penalty per kg  [s/kg]

  % ---- tyre model: lap = base + A*age + B*age^2 + fuelCoeff*fuel -----------
  %                              Soft    Medium   Hard
  params.baseTime     = [89.00,  89.90,  90.60]; % fresh-tyre pace    [s]
  params.degradationA = [ 0.090,  0.045,  0.020]; % linear wear       [s/lap]
  params.degradationB = [ 0.0080, 0.0035, 0.0012]; % quadratic wear   [s/lap^2]

  % ---- optimizer settings (read by optimize_strategy.m) ------------------
  params.minStintLength      = 3;            % shortest allowed stint   [laps]
  params.availableCompounds  = [1 2 3];      % tyre codes the search may use
  params.requireTwoCompounds = false;        % true = enforce the F1 rule of
                                             % >= 2 different dry compounds
end

function [seqStr, pitStr] = strategy_to_string(strategy, useFullNames)
% STRATEGY_TO_STRING  Turn a strategy struct into readable text.
%
%   [seqStr, pitStr] = strategy_to_string(strategy)         'Soft -> Hard', '15'
%   [seqStr, pitStr] = strategy_to_string(strategy, false)  'S-H',          '15'
%
% Shared by main.m and plot_results.m so the compound names (1 = Soft,
% 2 = Medium, 3 = Hard) are defined in exactly one place.

  if nargin < 2, useFullNames = true; end

  fullNames = {'Soft', 'Medium', 'Hard'};
  initials  = 'SMH';

  codes = strategy.compounds(:).';
  parts = cell(1, numel(codes));
  for k = 1:numel(codes)
    if codes(k) >= 1 && codes(k) <= 3 && codes(k) == fix(codes(k))
      if useFullNames
        parts{k} = fullNames{codes(k)};
      else
        parts{k} = initials(codes(k));
      end
    else
      parts{k} = '?';                    % unknown code (should never happen)
    end
  end

  if useFullNames
    seqStr = strjoin(parts, ' -> ');
  else
    seqStr = strjoin(parts, '-');
  end

  if isempty(strategy.pitLaps)
    pitStr = 'none';
  else
    pitStr = strtrim(sprintf('%d, ', strategy.pitLaps));
    pitStr = pitStr(1:end-1);            % drop the trailing comma
  end
end


%% =====================================================================
%%  MEMBER 4 - PLOTS
%% =====================================================================

function plot_results(bestStrategy, lapTimes, tyreAges, results, params, opts)
% PLOT_RESULTS  Four-panel dashboard for F1 STRATEGY LAB.
%
%   plot_results(bestStrategy, lapTimes, tyreAges, results, params)
%   plot_results(bestStrategy, lapTimes, tyreAges, results, params, opts)
%
% Inputs (same names as main.m):
%   bestStrategy  struct with .pitLaps and .compounds
%   lapTimes      1 x nLaps lap times of the best strategy [s]
%                 (pit-stop loss is included on the pit lap)
%   tyreAges      1 x nLaps tyre age of the best strategy  [laps]
%   results       struct array from optimize_strategy: pitLaps, compounds,
%                 totalTime for every candidate
%   params        shared parameter struct (nLaps, pitLoss, baseTime, ...)
%   opts          OPTIONAL struct:
%                   opts.visible  'on' (default) | 'off'   (off = silent test)
%                   opts.saveFile PNG file name to save ('' = do not save)
%                   opts.topN     strategies in the comparison chart (8)
%
% Panels:  1) lap time vs lap   2) tyre age vs lap
%          3) strategy comparison   4) tyre model curves (from calculate_lap_time)

  if nargin < 6 || isempty(opts), opts = struct(); end
  if ~isfield(opts, 'visible'),  opts.visible  = 'on'; end
  if ~isfield(opts, 'saveFile'), opts.saveFile = '';   end
  if ~isfield(opts, 'topN'),     opts.topN     = 8;    end

  % ---- colours: one per compound (Soft red, Medium yellow, Hard grey) ----
  names   = {'Soft', 'Medium', 'Hard'};
  colours = [0.85 0.13 0.13;
             0.95 0.70 0.05;
             0.40 0.40 0.40];

  nLaps    = numel(lapTimes);
  pitLaps  = bestStrategy.pitLaps(:).';
  tyres    = bestStrategy.compounds(:).';
  nStints  = numel(tyres);
  edges    = [0, pitLaps, nLaps];                % stint k = edges(k)+1 : edges(k+1)
  [seqStr, pitStr] = strategy_to_string(bestStrategy, true);

  % Lap times WITHOUT the pit-stop loss, so tyre/fuel trends stay visible.
  racingTimes = lapTimes;
  racingTimes(pitLaps) = racingTimes(pitLaps) - params.pitLoss;

  fig = figure('Name', 'F1 Strategy Lab - Results', 'NumberTitle', 'off', ...
               'Position', [60 40 1250 800], 'Color', 'w', ...
               'Visible', opts.visible);

  % =====================================================================
  % Panel 1: lap time versus race lap
  % =====================================================================
  subplot(2, 2, 1);
  hold on;
  [hs, labs] = deal([], {});
  for s = 1:nStints
    idx = (edges(s) + 1) : edges(s + 1);
    c   = tyres(s);
    h = plot(idx, racingTimes(idx), '-o', 'Color', colours(c, :), ...
             'LineWidth', 2, 'MarkerSize', 4, 'MarkerFaceColor', colours(c, :));
    if ~any(strcmp(labs, names{c}))
      hs(end + 1) = h;                  %#ok<AGROW>
      labs{end + 1} = names{c};         %#ok<AGROW>
    end
  end
  yl = ylim;
  yl = [yl(1) - 0.2, yl(2) + 0.2];
  hp = [];
  for k = 1:numel(pitLaps)
    hp = plot([pitLaps(k) + 0.5, pitLaps(k) + 0.5], yl, 'k--', 'LineWidth', 1.2);
  end
  if ~isempty(hp)
    hs(end + 1) = hp;
    labs{end + 1} = sprintf('Pit stop (+%.1f s)', params.pitLoss);
  end
  ylim(yl);
  xlim([1 nLaps]);
  hold off;
  grid on; box on;
  xlabel('Race lap number');
  ylabel('Lap time (s), pit loss excluded');
  title(sprintf('Best strategy: %s  |  pit after lap %s', seqStr, pitStr));
  legend(hs, labs{:}, 'Location', 'northeast');

  % =====================================================================
  % Panel 2: tyre age versus race lap
  % =====================================================================
  subplot(2, 2, 2);
  hold on;
  [hs, labs] = deal([], {});
  for s = 1:nStints
    idx = (edges(s) + 1) : edges(s + 1);
    c   = tyres(s);
    h = plot(idx, tyreAges(idx), '-o', 'Color', colours(c, :), ...
             'LineWidth', 2, 'MarkerSize', 4, 'MarkerFaceColor', colours(c, :));
    if ~any(strcmp(labs, names{c}))
      hs(end + 1) = h;                  %#ok<AGROW>
      labs{end + 1} = names{c};         %#ok<AGROW>
    end
  end
  hold off;
  grid on; box on;
  xlim([1 nLaps]);
  xlabel('Race lap number');
  ylabel('Tyre age (laps on current set)');
  title('Tyre age: resets to 1 after every pit stop');
  legend(hs, labs{:}, 'Location', 'northeast');

  % =====================================================================
  % Panel 3: comparison of the fastest candidate strategies
  % =====================================================================
  subplot(2, 2, 3);
  [sortedTimes, order] = sort([results.totalTime]);
  n      = min(opts.topN, numel(results));
  delta  = sortedTimes(1:n) - sortedTimes(1);       % gap to the best [s]
  labels = cell(1, n);
  for i = 1:n
    r = results(order(i));
    [sq, pt] = strategy_to_string(r, false);
    labels{i} = sprintf('#%d  %s  (pit %s)', i, sq, pt);
  end
  hb = barh(1:n, delta, 0.7);
  set(hb, 'FaceColor', [0.30 0.55 0.85]);
  set(gca, 'YTick', 1:n, 'YTickLabel', labels, 'YDir', 'reverse');
  xmax = max(max(delta) * 1.45, 1);
  xlim([0 xmax]);
  ylim([0.4, n + 0.6]);
  for i = 1:n
    if i == 1
      txt = '  BEST';
    else
      txt = sprintf('  +%.2f s', delta(i));
    end
    text(delta(i), i, txt, 'FontSize', 9, 'VerticalAlignment', 'middle');
  end
  grid on; box on;
  xlabel('Time lost compared with the best strategy (s)');
  title(sprintf('Top %d of %d candidate strategies (S/M/H = Soft/Medium/Hard)', ...
                n, numel(results)));

  % =====================================================================
  % Panel 4: the tyre model itself, evaluated with calculate_lap_time
  % =====================================================================
  subplot(2, 2, 4);
  hold on;
  maxAge = max(diff(edges)) + 5;
  ages   = 0:maxAge;
  for c = 1:3
    curve = zeros(size(ages));
    for k = 1:numel(ages)
      curve(k) = calculate_lap_time(ages(k), 0, c, params);   % empty tank
    end
    plot(ages, curve, '-', 'Color', colours(c, :), 'LineWidth', 2);
  end
  hold off;
  grid on; box on;
  xlabel('Tyre age (laps)');
  ylabel('Lap time at zero fuel (s)');
  title('Tyre model: Soft starts fastest but wears fastest');
  legend(names{:}, 'Location', 'northwest');

  drawnow;

  % ---- optional PNG export (never fatal) -----------------------------
  if ~isempty(opts.saveFile)
    try
      print(fig, opts.saveFile, '-dpng', '-r110');
    catch err
      warning('plot_results:saveFailed', 'Could not save figure: %s', err.message);
    end
  end
end

%% =====================================================================
%  MEMBER 4 - MAIN PROGRAM
%% =====================================================================
function txt = fmt_time(t)
% FMT_TIME  seconds -> 'm:ss.mmm'
  txt = sprintf('%d:%06.3f', floor(t / 60), mod(t, 60));
end

function value = ask_number(label, defaultValue, lo, hi, wholeOnly)
% ASK_NUMBER  Prompt until a valid number in [lo, hi] is typed (Enter = default).
  while true
    txt = input(sprintf('  %s [default %g, allowed %g-%g]: ', ...
                        label, defaultValue, lo, hi), 's');
    if isempty(strtrim(txt))
      value = defaultValue;
      return;
    end
    value = str2double(txt);
    ok = isscalar(value) && isfinite(value) && value >= lo && value <= hi;
    if wholeOnly
      ok = ok && (value == fix(value));
    end
    if ok
      return;
    end
    fprintf('  Invalid entry - please enter a number from %g to %g.\n', lo, hi);
  end
end

function out = f1_main(batchMode)
% F1_MAIN  Collect inputs, run the optimizer, report and plot.
%   out = f1_main(false)   interactive (asks questions, shows figure)
%   out = f1_main(true)    silent batch mode used by the self-test

  if nargin < 1, batchMode = false; end
  rule = repmat('=', 1, 68);
  thin = repmat('-', 1, 68);
  tyreNames = {'Soft', 'Medium', 'Hard'};

  % ---------- banner -------------------------------------------------------
  fprintf('\n%s\n', rule);
  fprintf('   F1 STRATEGY LAB\n');
  fprintf('   A GNU Octave-Based Race Simulation and Pit-Stop Optimization System\n');
  fprintf('%s\n\n', rule);

  % ---------- 1. parameters (hypothetical values live in default_params) ---
  params = default_params();

  % ---------- 2. let the user choose race distance and pit-stop loss -------
  if ~batchMode
    fprintf('Default race: %d laps, pit-stop time loss %.1f s.\n', ...
            params.nLaps, params.pitLoss);
    answer = input('Customize race distance and pit-stop loss? (y/n) [n]: ', 's');
    if strcmpi(strtrim(answer), 'y')
      newLaps    = ask_number('Race distance in laps', params.nLaps, 10, 60, true);
      newPitLoss = ask_number('Pit-stop time loss in seconds', params.pitLoss, 10, 40, false);
      params = default_params(newLaps, newPitLoss);  % fuel scales with distance
    end
    fprintf('\n');
  end

  fprintf('MODEL PARAMETERS  (hypothetical, educational values)\n%s\n', thin);
  fprintf('  Race distance : %d laps        Pit-stop loss : %.1f s\n', ...
          params.nLaps, params.pitLoss);
  fprintf('  Fuel          : %.1f kg at start, %.1f kg/lap burn, %.3f s per kg\n', ...
          params.fuelInitial, params.fuelPerLap, params.fuelCoeff);
  fprintf('  Search        : 1-stop and 2-stop, min stint %d laps\n\n', ...
          params.minStintLength);
  fprintf('  %-8s %10s %16s %18s\n', 'Tyre', 'Base (s)', 'Wear A (s/lap)', 'Wear B (s/lap^2)');
  for c = 1:3
    fprintf('  %-8s %10.2f %16.4f %18.5f\n', tyreNames{c}, params.baseTime(c), ...
            params.degradationA(c), params.degradationB(c));
  end
  fprintf('%s\n\n', thin);

  % ---------- size of the search + time estimate ---------------------------
  N  = params.nLaps;
  m  = params.minStintLength;
  nC = numel(params.availableCompounds);
  nCand = max(N - 2*m + 1, 0) * nC^2;
  if N >= 3*m
    nCand = nCand + (N - 3*m + 2) * (N - 3*m + 1) / 2 * nC^3;
  end

  probe.pitLaps   = floor(N / 2);                % time 3 trial simulations
  probe.compounds = [1 1];
  tic;
  for k = 1:3
    simulate_strategy(probe, params);
  end
  estSeconds = (toc / 3) * nCand;

  fprintf('Candidate strategies to evaluate : %d\n', nCand);
  fprintf('Estimated search time            : about %.0f s\n', max(estSeconds, 1));

  if ~batchMode && estSeconds > 90
    go = input('  This may take a while. Continue? (y/n) [y]: ', 's');
    if strcmpi(strtrim(go), 'n')
      fprintf('Cancelled by user.\n');
      out = struct();
      return;
    end
  end

  % ---------- 3. run the optimizer ----------------------------------------
  fprintf('\nSearching all one-stop and two-stop strategies...\n');
  fflush(stdout);
  tic;
  [bestStrategy, bestTime, results] = optimize_strategy(params);
  searchSeconds = toc;
  fprintf('Done: %d strategies evaluated in %.1f s.\n', numel(results), searchSeconds);

  if isempty(results) || ~isfinite(bestTime) || isempty(bestStrategy.pitLaps)
    fprintf('\nNo feasible strategy exists for these settings.\n');
    fprintf('Try a longer race or a smaller minimum stint length.\n');
    out = struct('params', params, 'bestStrategy', bestStrategy, ...
                 'bestTime', bestTime, 'results', results);
    return;
  end

  % ---------- 4. re-simulate the winner for lap-by-lap data ----------------
  [totalTime, lapTimes, tyreAges, fuelLoads] = simulate_strategy(bestStrategy, params);
  if abs(totalTime - bestTime) > 1e-9
    warning('f1:mismatch', 'Optimizer time and re-simulated time differ by %g s.', ...
            abs(totalTime - bestTime));
  end

  % ---------- rank every candidate (optimizer returns search order) --------
  [sortedTimes, order] = sort([results.totalTime]);
  ranked      = results(order);
  stopsRanked = cellfun(@numel, {ranked.pitLaps});

  % ---------- 5. report ----------------------------------------------------
  [seqStr, pitStr] = strategy_to_string(bestStrategy, true);
  nStops = numel(bestStrategy.pitLaps);

  fprintf('\n%s\n', rule);
  fprintf('   OPTIMAL STRATEGY\n');
  fprintf('%s\n', rule);
  fprintf('   Tyre sequence      : %s\n', seqStr);
  fprintf('   Pit stops          : %d  (after lap %s)\n', nStops, pitStr);
  fprintf('   Total race time    : %.3f s   (%s)\n', totalTime, fmt_time(totalTime));
  fprintf('   Average lap time   : %.3f s\n', totalTime / N);
  fprintf('%s\n\n', rule);

  edges = [0, bestStrategy.pitLaps, N];
  nSt   = numel(edges) - 1;
  fprintf('STINT BREAKDOWN\n%s\n', thin);
  fprintf('  %-6s %-8s %-10s %6s %14s %12s\n', 'Stint', 'Tyre', 'Laps', 'Length', 'Time (s)', 'Avg lap (s)');
  for s = 1:nSt
    a = edges(s) + 1;
    b = edges(s + 1);
    stintTime = sum(lapTimes(a:b));
    if s < nSt
      stintTime = stintTime - params.pitLoss;     % report pure racing time
    end
    fprintf('  %-6d %-8s %-10s %6d %14.3f %12.3f\n', s, ...
            tyreNames{bestStrategy.compounds(s)}, sprintf('%d-%d', a, b), ...
            b - a + 1, stintTime, stintTime / (b - a + 1));
  end
  fprintf('  (+ %d pit stop(s) x %.1f s = %.1f s of pit loss)\n', ...
          nStops, params.pitLoss, nStops * params.pitLoss);
  fprintf('%s\n\n', thin);

  fprintf('TOP 5 STRATEGIES   (S = Soft, M = Medium, H = Hard)\n%s\n', thin);
  fprintf('  %-5s %-10s %-6s %-14s %12s %10s\n', 'Rank', 'Tyres', 'Stops', 'Pit after lap', 'Total (s)', 'Gap (s)');
  for i = 1:min(5, numel(ranked))
    [sq, pt] = strategy_to_string(ranked(i), false);
    fprintf('  %-5d %-10s %-6d %-14s %12.3f %10.3f\n', i, sq, ...
            numel(ranked(i).pitLaps), pt, ranked(i).totalTime, ...
            ranked(i).totalTime - sortedTimes(1));
  end
  fprintf('%s\n\n', thin);

  i1 = find(stopsRanked == 1, 1);
  i2 = find(stopsRanked == 2, 1);
  if ~isempty(i1) && ~isempty(i2)
    fprintf('BEST ONE-STOP vs BEST TWO-STOP\n%s\n', thin);
    [sq, pt] = strategy_to_string(ranked(i1), false);
    fprintf('  Best 1-stop : %-8s pit after lap %-8s %10.3f s\n', sq, pt, ranked(i1).totalTime);
    [sq, pt] = strategy_to_string(ranked(i2), false);
    fprintf('  Best 2-stop : %-8s pit after lap %-8s %10.3f s\n', sq, pt, ranked(i2).totalTime);
    fprintf('  Difference  : %.3f s in favour of the %d-stop strategy\n', ...
            abs(ranked(i1).totalTime - ranked(i2).totalTime), nStops);
    fprintf('%s\n\n', thin);
  end
  fprintf('Fastest vs slowest candidate: %.1f s apart.\n', sortedTimes(end) - sortedTimes(1));

  % ---------- 7. plots -----------------------------------------------------
  fprintf('\nGenerating plots...\n');
  opts.topN = 8;
  if batchMode
    opts.visible  = 'off';
    opts.saveFile = fullfile(tempdir, 'f1_strategy_lab_selftest.png');
  else
    opts.visible  = 'on';
    opts.saveFile = 'f1_strategy_lab_results.png';
  end
  plot_results(bestStrategy, lapTimes, tyreAges, results, params, opts);
  if ~batchMode
    fprintf('Figure shown. A copy is saved as %s (if your graphics backend allows).\n', ...
            opts.saveFile);
  end

  % ---------- 8. honesty note ----------------------------------------------
  fprintf('\n%s\n', rule);
  fprintf(' NOTE: this strategy is optimal UNDER THE CHOSEN MODEL ASSUMPTIONS\n');
  fprintf(' (hypothetical tyre wear, fuel burn and fixed pit loss). It is an\n');
  fprintf(' educational simulation, NOT a prediction of a real Formula 1 race.\n');
  fprintf('%s\n\n', rule);

  out.params       = params;
  out.bestStrategy = bestStrategy;
  out.bestTime     = bestTime;
  out.results      = results;
  out.totalTime    = totalTime;
  out.lapTimes     = lapTimes;
  out.tyreAges     = tyreAges;
  out.fuelLoads    = fuelLoads;
end

%% =====================================================================
%  INTEGRATION SELF-TEST  (run:  F1_RUN_TEST = true;  f1_strategy_lab)
%% =====================================================================
function f1_self_test()
  fprintf('\n##### F1 STRATEGY LAB - SELF TEST #####\n\n');
  tol = 1e-9;
  p = default_params(30, 22.0);

  % ---- A. every shared parameter field exists, per-compound ones are 1x3 ----
  needed = {'nLaps','pitLoss','fuelInitial','fuelPerLap','baseTime', ...
            'degradationA','degradationB','fuelCoeff'};
  for k = 1:numel(needed)
    assert(isfield(p, needed{k}), 'Missing params field');
  end
  assert(numel(p.baseTime) == 3 && numel(p.degradationA) == 3 && ...
         numel(p.degradationB) == 3, 'Per-compound params must be 1x3.');
  fprintf('[PASS] A. shared parameter names and sizes\n');

  % ---- B. calculate_lap_time (Member 1) -------------------------------------
  % hand calculation: Soft, age 5, fuel 40 -> 89 + 0.09*5 + 0.008*25 + 0.03*40
  assert(abs(calculate_lap_time(5, 40, 1, p) - 90.85) < tol, 'Lap-time formula wrong.');
  soft0 = calculate_lap_time(0, 40, 1, p);  hard0 = calculate_lap_time(0, 40, 3, p);
  soft10 = calculate_lap_time(10, 40, 1, p); hard10 = calculate_lap_time(10, 40, 3, p);
  assert(soft0 < hard0, 'Soft should start faster than Hard.');
  assert((soft10 - soft0) > (hard10 - hard0), 'Soft should degrade more than Hard.');
  failed = false;
  try
    calculate_lap_time(0, 40, 4, p);
  catch
    failed = true;
  end
  assert(failed, 'Invalid compound must be rejected.');
  fprintf('[PASS] B. calculate_lap_time: formula, compound ordering, validation\n');

  % ---- C. simulate_strategy (Member 2) --------------------------------------
  s.pitLaps = 15;  s.compounds = [1 2];
  [tot, lt, ta, fl] = simulate_strategy(s, p);
  assert(numel(lt) == 30 && numel(ta) == 30 && numel(fl) == 30, 'Vector lengths.');
  assert(ta(15) == 15 && ta(16) == 1, 'Tyre age must reset after the pit stop.');
  assert(abs(fl(1) - p.fuelInitial) < tol, 'Fuel starts at fuelInitial.');
  assert(abs(fl(16) - (fl(15) - p.fuelPerLap)) < tol, 'Fuel must not reset at pit.');
  assert(abs(lt(15) - (calculate_lap_time(15, fl(15), 1, p) + p.pitLoss)) < tol, ...
         'Pit loss must be added once on the pit lap.');
  assert(abs(tot - sum(lt)) < tol, 'totalTime must equal sum(lapTimes).');
  failed = false;
  try
    bad.pitLaps = [10 20];
    bad.compounds = [1 2];
    simulate_strategy(bad, p);
  catch
    failed = true;
  end
  assert(failed, 'Compounds/stint mismatch must be rejected.');
  failed = false;
  try
    q = p;
    q.fuelInitial = 10;
    simulate_strategy(s, q);
  catch
    failed = true;
  end
  assert(failed, 'Too little fuel must be rejected.');
  fprintf('[PASS] C. simulate_strategy: reset, fuel, pit loss, validation\n');

  % ---- D. optimize_strategy (Member 3) --------------------------------------
  [bs, bt, res] = optimize_strategy(p);
  N = p.nLaps; m = p.minStintLength; C = numel(p.availableCompounds);
  expected = (N-2*m+1)*C^2 + (N-3*m+2)*(N-3*m+1)/2 * C^3;
  assert(numel(res) == expected, 'Candidate count differs from formula (7056).');
  assert(abs(bt - min([res.totalTime])) < tol, 'bestTime must be the minimum.');
  assert(all(diff([0 bs.pitLaps N]) >= m), 'Best strategy has a too-short stint.');
  assert(numel(bs.compounds) == numel(bs.pitLaps) + 1, 'One compound per stint.');
  for k = 1:100:numel(res)                       % spot-check stored times
    chk = simulate_strategy(struct('pitLaps', res(k).pitLaps, ...
                                   'compounds', res(k).compounds), p);
    assert(abs(chk - res(k).totalTime) < tol, 'Stored time differs from simulation.');
  end
  [bs2, bt2] = optimize_strategy(p);
  assert(isequal(bs2, bs) && bt2 == bt, 'Search must be reproducible.');
  % regression value from an independent re-implementation of the model
  assert(isequal(bs.pitLaps, 15) && isequal(bs.compounds, [1 1]) && ...
         abs(bt - 2758.550) < 1e-3, 'Unexpected optimum for the default parameters.');
  warning('off', 'optimize_strategy:noFeasible');
  [bs3, bt3, r3] = optimize_strategy(default_params(5, 22));  % too short to pit twice
  warning('on', 'optimize_strategy:noFeasible');
  assert(isinf(bt3) && isempty(bs3.pitLaps) && isempty(r3), 'Infeasible case mishandled.');
  fprintf('[PASS] D. optimize_strategy: count %d, minimum, reproducible, infeasible case\n', ...
          numel(res));

  % ---- E. whole application in silent batch mode ------------------------------
  out = f1_main(true);
  assert(abs(out.totalTime - out.bestTime) < tol, 'Re-simulated time must match optimizer.');
  assert(abs(sum(out.lapTimes) - out.totalTime) < tol, 'Sum of laps.');
  assert(all(diff(out.fuelLoads) < 0) && all(out.fuelLoads >= 0), 'Fuel must fall, never < 0.');
  fprintf('[PASS] E. main program end-to-end (plots drawn off-screen)\n');

  fprintf('\nALL SELF-TESTS PASSED.\n\n');
end

%% =====================================================================
%  ENTRY POINT  (everything above only DEFINES functions; this runs them)
%% =====================================================================
% Web integration: do not launch the interactive command-line UI when sourced by Flask.
if ~exist('F1_WEB_MODE', 'var') || ~F1_WEB_MODE
  if ~exist('F1_RUN_TEST', 'var'), F1_RUN_TEST = false; end
  if F1_RUN_TEST
    f1_self_test();
  else
    f1_results = f1_main(false);
  end
end
