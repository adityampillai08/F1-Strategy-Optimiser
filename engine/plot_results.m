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
