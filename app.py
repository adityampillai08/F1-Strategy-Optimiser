from flask import Flask, render_template, request, jsonify
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent
ENGINE_FILE = APP_DIR / "f1_strategy_lab.m"
app = Flask(__name__)

def octave_quote(value: str) -> str:
    """Quote a path for an Octave single-quoted string."""
    return str(value).replace("'", "''")

def run_octave_simulation(settings):
    octave = shutil.which("octave")
    if not octave:
        raise RuntimeError(
            "GNU Octave was not found. Install it and make sure the `octave` command "
            "works in your terminal, then restart Flask."
        )

    laps = int(settings.get("laps", 30))
    pit_loss = float(settings.get("pitLoss", 22.0))
    require_two = bool(settings.get("requireTwoCompounds", True))

    if not 10 <= laps <= 60:
        raise ValueError("Race distance must be between 10 and 60 laps.")
    if not 10 <= pit_loss <= 40:
        raise ValueError("Pit-stop loss must be between 10 and 40 seconds.")

    with tempfile.TemporaryDirectory(prefix="f1lab_") as tmp:
        tmp_path = Path(tmp)
        input_path = tmp_path / "settings.json"
        output_path = tmp_path / "result.json"
        driver_path = tmp_path / "web_driver.m"
        input_path.write_text(json.dumps({
            "laps": laps,
            "pitLoss": pit_loss,
            "requireTwoCompounds": require_two
        }), encoding="utf-8")

        # The driver is created per request so simultaneous requests don't overwrite each other.
        driver = f"""
addpath('{octave_quote(APP_DIR / 'engine')}');
source('{octave_quote(APP_DIR / 'engine' / 'v5_reliability_web.m')}');
cfg = jsondecode(fileread('{octave_quote(input_path)}'));
params = default_params(cfg.laps, cfg.pitLoss);
params.temperatureModel.enabled = true;
params.requireTwoCompounds = logical(cfg.requireTwoCompounds);
% Three-stop search grows quickly; use deterministic coarse-to-fine search in the web UI.
params.search.fastEnabled = true;
params.search.refineTopK = 8;
[bestStrategy, bestTime, results] = optimize_strategy(params);
if isempty(results) || ~isfinite(bestTime) || isempty(bestStrategy.pitLaps)
  error('No feasible strategy found for these settings.');
end
[totalTime, lapTimes, tyreAges, fuelLoads] = simulate_strategy(bestStrategy, params);
[sortedTimes, order] = sort([results.totalTime]);
topCount = min(10, numel(order));
top = struct('rank', {{}}, 'pitLaps', {{}}, 'compounds', {{}}, 'totalTime', {{}}, 'gap', {{}});
for i = 1:topCount
  r = results(order(i));
  top(i).rank = i;
  top(i).pitLaps = r.pitLaps;
  top(i).compounds = r.compounds;
  top(i).totalTime = r.totalTime;
  top(i).gap = r.totalTime - sortedTimes(1);
  if isfield(r, 'reliabilityScore'), top(i).reliabilityScore = r.reliabilityScore; else, top(i).reliabilityScore = NaN; end
  if isfield(r, 'winFrequency'), top(i).winFrequency = r.winFrequency; else, top(i).winFrequency = NaN; end
  if isfield(r, 'scenarioStdSeconds'), top(i).scenarioStdSeconds = r.scenarioStdSeconds; else, top(i).scenarioStdSeconds = NaN; end
end
out = struct();
out.nLaps = params.nLaps;
out.pitLoss = params.pitLoss;
out.totalTime = totalTime;
out.averageLap = totalTime / params.nLaps;
out.bestStrategy = bestStrategy;
out.lapTimes = lapTimes;
out.tyreAges = tyreAges;
out.fuelLoads = fuelLoads;
out.topStrategies = top;
out.candidatesEvaluated = numel(results);
out.compoundNames = {{'Soft', 'Medium', 'Hard'}};
out.modelParams = struct('baseTime', params.baseTime, 'degradationA', params.degradationA, 'degradationB', params.degradationB, 'fuelCoeff', params.fuelCoeff, 'fuelPerLap', params.fuelPerLap, 'fuelInitial', params.fuelInitial);
if isfield(params, 'temperatureModel'), out.temperatureModel = params.temperatureModel; end
out.success = true;
fid = fopen('{octave_quote(output_path)}', 'w');
fprintf(fid, '%s', jsonencode(out));
fclose(fid);
"""
        driver_path.write_text(driver, encoding="utf-8")

        cmd = [octave, "--quiet", "--no-gui", str(driver_path)]
        proc = subprocess.run(
            cmd, cwd=str(APP_DIR), capture_output=True, text=True, timeout=180
        )
        if proc.returncode != 0 or not output_path.exists():
            details = (proc.stderr or proc.stdout or "No details returned by Octave").strip()
            raise RuntimeError("Octave simulation failed. " + details[-1800:])
        try:
            return json.loads(output_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            raise RuntimeError("Octave returned an unreadable result. " + str(exc))

@app.get("/")
def index():
    return render_template("index.html")

@app.get("/race-simulation")
def race_simulation():
    return render_template("race_simulation.html")

@app.get("/api/health")
def health():
    return jsonify({"ok": True, "octaveAvailable": shutil.which("octave") is not None})

@app.post("/api/optimize")
def optimize():
    settings = request.get_json(silent=True) or {}
    try:
        result = run_octave_simulation(settings)
        return jsonify(result)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400
    except subprocess.TimeoutExpired:
        return jsonify({"error": "The optimization took too long. Try a shorter race distance."}), 504
    except Exception as exc:
        return jsonify({"error": str(exc)}), 500

if __name__ == "__main__":
    app.run(debug=True, port=5000)
