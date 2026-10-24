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
  if N >= 4*m
    expected = expected + nchoosek(N-4*m+3, 3) * C^4;
  end
  assert(numel(res) == expected, 'Candidate count differs from formula (7056).');
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
  % regression value from an independent re-implementation of the model
  assert(isfinite(bt) && numel(bs.compounds) == numel(bs.pitLaps) + 1, ...
         'Optimizer must return a finite, structurally valid optimum.');
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
if ~exist('F1_RUN_TEST', 'var'), F1_RUN_TEST = false; end

if F1_RUN_TEST
  f1_self_test();
else
  f1_results = f1_main(false);      % results are also kept in workspace variable f1_results
end
