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
