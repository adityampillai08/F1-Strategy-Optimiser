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
