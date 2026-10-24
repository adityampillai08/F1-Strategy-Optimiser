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
%      >> v5_reliability                     % run the application
%
%      >> F1_RUN_TEST = true;  v5_reliability     % run the built-in self-test
%      >> clear F1_RUN_TEST                       % back to normal mode
%
%  FILE LAYOUT (top to bottom, each part = one team member's module):
%      1. calculate_lap_time   Member 1  tyre + fuel lap-time model
%      2. simulate_strategy    Member 2  lap-by-lap race simulator
%      3. optimize_strategy    Member 3  exhaustive / fast 1-/2-stop optimizer
%      4. track_database (24 venues), default_params, strategy_to_string, plot_results, f1_main
%                              Member 4  track settings, parameters, main program, plots
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

    % Thermal state for the simplified tyre-temperature model.
    tyreTempC = 25;
    if isfield(params, 'temperatureModel') && isfield(params.temperatureModel, 'ambientTempC')
        tyreTempC = params.temperatureModel.ambientTempC + 8;
    end

    % ---------- Simulate each race lap ----------
    for lap = 1:nLaps

        % Record the fuel load at the start of this lap.
        fuelLoads(lap) = fuelLoad;

        % Age the tyre by one lap before calculating lap time.
        tyreAge = tyreAge + 1;
        tyreAges(lap) = tyreAge;

        % Current stint's tyre compound.
        compound = compounds(stintIndex);

        % Calculate baseline lap time using the shared project function.
        lapTime = calculate_lap_time( ...
            tyreAge, fuelLoad, compound, params);

        % ---- Simplified tyre-temperature model ------------------------------
        % This is an educational approximation, not measured F1 tyre telemetry.
        if isfield(params, 'temperatureModel') && ...
                isfield(params.temperatureModel, 'enabled') && params.temperatureModel.enabled
            tm = params.temperatureModel;
            ambientC = tm.ambientTempC;
            trackC = tm.trackTempC;
            stress = tm.trackStress;
            isWetLap = false;
            if isfield(params, 'raceScenario') && ~isempty(params.raceScenario)
                scenario = params.raceScenario;
                if isfield(scenario, 'ambientTempC'), ambientC = scenario.ambientTempC; end
                if isfield(scenario, 'trackTempC'), trackC = scenario.trackTempC; end
                if isfield(scenario, 'wetLaps'), isWetLap = any(scenario.wetLaps == lap); end
            end
            targetTyreTempC = 78 + 0.25 * (ambientC - 20) + 0.55 * (trackC - 20) + 1.5 * stress;
            if isWetLap, targetTyreTempC = targetTyreTempC - 8; end
            tyreTempC = tyreTempC + 0.32 * (targetTyreTempC - tyreTempC);
            coldPenalty = max(0, 85 - tyreTempC) * 0.025;
            hotPenalty = max(0, tyreTempC - 105) * 0.060;
            lapTime = lapTime + coldPenalty + hotPenalty;
            baseWear = params.degradationA(compound) * tyreAge + ...
                       params.degradationB(compound) * tyreAge^2;
            thermalWearFactor = 1 + max(0, tyreTempC - 100) * 0.012 + ...
                                  max(0, 78 - tyreTempC) * 0.004;
            lapTime = lapTime + max(0, baseWear * (thermalWearFactor - 1));
        end

        % ---- Monte Carlo race-event effects (only when a scenario is supplied)
        if isfield(params, 'raceScenario') && ~isempty(params.raceScenario)
            scenario = params.raceScenario;

            % Rain adds a simple lap-time penalty and additional wear.
            if isfield(scenario, 'wetLaps') && any(scenario.wetLaps == lap)
                lapTime = lapTime + scenario.rainPenaltySeconds;
                extraWear = (scenario.wetWearMultiplier - 1) * ...
                    (params.degradationA(compound) * tyreAge + ...
                     params.degradationB(compound) * tyreAge^2);
                lapTime = lapTime + max(0, extraWear);
            end

            % SC/VSC pace penalties are simplified educational assumptions.
            if isfield(scenario, 'scLaps') && any(scenario.scLaps == lap)
                lapTime = lapTime + scenario.scPaceDelta;
            elseif isfield(scenario, 'vscLaps') && any(scenario.vscLaps == lap)
                lapTime = lapTime + scenario.vscPaceDelta;
            end

            % Simplified red-flag restart delay.
            if isfield(scenario, 'redFlagLaps') && ...
                    any(scenario.redFlagLaps == lap)
                lapTime = lapTime + scenario.redFlagRestartDelay;
            end
        end

        % Pit-stop loss is charged once, on the scheduled pit lap.
        if pitIndex <= numel(pitLaps) && lap == pitLaps(pitIndex)
            pitLossThisLap = params.pitLoss;
            if isfield(params, 'raceScenario') && ~isempty(params.raceScenario)
                scenario = params.raceScenario;
                if isfield(scenario, 'scLaps') && any(scenario.scLaps == lap)
                    pitLossThisLap = params.pitLoss * scenario.scPitLossMultiplier;
                elseif isfield(scenario, 'vscLaps') && any(scenario.vscLaps == lap)
                    pitLossThisLap = params.pitLoss * scenario.vscPitLossMultiplier;
                elseif isfield(scenario, 'redFlagLaps') && ...
                        any(scenario.redFlagLaps == lap)
                    pitLossThisLap = 0;
                end
            end
            lapTime = lapTime + pitLossThisLap;

            % The new stint starts on the following lap.
            tyreAge = 0;
            if exist('tm', 'var'), tyreTempC = tm.ambientTempC + 8; end
            stintIndex = stintIndex + 1;
            pitIndex = pitIndex + 1;
        end

        % Simplified assumption: a red flag resets tyre age after the lap.
        if isfield(params, 'raceScenario') && ~isempty(params.raceScenario) && ...
                isfield(params.raceScenario, 'redFlagLaps') && ...
                any(params.raceScenario.redFlagLaps == lap)
            tyreAge = 0;
            if exist('tm', 'var'), tyreTempC = tm.ambientTempC + 4; end
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
% OPTIMIZE_STRATEGY  Search for the fastest 1-stop / 2-stop / 3-stop strategy.
% Supports the original exhaustive mode and an optional coarse-to-fine fast mode.
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
%   One-stop candidates : O(N * C^2)
%   Two-stop candidates : O(N^2 * C^3)
%   Three-stop candidates: O(N^3 * C^4); web mode uses coarse-to-fine search
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

  % Generate one fixed scenario set shared by all candidate strategies.
  % This makes strategy comparisons fair and the search reproducible.
  useMonteCarlo = isfield(params, 'monteCarlo') && ...
                  isfield(params.monteCarlo, 'enabled') && ...
                  params.monteCarlo.enabled;
  scenarios = {};
  if useMonteCarlo
    scenarios = generate_race_scenarios(params);
  end

  if ~(isscalar(minStint) && minStint >= 1 && minStint == fix(minStint))
    error('optimize_strategy:badInput', ...
          'minStintLength must be a positive integer.');
  end
  if isempty(compounds)
    error('optimize_strategy:badInput', 'availableCompounds is empty.');
  end

  % ---------- 2. build the list of candidates (no simulation yet) -----
  % Fast mode evaluates a coarse pit-lap grid first, then refines around
  % the strongest coarse candidates. Exhaustive mode remains available and
  % is retained for deterministic regression tests.
  fastSearch = isfield(params, 'search') && ...
               isfield(params.search, 'fastEnabled') && params.search.fastEnabled;
  searchStride = 1;
  refineTopK = 0;
  if fastSearch
    searchStride = max(2, ceil(numLaps / 12));
    refineTopK = get_param(params.search, 'refineTopK', 8);
  end
  pitSets = cell(1, 3);
  pitSets{1} = pit_laps_one_stop(numLaps, minStint);
  pitSets{2} = pit_laps_two_stop(numLaps, minStint);
  pitSets{3} = pit_laps_three_stop(numLaps, minStint);
  if fastSearch && searchStride > 1
    for ns = 1:3
      fullSet = pitSets{ns};
      if ~isempty(fullSet)
        keep = all(mod(fullSet - minStint, searchStride) == 0, 2);
        coarseSet = fullSet(keep, :);
        if isempty(coarseSet), coarseSet = fullSet(1, :); end
        pitSets{ns} = coarseSet;
      end
    end
  end

  % Upper bound on number of candidates, used to pre-allocate results.
  maxCand = 0;
  for numStops = 1:3
    maxCand = maxCand + size(pitSets{numStops}, 1) * ...
              numel(compounds)^(numStops + 1);
  end

  % Reliability fields are NaN when Monte Carlo is disabled, so the
  % application never presents deterministic results as reliability data.
  emptyEntry = struct('pitLaps', [], 'compounds', [], 'totalTime', Inf, ...
      'scenarioTimes', [], 'averageRaceTime', NaN, 'scenarioStdSeconds', NaN, ...
      'winFrequency', NaN, 'reliabilityScore', NaN);
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
        if useMonteCarlo
          scenarioTimes = zeros(1, numel(scenarios));
          for sc = 1:numel(scenarios)
            scenarioParams = params;
            scenarioParams.raceScenario = scenarios{sc};
            scenarioTimes(sc) = simulate_strategy(strategy, scenarioParams);
          end
          totalTime = mean(scenarioTimes);
        else
          scenarioTimes = [];
          totalTime = simulate_strategy(strategy, params);   % first output only
        end

        count = count + 1;
        results(count).pitLaps   = pitLaps;
        results(count).compounds = tyres;
        results(count).totalTime = totalTime;
        results(count).averageRaceTime = totalTime;
        if useMonteCarlo
          results(count).scenarioTimes = scenarioTimes;
          results(count).scenarioStdSeconds = std(scenarioTimes, 1);
        end

        % Only finite times are feasible; strict "<" keeps first on ties.
        if isfinite(totalTime) && totalTime < bestTime
          bestTime               = totalTime;
          bestStrategy.pitLaps   = pitLaps;
          bestStrategy.compounds = tyres;
        end
      end
    end
  end

  % ---------- 3a. local refinement around the best coarse plans ---------
  % Refine pit timing by +/-1 lap around the best distinct coarse plans.
  % Evaluate every allowed compound sequence at those nearby pit timings.
  if fastSearch && count > 0
    coarseCount = count;
    [~, coarseOrder] = sort([results(1:coarseCount).totalTime], 'ascend');
    topK = min(refineTopK, numel(coarseOrder));
    seenKeys = cell(1, coarseCount);
    for q = 1:coarseCount
      seenKeys{q} = strategy_key(results(q).pitLaps, results(q).compounds);
    end
    refinedPlans = {};
    for q = 1:numel(coarseOrder)
      r = results(coarseOrder(q));
      planKey = sprintf('%d,', [numel(r.pitLaps), r.pitLaps]);
      if any(strcmp(refinedPlans, planKey)), continue; end
      refinedPlans{end+1} = planKey; %#ok<AGROW>
      offsets = -1:1;
      nPitDims = numel(r.pitLaps);
      if nPitDims == 1
        offsetRows = offsets(:);
      elseif nPitDims == 2
        [oa, ob] = ndgrid(offsets, offsets);
        offsetRows = [oa(:), ob(:)];
      else
        [oa, ob, oc] = ndgrid(offsets, offsets, offsets);
        offsetRows = [oa(:), ob(:), oc(:)];
      end
      for oi = 1:size(offsetRows, 1)
        pitLaps = r.pitLaps + offsetRows(oi, :);
        if ~is_valid_pit_plan(pitLaps, numLaps, minStint), continue; end
        numStops = numel(pitLaps);
        combMat = compound_combinations(compounds, numStops + 1);
        for cj = 1:size(combMat, 1)
          tyres = combMat(cj, :);
          if needTwo && numel(unique(tyres)) < 2, continue; end
          key = strategy_key(pitLaps, tyres);
          if any(strcmp(seenKeys, key)), continue; end
          seenKeys{end+1} = key; %#ok<AGROW>
          strategy.pitLaps = pitLaps;
          strategy.compounds = tyres;
          if useMonteCarlo
            scenarioTimes = zeros(1, numel(scenarios));
            for sc = 1:numel(scenarios)
              scenarioParams = params;
              scenarioParams.raceScenario = scenarios{sc};
              scenarioTimes(sc) = simulate_strategy(strategy, scenarioParams);
            end
            totalTime = mean(scenarioTimes);
          else
            scenarioTimes = [];
            totalTime = simulate_strategy(strategy, params);
          end
          count = count + 1;
          results(count) = emptyEntry;
          results(count).pitLaps = pitLaps;
          results(count).compounds = tyres;
          results(count).totalTime = totalTime;
          results(count).averageRaceTime = totalTime;
          if useMonteCarlo
            results(count).scenarioTimes = scenarioTimes;
            results(count).scenarioStdSeconds = std(scenarioTimes, 1);
          end
          if isfinite(totalTime) && totalTime < bestTime
            bestTime = totalTime;
            bestStrategy.pitLaps = pitLaps;
            bestStrategy.compounds = tyres;
          end
        end
      end
      if numel(refinedPlans) >= topK, break; end
    end
    fprintf('Fast search: coarse stride %d laps; locally refined %d promising pit plans.\n', ...
            searchStride, numel(refinedPlans));
  end

  % Trim unused pre-allocated entries.
  results = results(1:count);

  % ---------- 3b. scenario-based reliability statistics ----------------
  if useMonteCarlo && ~isempty(results)
    nSc = numel(scenarios);
    winCounts = zeros(1, numel(results));
    scenarioStd = [results.scenarioStdSeconds];
    for sc = 1:nSc
      timesThisScenario = arrayfun(@(r) r.scenarioTimes(sc), results);
      finiteMask = isfinite(timesThisScenario);
      if any(finiteMask)
        bestThisScenario = min(timesThisScenario(finiteMask));
        winners = find(finiteMask & abs(timesThisScenario - bestThisScenario) <= 1e-9);
        winCounts(winners) = winCounts(winners) + 1 / numel(winners);
      end
    end
    winFrequency = winCounts / nSc;

    % Consistency is normalized within this candidate set: 1 means the
    % lowest scenario-to-scenario standard deviation; 0 means the highest.
    % Reliability score = 70% scenario win frequency + 30% consistency.
    minStd = min(scenarioStd);
    maxStd = max(scenarioStd);
    if maxStd - minStd <= eps(max(1, max(abs(scenarioStd))))
      consistency = ones(size(scenarioStd));
    else
      consistency = (maxStd - scenarioStd) / (maxStd - minStd);
    end
    consistency = max(0, min(1, consistency));
    for k = 1:numel(results)
      results(k).winFrequency = winFrequency(k);
      results(k).reliabilityScore = 100 * ...
          (0.70 * winFrequency(k) + 0.30 * consistency(k));
    end
  end

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

function key = strategy_key(pitLaps, compounds)
% Stable text key used to avoid duplicate candidates during local refinement.
  key = ['P:', sprintf('%d,', pitLaps(:).'), '|C:', sprintf('%d,', compounds(:).')];
end

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

function pitMat = pit_laps_three_stop(numLaps, minStint)
% All (p1,p2,p3) plans with four stints each at least minStint laps.
  pitMat = zeros(0, 3);
  for p1 = minStint : (numLaps - 3*minStint)
    for p2 = (p1 + minStint) : (numLaps - 2*minStint)
      for p3 = (p2 + minStint) : (numLaps - minStint)
        pitMat(end+1, :) = [p1, p2, p3]; %#ok<AGROW>
      end
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

function tracks = track_database()
% TRACK_DATABASE  Educational database for all 24 venues announced for 2026.
% Lap counts use standard Grand Prix race distances for these circuit layouts.
% Bahrain and Saudi Arabia are retained as venue records even if a season's
% event status changes. Pit-loss values are approximate MODEL inputs (seconds),
% not official fixed values; they vary with pit-lane layout and race conditions.
%
% Each track has a canonical name and aliases accepted by the input prompt.
% Generic country names such as "USA" intentionally match multiple venues and
% trigger a clarification prompt instead of silently selecting one.
  names = { ...
    'Australian Grand Prix - Melbourne', ...
    'Chinese Grand Prix - Shanghai', ...
    'Japanese Grand Prix - Suzuka', ...
    'Bahrain Grand Prix - Sakhir', ...
    'Saudi Arabian Grand Prix - Jeddah', ...
    'Miami Grand Prix', ...
    'Canadian Grand Prix - Montreal', ...
    'Monaco Grand Prix', ...
    'Spanish Grand Prix - Barcelona-Catalunya', ...
    'Austrian Grand Prix - Spielberg', ...
    'British Grand Prix - Silverstone', ...
    'Belgian Grand Prix - Spa-Francorchamps', ...
    'Hungarian Grand Prix - Budapest', ...
    'Dutch Grand Prix - Zandvoort', ...
    'Italian Grand Prix - Monza', ...
    'Spanish Grand Prix - Madrid', ...
    'Azerbaijan Grand Prix - Baku', ...
    'Singapore Grand Prix', ...
    'United States Grand Prix - Austin', ...
    'Mexico City Grand Prix', ...
    'São Paulo Grand Prix - Interlagos', ...
    'Las Vegas Grand Prix', ...
    'Qatar Grand Prix - Lusail', ...
    'Abu Dhabi Grand Prix - Yas Marina'};
  laps = [58, 56, 53, 57, 50, 57, 70, 78, 66, 71, 52, 44, ...
          70, 72, 53, 57, 51, 62, 56, 71, 71, 50, 57, 58];
  % Approximate model estimates only; adjust interactively if desired.
  pitLoss = [22, 24, 22, 23, 24, 22, 19, 20, 22, 21, 23, 21, ...
             21, 21, 23, 22, 20, 29, 24, 22, 22, 22, 22, 22];
  aliases = { ...
    {'melbourne','australia','australian gp','albert park'}, ...
    {'shanghai','china','chinese','chinese gp'}, ...
    {'suzuka','japan','japanese gp'}, ...
    {'bahrain','sakhir','bahrain gp'}, ...
    {'jeddah','saudi arabia','saudi arabian gp'}, ...
    {'miami','miami gp','miami grand prix','usa','united states'}, ...
    {'montreal','canada','canadian gp','gilles-villeneuve'}, ...
    {'monaco','monaco gp'}, ...
    {'barcelona','barcelona-catalunya','catalunya','spanish gp barcelona'}, ...
    {'spielberg','austria','austrian gp','red bull ring'}, ...
    {'silverstone','british','british gp','uk','great britain'}, ...
    {'spa','spa-francorchamps','belgium','belgian gp'}, ...
    {'budapest','hungary','hungarian gp','hungaroring'}, ...
    {'zandvoort','netherlands','dutch gp'}, ...
    {'monza','italy','italian gp'}, ...
    {'madrid','madring','spanish gp madrid'}, ...
    {'baku','azerbaijan','azerbaijan gp'}, ...
    {'singapore','singapore gp','marina bay'}, ...
    {'austin','texas','texas/austin','texas austin','cota', ...
     'circuit of the americas','us gp','usa','united states'}, ...
    {'mexico','mexico city','mexican gp','hermanos rodriguez'}, ...
    {'sao paulo','são paulo','brazil','brazilian gp','interlagos'}, ...
    {'las vegas','vegas','las vegas gp','usa','united states'}, ...
    {'qatar','lusail','qatar gp'}, ...
    {'abu dhabi','yas marina','abu dhabi gp'}};
  % Circuit-specific model priors (heuristic, NOT calculated historical rates).
  % Order follows names above. Probabilities are per-race event chances.
  scProb   = [0.42 0.35 0.38 0.30 0.58 0.45 0.40 0.72 0.32 0.32 0.38 0.42 0.28 0.42 0.25 0.40 0.70 0.78 0.38 0.28 0.48 0.78 0.35 0.32];
  vscProb  = [0.38 0.35 0.32 0.25 0.35 0.35 0.32 0.20 0.28 0.25 0.30 0.32 0.22 0.25 0.20 0.30 0.25 0.22 0.28 0.22 0.30 0.20 0.25 0.22];
  redProb  = [0.08 0.08 0.08 0.06 0.12 0.10 0.08 0.16 0.06 0.06 0.08 0.12 0.05 0.10 0.04 0.08 0.18 0.18 0.08 0.06 0.12 0.18 0.08 0.05];
  rainProb = [0.42 0.28 0.38 0.03 0.03 0.08 0.42 0.18 0.22 0.18 0.42 0.42 0.18 0.35 0.18 0.22 0.12 0.08 0.25 0.08 0.38 0.08 0.08 0.04];
  ambientC = [22 24 19 29 30 29 20 24 24 24 18 17 25 19 25 24 24 29 25 22 20 17 29 28];
  trackC   = [32 36 28 38 42 42 31 35 38 40 30 28 43 30 42 39 35 38 37 42 34 24 38 35];
  stress   = [3.2 3.5 4.5 3.8 3.8 3.2 3.5 2.5 3.6 4.0 4.0 4.5 3.2 3.0 3.0 3.5 3.0 3.5 4.0 3.2 4.0 2.8 4.5 3.2];
  for k = 1:numel(names)
    tracks(k).name = names{k};
    tracks(k).nLaps = laps(k);
    tracks(k).pitLoss = pitLoss(k);
    tracks(k).aliases = aliases{k};
    tracks(k).eventProbabilities = struct('safetyCar', scProb(k), ...
        'vsc', vscProb(k), 'redFlag', redProb(k), 'rain', rainProb(k));
    tracks(k).ambientTempC = ambientC(k);
    tracks(k).trackTempC = trackC(k);
    tracks(k).trackStress = stress(k);
  end
end

function [track, isCustom] = select_grand_prix()
% SELECT_GRAND_PRIX  Resolve a GP/circuit name, including ambiguous USA.
  tracks = track_database();
  isCustom = false;
  while true
    fprintf('Choose a Grand Prix / circuit (or type custom):\n');
    for k = 1:numel(tracks)
      fprintf('  %-2d %s (%d laps)\n', k, tracks(k).name, tracks(k).nLaps);
    end
    answer = lower(strtrim(input('  GP name or number: ', 's')));
    if strcmp(answer, 'custom') || strcmp(answer, 'other')
      track.name = 'Custom race';
      track.nLaps = 30;
      track.pitLoss = 22.0;
      isCustom = true;
      return;
    end
    numericChoice = str2double(answer);
    if isfinite(numericChoice) && numericChoice == fix(numericChoice) && ...
       numericChoice >= 1 && numericChoice <= numel(tracks)
      track = tracks(numericChoice);
      return;
    end
    matches = [];
    for k = 1:numel(tracks)
      if strcmp(answer, lower(tracks(k).name))
        matches(end+1) = k;
      else
        for a = 1:numel(tracks(k).aliases)
          if strcmp(answer, lower(tracks(k).aliases{a}))
            matches(end+1) = k;
            break;
          end
        end
      end
    end
    matches = unique(matches);
    if numel(matches) == 1
      track = tracks(matches);
      return;
    elseif numel(matches) > 1
      fprintf('That name is ambiguous. Please choose the circuit:\n');
      for j = 1:numel(matches)
        fprintf('  %d) %s\n', j, tracks(matches(j)).name);
      end
      pick = str2double(input('  Enter choice number: ', 's'));
      if isfinite(pick) && pick == fix(pick) && pick >= 1 && pick <= numel(matches)
        track = tracks(matches(pick));
        return;
      end
      fprintf('Invalid circuit choice.\n\n');
    else
      fprintf('Track not recognized. Enter a listed name/number, or custom.\n\n');
    end
  end
end

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

  % ---- optional fast optimizer (interactive runs enable this) ------------
  % Exhaustive search remains the default for regression/self-tests.
  params.search.fastEnabled = false;
  params.search.refineTopK = 8;

  % ---- Monte Carlo race-event settings ---------------------------------
  % Disabled by default to preserve the original runtime and behaviour.
  params.monteCarlo.enabled    = false;
  params.monteCarlo.nScenarios = 20;
  params.monteCarlo.seed       = 20261023;

  % Illustrative per-race probabilities; not verified historical statistics.
  params.eventProbabilities.safetyCar = 0.35;
  params.eventProbabilities.vsc       = 0.30;
  params.eventProbabilities.redFlag   = 0.08;
  params.eventProbabilities.rain      = 0.35;

  % Disabled for generic unit tests; enabled with circuit-specific values
  % after the user selects a Grand Prix in f1_main.
  params.temperatureModel.enabled = false;
  params.temperatureModel.ambientTempC = 25;
  params.temperatureModel.trackTempC = 35;
  params.temperatureModel.trackStress = 3.5;
end

function params = apply_track_profile(params, track)
% APPLY_TRACK_PROFILE Load circuit-specific event priors and thermal settings.
% Values are educational heuristics, not official measured probabilities.
  if isfield(track, 'eventProbabilities')
    params.eventProbabilities = track.eventProbabilities;
    params.temperatureModel.ambientTempC = track.ambientTempC;
    params.temperatureModel.trackTempC = track.trackTempC;
    params.temperatureModel.trackStress = track.trackStress;
  else
    % Custom venue: retain conservative generic defaults.
    params.eventProbabilities.safetyCar = 0.35;
    params.eventProbabilities.vsc = 0.30;
    params.eventProbabilities.redFlag = 0.08;
    params.eventProbabilities.rain = 0.25;
  end
  params.temperatureModel.enabled = true;
end

function scenarios = generate_race_scenarios(params)
% GENERATE_RACE_SCENARIOS Generate reproducible Monte Carlo race scenarios.
% Event probabilities represent the chance of each event occurring per race.

  nLaps = params.nLaps;
  mc = params.monteCarlo;
  nScenarios = mc.nScenarios;
  seed = mc.seed;

  if ~isscalar(nScenarios) || ~isfinite(nScenarios) || ...
      nScenarios < 1 || nScenarios ~= fix(nScenarios)
    error('nScenarios must be a positive integer.');
  end
  if ~isscalar(seed) || ~isfinite(seed) || ...
      seed < 0 || seed ~= fix(seed)
    error('Monte Carlo seed must be a non-negative integer.');
  end
  if ~isscalar(nLaps) || ~isfinite(nLaps) || ...
      nLaps < 2 || nLaps ~= fix(nLaps)
    error('nLaps must be an integer of at least 2.');
  end

  probs = params.eventProbabilities;
  probabilities = [probs.safetyCar, probs.vsc, probs.redFlag, probs.rain];
  if any(~isfinite(probabilities)) || ...
      any(probabilities < 0) || any(probabilities > 1)
    error('Event probabilities must be between 0 and 1.');
  end

  % Preserve the user's random-number state after generation.
  oldRng = rng();
  rngCleanup = onCleanup(@() rng(oldRng));
  rng(double(seed), 'twister');
  scenarios = cell(1, nScenarios);

  for i = 1:nScenarios
    scLaps = [];
    vscLaps = [];
    redFlagLaps = [];
    wetLaps = [];

    % Safety Car: one possible event lasting 1-8 laps.
    if rand() < probs.safetyCar
      firstLap = max(2, ceil(nLaps * 0.15));
      lastLap = max(firstLap, ceil(nLaps * 0.85));
      startLap = randi([firstLap, lastLap]);
      maxDuration = min(8, nLaps - startLap + 1);
      duration = randi([1, maxDuration]);
      scLaps = startLap:min(nLaps, startLap + duration - 1);
    end

    % VSC: one possible event lasting 1-4 laps, not overlapping an SC.
    if rand() < probs.vsc
      startLap = randi([1, nLaps]);
      maxDuration = min(4, nLaps - startLap + 1);
      duration = randi([1, maxDuration]);
      vscLaps = startLap:min(nLaps, startLap + duration - 1);
      vscLaps = setdiff(vscLaps, scLaps);
    end

    % Red flag: one possible event; takes priority over SC/VSC that lap.
    if rand() < probs.redFlag
      firstLap = max(2, ceil(nLaps * 0.20));
      lastLap = max(firstLap, ceil(nLaps * 0.90));
      redFlagLaps = randi([firstLap, lastLap]);
      scLaps = setdiff(scLaps, redFlagLaps);
      vscLaps = setdiff(vscLaps, redFlagLaps);
    end

    % Rain: one possible wet period lasting 1-15 laps.
    if rand() < probs.rain
      startLap = randi([1, nLaps]);
      maxDuration = min(15, nLaps - startLap + 1);
      duration = randi([1, maxDuration]);
      wetLaps = startLap:min(nLaps, startLap + duration - 1);
    end

    ambientScenario = 25;
    trackScenario = 35;
    if isfield(params, 'temperatureModel')
      ambientScenario = params.temperatureModel.ambientTempC + (rand() * 6 - 3);
      trackScenario = params.temperatureModel.trackTempC + (rand() * 10 - 5);
    end
    scenarios{i} = struct( ...
      'scLaps', scLaps, ...
      'vscLaps', vscLaps, ...
      'redFlagLaps', redFlagLaps, ...
      'wetLaps', wetLaps, ...
      'ambientTempC', ambientScenario, ...
      'trackTempC', trackScenario, ...
      'scPaceDelta', 24.0, ...
      'vscPaceDelta', 8.0, ...
      'scPitLossMultiplier', 0.55, ...
      'vscPitLossMultiplier', 0.75, ...
      'redFlagRestartDelay', 90.0, ...
      'rainPenaltySeconds', 7.0, ...
      'wetWearMultiplier', 1.25);
  end
  clear rngCleanup;
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

  % Dedicated views requested for the project presentation: a comparison
  % dashboard, race-pace graph, and tyre-degradation graph. These are kept
  % separate from the four-panel overview so each is legible when presented.
  plot_strategy_comparison_dashboard(results, opts);
  plot_race_pace_graph(bestStrategy, lapTimes, params, opts);
  plot_tyre_degradation_graph(params, bestStrategy, opts);
end

function plot_strategy_comparison_dashboard(results, opts)
% PLOT_STRATEGY_COMPARISON_DASHBOARD Compare pace and reliability side by side.
  if nargin < 2 || isempty(opts), opts = struct(); end
  if ~isfield(opts, 'visible'), opts.visible = 'on'; end
  if ~isfield(opts, 'topN'), opts.topN = 8; end
  if isempty(results), return; end

  [times, order] = sort([results.totalTime]);
  n = min(opts.topN, numel(results));
  order = order(1:n);
  times = times(1:n);
  labels = cell(1,n);
  for i = 1:n
    [sq, pt] = strategy_to_string(results(order(i)), false);
    labels{i} = sprintf('%s (pit %s)', sq, pt);
  end
  gaps = times - times(1);
  hasReliability = isfield(results, 'reliabilityScore') && ...
      any(isfinite([results(order).reliabilityScore]));

  fig = figure('Name', 'F1 Strategy Lab - Strategy Comparison Dashboard', ...
      'NumberTitle', 'off', 'Position', [80 80 1250 720], ...
      'Color', 'w', 'Visible', opts.visible);

  subplot(1,2,1);
  hb = barh(1:n, gaps, 0.72);
  set(hb, 'FaceColor', [0.22 0.48 0.78]);
  set(gca, 'YTick', 1:n, 'YTickLabel', labels, 'YDir', 'reverse');
  xlim([0 max(max(gaps)*1.25, 1)]);
  xlabel('Gap to fastest mean race time (s)');
  title('Race pace: top candidate strategies');
  grid on; box on;
  for i = 1:n
    text(gaps(i), i, sprintf('  +%.2f s', gaps(i)), ...
      'VerticalAlignment', 'middle', 'FontSize', 9);
  end

  subplot(1,2,2);
  if hasReliability
    winRate = 100 * [results(order).winFrequency];
    score = [results(order).reliabilityScore];
    bar(1:n, winRate, 0.45, 'FaceColor', [0.18 0.62 0.42]);
    hold on;
    plot(1:n, score, '-o', 'LineWidth', 2, 'MarkerSize', 5, ...
      'Color', [0.75 0.25 0.20], 'MarkerFaceColor', [0.75 0.25 0.20]);
    hold off;
    ylabel('Win frequency (%) / reliability score');
    ylim([0 100]);
    set(gca, 'XTick', 1:n, 'XTickLabel', labels, 'XTickLabelRotation', 25);
    title('Monte Carlo robustness: wins and reliability score');
    legend({'Win frequency', 'Reliability score'}, 'Location', 'best');
  else
    axis off;
    text(0.05, 0.65, 'Monte Carlo is disabled.', 'FontSize', 13, ...
      'Units', 'normalized');
    text(0.05, 0.52, ...
      'Enable Monte Carlo to compare scenario win frequency and reliability.', ...
      'FontSize', 11, 'Units', 'normalized', 'Interpreter', 'none');
    text(0.05, 0.35, ...
      'Race-time ranking is still available in the left panel.', ...
      'FontSize', 10, 'Units', 'normalized', 'Interpreter', 'none');
  end
  drawnow;
  if isfield(opts, 'saveFile') && ~isempty(opts.saveFile)
    try
      [folder, base, ~] = fileparts(opts.saveFile);
      if isempty(folder), folder = '.'; end
      print(fig, fullfile(folder, [base '_comparison.png']), '-dpng', '-r120');
    catch err
      warning('plot_strategy_comparison_dashboard:saveFailed', ...
        'Could not save comparison dashboard: %s', err.message);
    end
  end
end

function plot_race_pace_graph(bestStrategy, lapTimes, params, opts)
% PLOT_RACE_PACE_GRAPH Lap-by-lap race pace, coloured by tyre stint.
  if nargin < 4 || isempty(opts), opts = struct(); end
  if ~isfield(opts, 'visible'), opts.visible = 'on'; end
  names = {'Soft','Medium','Hard'};
  colours = [0.85 0.13 0.13; 0.95 0.70 0.05; 0.40 0.40 0.40];
  nLaps = numel(lapTimes);
  pitLaps = bestStrategy.pitLaps(:).';
  tyres = bestStrategy.compounds(:).';
  edges = [0, pitLaps, nLaps];
  pace = lapTimes;
  pitIdx = pitLaps(pitLaps >= 1 & pitLaps <= nLaps);
  pace(pitIdx) = pace(pitIdx) - params.pitLoss;

  fig = figure('Name', 'F1 Strategy Lab - Race Pace', 'NumberTitle', 'off', ...
    'Position', [120 100 1050 560], 'Color', 'w', 'Visible', opts.visible);
  hold on; hs = []; labs = {};
  for st = 1:numel(tyres)
    idx = (edges(st)+1):edges(st+1);
    if isempty(idx), continue; end
    c = tyres(st);
    h = plot(idx, pace(idx), '-o', 'Color', colours(c,:), ...
      'LineWidth', 2, 'MarkerSize', 4, 'MarkerFaceColor', colours(c,:));
    if ~any(strcmp(labs, names{c}))
      hs(end+1) = h; labs{end+1} = names{c}; %#ok<AGROW>
    end
  end
  yl = ylim;
  for k = 1:numel(pitLaps)
    h = plot([pitLaps(k)+0.5 pitLaps(k)+0.5], yl, 'k--', 'LineWidth', 1.2);
    if k == 1
      hs(end+1) = h; labs{end+1} = 'Pit stop'; %#ok<AGROW>
    end
  end
  hold off; grid on; box on;
  xlim([1 nLaps]); xlabel('Race lap');
  ylabel('Lap time (s), pit-stop loss excluded');
  title('Race pace by lap and tyre compound');
  if ~isempty(hs), legend(hs, labs, 'Location', 'best'); end
  drawnow;
  if isfield(opts, 'saveFile') && ~isempty(opts.saveFile)
    try
      [folder, base, ~] = fileparts(opts.saveFile);
      if isempty(folder), folder = '.'; end
      print(fig, fullfile(folder, [base '_race_pace.png']), '-dpng', '-r120');
    catch err
      warning('plot_race_pace_graph:saveFailed', 'Could not save race-pace graph: %s', err.message);
    end
  end
end

function plot_tyre_degradation_graph(params, bestStrategy, opts)
% PLOT_TYRE_DEGRADATION_GRAPH Plot modelled time loss versus tyre age.
  if nargin < 3 || isempty(opts), opts = struct(); end
  if ~isfield(opts, 'visible'), opts.visible = 'on'; end
  names = {'Soft','Medium','Hard'};
  colours = [0.85 0.13 0.13; 0.95 0.70 0.05; 0.40 0.40 0.40];
  nLaps = params.nLaps;
  pitLaps = bestStrategy.pitLaps(:).';
  tyres = bestStrategy.compounds(:).';
  edges = [0, pitLaps, nLaps];
  maxAge = max(nLaps, max(diff(edges)));
  ages = 0:maxAge;

  fig = figure('Name', 'F1 Strategy Lab - Tyre Degradation', 'NumberTitle', 'off', ...
    'Position', [140 120 1050 560], 'Color', 'w', 'Visible', opts.visible);
  hold on;
  for c = 1:3
    freshTime = calculate_lap_time(0, 0, c, params);
    loss = zeros(size(ages));
    for j = 1:numel(ages)
      loss(j) = calculate_lap_time(ages(j), 0, c, params) - freshTime;
    end
    plot(ages, loss, '-', 'Color', colours(c,:), 'LineWidth', 2.2);
  end
  % Mark the maximum tyre age reached in each stint of the winning strategy.
  for st = 1:numel(tyres)
    stintLength = edges(st+1) - edges(st);
    c = tyres(st);
    plot(stintLength, calculate_lap_time(stintLength, 0, c, params) - ...
      calculate_lap_time(0, 0, c, params), 'o', 'Color', colours(c,:), ...
      'MarkerFaceColor', colours(c,:), 'MarkerSize', 7);
  end
  hold off; grid on; box on;
  xlabel('Tyre age (laps on current set)');
  ylabel('Modelled lap-time loss vs fresh tyre (s)');
  title('Tyre degradation by compound (fuel effect excluded)');
  legend(names, 'Location', 'northwest');
  drawnow;
  if isfield(opts, 'saveFile') && ~isempty(opts.saveFile)
    try
      [folder, base, ~] = fileparts(opts.saveFile);
      if isempty(folder), folder = '.'; end
      print(fig, fullfile(folder, [base '_tyre_degradation.png']), '-dpng', '-r120');
    catch err
      warning('plot_tyre_degradation_graph:saveFailed', ...
        'Could not save tyre-degradation graph: %s', err.message);
    end
  end
end

%% =====================================================================
%  MEMBER 4 - MAIN PROGRAM
%% =====================================================================
%% =====================================================================
%%  HISTORICAL STRATEGY REFERENCE
%% =====================================================================
function history = historical_strategy_database()
% HISTORICAL_STRATEGY_DATABASE Compact reference summaries.
% 2025 records below are transcribed from PITWALL's processed race-strategy
% table (finishers only, at least 90% race distance). COTA 2022-2024 examples
% are from McLaren Racing's retrospective. Coverage is intentionally explicit:
% missing seasons are not fabricated. Tyre codes: 1 Soft, 2 Medium, 3 Hard,
% 4 Intermediate, 5 Wet. Source: https://www.pitwall.info/f1-tyre-strategy/
% COTA source: https://www.mclaren.com/racing/formula-1/2025/2025-strategy-trends/
  gp = { ...
    'Abu Dhabi','Qatar','Las Vegas','São Paulo','Mexico City','United States - Austin', ...
    'Singapore','Azerbaijan','Italy - Monza','Netherlands','Hungary','Belgium', ...
    'Great Britain','Austria','Canada','Spain - Barcelona','Monaco','Emilia Romagna', ...
    'Miami','Saudi Arabia','Bahrain','Japan','China','Australia'};
  seq = { ...
    'Medium -> Hard','Medium -> Medium -> Hard','Medium -> Hard','Medium -> Soft -> Medium', ...
    'Medium -> Soft','Medium -> Soft','Medium -> Hard','Hard -> Medium','Medium -> Hard', ...
    'Medium -> Hard -> Soft','Medium -> Hard','Intermediate -> Medium', ...
    'Intermediate -> Intermediate -> Medium','Medium -> Hard -> Medium','Medium -> Hard -> Hard', ...
    'Soft -> Medium -> Soft -> Soft','Medium -> Hard -> Hard','Medium -> Hard -> Hard', ...
    'Medium -> Hard','Medium -> Hard','Soft -> Medium -> Hard','Medium -> Hard', ...
    'Medium -> Hard','Intermediate -> Hard -> Intermediate'};
  finishers = [20 18 17 17 17 19 20 19 18 17 19 20 15 16 18 17 18 18 16 18 19 20 19 14];
  stops1 = [14 0 14 1 11 17 17 16 18 3 10 14 6 2 7 0 0 2 16 17 0 19 13 0];
  stops2 = [6 16 2 13 6 2 2 2 0 11 8 6 9 13 9 3 17 15 0 1 17 1 4 12];
  history = struct('year', {}, 'grandPrix', {}, 'commonStrategy', {}, ...
                   'finishers', {}, 'oneStopFinishers', {}, 'twoStopFinishers', {}, 'source', {});
  for k = 1:numel(gp)
    history(end+1) = struct('year', 2025, 'grandPrix', gp{k}, ...
      'commonStrategy', seq{k}, 'finishers', finishers(k), ...
      'oneStopFinishers', stops1(k), 'twoStopFinishers', stops2(k), ...
      'source', 'PITWALL processed race-strategy table');
  end
  % Known COTA trend records for four recent seasons, retained separately.
  history(end+1) = struct('year', 2022, 'grandPrix', 'United States - Austin', ...
    'commonStrategy', 'Medium -> Hard -> Medium', 'finishers', NaN, ...
    'oneStopFinishers', NaN, 'twoStopFinishers', NaN, ...
    'source', 'McLaren Racing 2025 strategy retrospective');
  history(end+1) = struct('year', 2023, 'grandPrix', 'United States - Austin', ...
    'commonStrategy', 'Medium -> Medium -> Hard', 'finishers', NaN, ...
    'oneStopFinishers', NaN, 'twoStopFinishers', NaN, ...
    'source', 'McLaren Racing 2025 strategy retrospective');
  history(end+1) = struct('year', 2024, 'grandPrix', 'United States - Austin', ...
    'commonStrategy', 'Medium -> Hard', 'finishers', NaN, ...
    'oneStopFinishers', NaN, 'twoStopFinishers', NaN, ...
    'source', 'McLaren Racing 2025 strategy retrospective');
end

function print_historical_strategies(trackName)
% PRINT_HISTORICAL_STRATEGIES Show sourced reference data for the selected GP.
  history = historical_strategy_database();
  key = lower(trackName);
  if ~isempty(strfind(key, 'austin')) || ~isempty(strfind(key, 'united states'))
    wanted = 'United States - Austin';
  elseif ~isempty(strfind(key, 'abu dhabi'))
    wanted = 'Abu Dhabi';
  elseif ~isempty(strfind(key, 'qatar'))
    wanted = 'Qatar';
  elseif ~isempty(strfind(key, 'las vegas'))
    wanted = 'Las Vegas';
  elseif ~isempty(strfind(key, 'são paulo')) || ~isempty(strfind(key, 'sao paulo'))
    wanted = 'São Paulo';
  elseif ~isempty(strfind(key, 'mexico'))
    wanted = 'Mexico City';
  elseif ~isempty(strfind(key, 'singapore'))
    wanted = 'Singapore';
  elseif ~isempty(strfind(key, 'azerbaijan')) || ~isempty(strfind(key, 'baku'))
    wanted = 'Azerbaijan';
  elseif ~isempty(strfind(key, 'monza')) || ~isempty(strfind(key, 'italian'))
    wanted = 'Italy - Monza';
  elseif ~isempty(strfind(key, 'netherlands')) || ~isempty(strfind(key, 'dutch')) || ~isempty(strfind(key, 'zandvoort'))
    wanted = 'Netherlands';
  elseif ~isempty(strfind(key, 'hungary')) || ~isempty(strfind(key, 'budapest'))
    wanted = 'Hungary';
  elseif ~isempty(strfind(key, 'belgium')) || ~isempty(strfind(key, 'spa'))
    wanted = 'Belgium';
  elseif ~isempty(strfind(key, 'british')) || ~isempty(strfind(key, 'silverstone'))
    wanted = 'Great Britain';
  elseif ~isempty(strfind(key, 'austria')) || ~isempty(strfind(key, 'spielberg'))
    wanted = 'Austria';
  elseif ~isempty(strfind(key, 'canada')) || ~isempty(strfind(key, 'montreal'))
    wanted = 'Canada';
  elseif ~isempty(strfind(key, 'barcelona'))
    wanted = 'Spain - Barcelona';
  elseif ~isempty(strfind(key, 'monaco'))
    wanted = 'Monaco';
  elseif ~isempty(strfind(key, 'imola') ) || ~isempty(strfind(key, 'emilia romagna'))
    wanted = 'Emilia Romagna';
  elseif ~isempty(strfind(key, 'miami'))
    wanted = 'Miami';
  elseif ~isempty(strfind(key, 'saudi')) || ~isempty(strfind(key, 'jeddah'))
    wanted = 'Saudi Arabia';
  elseif ~isempty(strfind(key, 'bahrain'))
    wanted = 'Bahrain';
  elseif ~isempty(strfind(key, 'japan')) || ~isempty(strfind(key, 'suzuka'))
    wanted = 'Japan';
  elseif ~isempty(strfind(key, 'china')) || ~isempty(strfind(key, 'shanghai'))
    wanted = 'China';
  elseif ~isempty(strfind(key, 'australia')) || ~isempty(strfind(key, 'melbourne'))
    wanted = 'Australia';
  else
    wanted = '';
  end
  matches = [];
  for k = 1:numel(history)
    if strcmpi(history(k).grandPrix, wanted), matches(end+1) = k; end
  end
  fprintf('\nRECENT HISTORICAL STRATEGY REFERENCE\n');
  fprintf('Source data coverage varies by venue; unavailable seasons are not guessed.\n');
  if isempty(matches)
    fprintf('No sourced strategy summary is bundled for this venue yet.\n\n');
    return;
  end
  for j = 1:numel(matches)
    h = history(matches(j));
    fprintf('  %d: %s\n', h.year, h.commonStrategy);
    if isfinite(h.finishers)
      fprintf('     Finishers counted: %d; one-stop finishers: %d; two-stop finishers: %d\n', ...
        h.finishers, h.oneStopFinishers, h.twoStopFinishers);
    end
  end
  fprintf('  Source: %s\n\n', history(matches(end)).source);
end

%% =====================================================================
%%  MEMBER 4 - MAIN PROGRAM
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

  % ---------- 2. choose a Grand Prix / circuit -----------------------------
  trackName = 'Default educational race';
  if ~batchMode
    [track, isCustom] = select_grand_prix();
    trackName = track.name;
    if isCustom
      fprintf('Custom race defaults: %d laps, pit-stop loss %.1f s.\n', ...
              track.nLaps, track.pitLoss);
      newLaps = ask_number('Race distance in laps', track.nLaps, 10, 100, true);
      newPitLoss = ask_number('Estimated pit-stop loss in seconds', ...
                              track.pitLoss, 10, 40, false);
    else
      newLaps = track.nLaps;
      newPitLoss = track.pitLoss;
      fprintf('Selected: %s\n', track.name);
      fprintf('Track database: %d laps; estimated pit-lane loss %.1f s.\n', ...
              newLaps, newPitLoss);
      change = input('Override laps / pit-loss estimates? (y/n) [n]: ', 's');
      if strcmpi(strtrim(change), 'y')
        newLaps = ask_number('Race distance in laps', newLaps, 10, 100, true);
        newPitLoss = ask_number('Estimated pit-stop loss in seconds', ...
                                newPitLoss, 10, 40, false);
      end
    end
    params = default_params(newLaps, newPitLoss);  % fuel scales with distance
    params = apply_track_profile(params, track);
    fprintf('\n');
    showHistory = input('Show available recent real-world strategy reference? (y/n) [y]: ', 's');
    if isempty(strtrim(showHistory)) || strcmpi(strtrim(showHistory), 'y')
      print_historical_strategies(trackName);
    end
    mcChoice = input('Enable Monte Carlo event simulation? (y/n) [n]: ', 's');
    if strcmpi(strtrim(mcChoice), 'y')
      params.monteCarlo.enabled = true;
      params.monteCarlo.nScenarios = ask_number( ...
          'Number of Monte Carlo scenarios (more = slower)', 3, 2, 20, true);
      fprintf('Monte Carlo enabled with %d shared race scenarios.\n', ...
          params.monteCarlo.nScenarios);
    end
  end

  fprintf('TRACK: %s\n', trackName);
  fprintf('EVENT PRIORS (heuristic assumptions, not official historical rates): SC %.0f%% | VSC %.0f%% | red flag %.0f%% | rain %.0f%%\n', ...
      100*params.eventProbabilities.safetyCar, 100*params.eventProbabilities.vsc, ...
      100*params.eventProbabilities.redFlag, 100*params.eventProbabilities.rain);
  if isfield(params, 'temperatureModel') && params.temperatureModel.enabled
    fprintf('WEATHER MODEL: ambient %.1f C | track %.1f C | tyre-stress index %.1f/5\n', ...
      params.temperatureModel.ambientTempC, params.temperatureModel.trackTempC, ...
      params.temperatureModel.trackStress);
  end
  fprintf('MODEL PARAMETERS  (educational values; pit loss is an estimate)\n%s\n', thin);
  fprintf('  Race distance : %d laps        Pit-stop loss : %.1f s\n', ...
          params.nLaps, params.pitLoss);
  fprintf('  Fuel          : %.1f kg at start, %.1f kg/lap burn, %.3f s per kg\n', ...
          params.fuelInitial, params.fuelPerLap, params.fuelCoeff);
  % Interactive runs use fast search; batch/self-test mode stays exhaustive.
  params.search.fastEnabled = ~batchMode;
  params.search.refineTopK = 8;
  if params.search.fastEnabled
    searchLabel = 'fast coarse-to-fine';
  else
    searchLabel = 'exhaustive';
  end
  fprintf('  Search        : %s, 1-stop, 2-stop, and 3-stop, min stint %d laps\n\n', ...
          searchLabel, params.minStintLength);
  fprintf('  %-8s %10s %16s %18s\n', 'Tyre', 'Base (s)', 'Wear A (s/lap)', 'Wear B (s/lap^2)');
  for c = 1:3
    fprintf('  %-8s %10.2f %16.4f %18.5f\n', tyreNames{c}, params.baseTime(c), ...
            params.degradationA(c), params.degradationB(c));
  end
  fprintf('%s\n\n', thin);

  % ---------- size of the search + time estimate ---------------------------
  % Interactive runs use the coarse-to-fine optimizer to avoid very long
  % exhaustive searches. Batch/self-test mode preserves exact exhaustive behavior.
  N  = params.nLaps;
  m  = params.minStintLength;
  nC = numel(params.availableCompounds);
  nCand = max(N - 2*m + 1, 0) * nC^2;
  if N >= 3*m
    nCand = nCand + (N - 3*m + 2) * (N - 3*m + 1) / 2 * nC^3;
  end
  if N >= 4*m
    nCand = nCand + nchoosek(N - 4*m + 3, 3) * nC^4;
  end
  if params.search.fastEnabled
    strideEstimate = max(2, ceil(N / 12));
    nOneCoarse = numel(minStint:strideEstimate:(N-minStint));
    grid = minStint:strideEstimate:(N-minStint);
    nTwoCoarse = 0;
    nThreeCoarse = 0;
    for aa = 1:numel(grid)
      for bb = aa+1:numel(grid)
        if grid(bb)-grid(aa) >= m && N-grid(bb) >= m
          nTwoCoarse = nTwoCoarse + 1;
        end
        for cc = bb+1:numel(grid)
          if grid(bb)-grid(aa) >= m && grid(cc)-grid(bb) >= m && N-grid(cc) >= m
            nThreeCoarse = nThreeCoarse + 1;
          end
        end
      end
    end
    nCand = nOneCoarse*nC^2 + nTwoCoarse*nC^3 + nThreeCoarse*nC^4 + ...
            params.search.refineTopK*27*nC^4;
  end

  probe.pitLaps   = floor(N / 2);                % time 3 trial simulations
  probe.compounds = [1 1];
  tic;
  for k = 1:3
    simulate_strategy(probe, params);
  end
  estSeconds = (toc / 3) * nCand;
  if isfield(params, 'monteCarlo') && params.monteCarlo.enabled
    estSeconds = estSeconds * params.monteCarlo.nScenarios;
  end

  fprintf('Candidate strategies to evaluate : %d\n', nCand);
  if isfield(params, 'monteCarlo') && params.monteCarlo.enabled
    fprintf('Monte Carlo scenario count       : %d (shared across all candidates)\n', ...
            params.monteCarlo.nScenarios);
  end
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
  fprintf('\nSearching one-stop, two-stop, and three-stop strategies...\n');
  fflush(stdout);
  tic;
  [bestStrategy, bestTime, results] = optimize_strategy(params);
  searchSeconds = toc;
  fprintf('Done: %d strategies evaluated in %.1f s.\n', numel(results), searchSeconds);

  if isempty(results) || ~isfinite(bestTime) || isempty(bestStrategy.pitLaps)
    fprintf('\nNo feasible strategy exists for these settings.\n');
    fprintf('Try a longer race or a smaller minimum stint length.\n');
    out = struct('params', params, 'trackName', trackName, ...
                 'bestStrategy', bestStrategy, 'bestTime', bestTime, ...
                 'results', results);
    return;
  end

  % ---------- 4. re-simulate the winner for lap-by-lap data ----------------
  if isfield(params, 'monteCarlo') && params.monteCarlo.enabled
    % Recreate the same seeded scenarios used by the optimizer and average
    % lap-by-lap outputs so the reported total agrees with the objective.
    scenariosForWinner = generate_race_scenarios(params);
    scenarioTotals = zeros(1, numel(scenariosForWinner));
    lapMatrix = zeros(numel(scenariosForWinner), params.nLaps);
    ageMatrix = zeros(numel(scenariosForWinner), params.nLaps);
    fuelMatrix = zeros(numel(scenariosForWinner), params.nLaps);
    for sc = 1:numel(scenariosForWinner)
      scenarioParams = params;
      scenarioParams.raceScenario = scenariosForWinner{sc};
      [scenarioTotals(sc), lapMatrix(sc,:), ageMatrix(sc,:), fuelMatrix(sc,:)] = ...
          simulate_strategy(bestStrategy, scenarioParams);
    end
    totalTime = mean(scenarioTotals);
    lapTimes = mean(lapMatrix, 1);
    tyreAges = mean(ageMatrix, 1);
    fuelLoads = mean(fuelMatrix, 1);
  else
    [totalTime, lapTimes, tyreAges, fuelLoads] = simulate_strategy(bestStrategy, params);
  end
  if abs(totalTime - bestTime) > 1e-7
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
  if isfield(params, 'monteCarlo') && params.monteCarlo.enabled
    fprintf('STINT BREAKDOWN (scenario-averaged lap-time profile)\n%s\n', thin);
  else
    fprintf('STINT BREAKDOWN\n%s\n', thin);
  end
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
  if isfield(params, 'monteCarlo') && params.monteCarlo.enabled
    fprintf('\nMONTE CARLO RELIABILITY (same scenarios used for every strategy)\n%s\n', thin);
    fprintf('  Score formula: 70%% scenario win frequency + 30%% relative consistency.\n');
    fprintf('  Consistency is normalized within this candidate set; score is model-relative.\n');
    fprintf('  %-5s %-10s %-12s %-12s %-12s\n', 'Rank', 'Tyres', 'Win rate', 'Std dev (s)', 'Score / 100');
    for i = 1:min(5, numel(ranked))
      fprintf('  %-5d %-10s %10.1f%% %12.3f %12.1f\n', i, ...
          strategy_to_string(ranked(i), false), 100*ranked(i).winFrequency, ...
          ranked(i).scenarioStdSeconds, ranked(i).reliabilityScore);
    end
    fprintf('  Higher score indicates more frequent scenario wins and/or more consistent times.\n');
  else
    fprintf('\nReliability metrics unavailable: enable Monte Carlo to evaluate strategies across varied race scenarios.\n');
  end
  fprintf('%s\n\n', thin);

  i1 = find(stopsRanked == 1, 1);
  i2 = find(stopsRanked == 2, 1);
  if ~isempty(i1) && ~isempty(i2)
    fprintf('BEST ONE-STOP vs BEST TWO-STOP vs BEST THREE-STOP\n%s\n', thin);
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
  out.trackName    = trackName;
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

  % ---- A2. Grand Prix database -----------------------------------------------
  tracks = track_database();
  trackNames = {tracks.name};
  iSilverstone = find(strcmp(trackNames, 'British Grand Prix - Silverstone'), 1);
  iVegas = find(strcmp(trackNames, 'Las Vegas Grand Prix'), 1);
  iAustin = find(strcmp(trackNames, 'United States Grand Prix - Austin'), 1);
  iChina = find(strcmp(trackNames, 'Chinese Grand Prix - Shanghai'), 1);
  assert(~isempty(iSilverstone) && tracks(iSilverstone).nLaps == 52, ...
         'Silverstone database entry is missing or incorrect.');
  assert(~isempty(iVegas) && tracks(iVegas).nLaps == 50, ...
         'Las Vegas database entry is missing or incorrect.');
  assert(~isempty(iAustin) && tracks(iAustin).nLaps == 56, ...
         'Austin database entry is missing or incorrect.');
  assert(~isempty(iChina) && tracks(iChina).nLaps == 56, ...
         'Shanghai database entry is missing or incorrect.');
  assert(tracks(iSilverstone).pitLoss > 0 && tracks(iVegas).pitLoss > 0, ...
         'Pit-loss estimates must be positive.');
  assert(numel(tracks) == 24, 'Database should contain all 24 announced 2026 venues.');
  assert(any(strcmp(trackNames, 'Miami Grand Prix')), 'Miami entry missing.');
  assert(any(strcmp(trackNames, 'Spanish Grand Prix - Madrid')), 'Madrid entry missing.');
  assert(any(strcmp(trackNames, 'Saudi Arabian Grand Prix - Jeddah')), 'Jeddah entry missing.');
  assert(any(strcmp(trackNames, 'Bahrain Grand Prix - Sakhir')), 'Bahrain entry missing.');
  assert(isfield(tracks(iSilverstone), 'eventProbabilities') && ...
         tracks(iSilverstone).eventProbabilities.safetyCar >= 0 && ...
         tracks(iSilverstone).eventProbabilities.safetyCar <= 1, ...
         'Circuit-specific event probabilities missing/invalid.');
  hist = historical_strategy_database();
  assert(any([hist.year] == 2025), 'Historical strategy reference missing 2025 data.');
  fprintf('[PASS] A2. Grand Prix database entries (%d venues)\n', numel(tracks));

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

  % Thermal model should be finite and must affect time when enabled.
  thermalParams = default_params(12, 22.0);
  thermalParams.temperatureModel.enabled = true;
  thermalParams.temperatureModel.ambientTempC = 28;
  thermalParams.temperatureModel.trackTempC = 43;
  thermalParams.temperatureModel.trackStress = 4.0;
  thermalStrategy.pitLaps = 6; thermalStrategy.compounds = [2 3];
  thermalTime = simulate_strategy(thermalStrategy, thermalParams);
  assert(isfinite(thermalTime) && thermalTime > 0, 'Thermal model returned invalid time.');
  fprintf('[PASS] C3. Tyre-temperature / weather model smoke test\n');

  % ---- C2. Monte Carlo scenario generation and simulator integration --------
  mcParams = default_params(12, 22.0);
  mcParams.monteCarlo.nScenarios = 8;
  mcParams.monteCarlo.seed = 12345;
  scenariosA = generate_race_scenarios(mcParams);
  scenariosB = generate_race_scenarios(mcParams);
  assert(isequal(scenariosA, scenariosB), ...
         'Monte Carlo scenarios must be reproducible for a fixed seed.');

  mcStrategy.pitLaps = 6;
  mcStrategy.compounds = [2 3];
  mcParams.raceScenario = scenariosA{1};
  [mcTime, mcLapTimes, mcTyreAges, mcFuelLoads] = ...
      simulate_strategy(mcStrategy, mcParams);
  assert(isfinite(mcTime) && abs(mcTime - sum(mcLapTimes)) < tol, ...
         'Scenario simulation returned invalid time outputs.');
  assert(numel(mcLapTimes) == 12 && numel(mcTyreAges) == 12 && ...
         numel(mcFuelLoads) == 12, 'Scenario simulation output lengths are wrong.');

  cleanScenario = struct('scLaps', [], 'vscLaps', [], ...
                         'redFlagLaps', [], 'wetLaps', []);
  mcParams.raceScenario = cleanScenario;
  plainParams = rmfield(mcParams, 'raceScenario');
  plainTime = simulate_strategy(mcStrategy, plainParams);
  cleanTime = simulate_strategy(mcStrategy, mcParams);
  assert(abs(plainTime - cleanTime) < tol, ...
         'An empty scenario must preserve legacy simulator behaviour.');
  fprintf('[PASS] C2. Monte Carlo: reproducibility, simulation, legacy compatibility\n');

  % ---- D. optimize_strategy (Member 3) --------------------------------------
  [bs, bt, res] = optimize_strategy(p);
  N = p.nLaps; m = p.minStintLength; C = numel(p.availableCompounds);
  expected = (N-2*m+1)*C^2 + (N-3*m+2)*(N-3*m+1)/2 * C^3;
  if N >= 4*m
    expected = expected + nchoosek(N-4*m+3, 3) * C^4;
  end
  assert(numel(res) == expected, 'Candidate count differs from 1/2/3-stop formula.');
  assert(abs(bt - min([res.totalTime])) < tol, 'bestTime must be the minimum.');
  assert(all(diff([0 bs.pitLaps N]) >= m), 'Best strategy has a too-short stint.');
  assert(numel(bs.compounds) == numel(bs.pitLaps) + 1, 'One compound per stint.');
  assert(numel(bs.pitLaps) <= 3, 'Optimizer must not exceed three pit stops.');
  for k = 1:100:numel(res)                       % spot-check stored times
    chk = simulate_strategy(struct('pitLaps', res(k).pitLaps, ...
                                   'compounds', res(k).compounds), p);
    assert(abs(chk - res(k).totalTime) < tol, 'Stored time differs from simulation.');
  end
  [bs2, bt2] = optimize_strategy(p);
  assert(isequal(bs2, bs) && bt2 == bt, 'Search must be reproducible.');
  % Regression: default optimum remains finite and structurally valid after adding 3-stop candidates.
  assert(isfinite(bt) && numel(bs.compounds) == numel(bs.pitLaps) + 1, ...
         'Unexpected optimizer output structure.');
  warning('off', 'optimize_strategy:noFeasible');
  [bs3, bt3, r3] = optimize_strategy(default_params(5, 22));  % too short to pit twice
  warning('on', 'optimize_strategy:noFeasible');
  assert(isinf(bt3) && isempty(bs3.pitLaps) && isempty(r3), 'Infeasible case mishandled.');
  fprintf('[PASS] D. optimize_strategy: count %d, minimum, reproducible, infeasible case\n', ...
          numel(res));

  % Small optimizer smoke test keeps Monte Carlo testing inexpensive.
  mcOptParams = default_params(9, 22.0);
  mcOptParams.availableCompounds = [2 3];
  mcOptParams.monteCarlo.enabled = true;
  mcOptParams.monteCarlo.nScenarios = 2;
  mcOptParams.monteCarlo.seed = 321;
  [mcBest, mcBestTime, mcResults] = optimize_strategy(mcOptParams);
  assert(isfinite(mcBestTime) && ~isempty(mcResults) && ...
         numel(mcBest.compounds) == numel(mcBest.pitLaps) + 1, ...
         'Monte Carlo optimizer integration failed.');
  assert(all(isfinite([mcResults.reliabilityScore])) && ...
         all([mcResults.reliabilityScore] >= 0 & [mcResults.reliabilityScore] <= 100), ...
         'Reliability scores must be finite and in [0,100].');
  assert(all([mcResults.winFrequency] >= 0 & [mcResults.winFrequency] <= 1), ...
         'Win frequencies must be in [0,1].');
  assert(all(isfinite([mcResults.scenarioStdSeconds])), ...
         'Scenario standard deviations must be finite.');
  fprintf('[PASS] D2. Monte Carlo optimizer + reliability metrics\n');

  % ---- E. whole application in silent batch mode ------------------------------
  out = f1_main(true);
  assert(abs(out.totalTime - out.bestTime) < tol, 'Re-simulated time must match optimizer.');
  assert(abs(sum(out.lapTimes) - out.totalTime) < tol, 'Sum of laps.');
  assert(all(diff(out.fuelLoads) < 0) && all(out.fuelLoads >= 0), 'Fuel must fall, never < 0.');
  fprintf('[PASS] E. main program end-to-end (plots drawn off-screen)\n');

  fprintf('\nALL SELF-TESTS PASSED.\n\n');
end

%% WEB INTEGRATION NOTE
% Interactive CLI entry point removed: Flask calls the model functions directly.
