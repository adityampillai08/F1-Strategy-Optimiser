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
