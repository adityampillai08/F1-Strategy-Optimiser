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
