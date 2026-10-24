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
