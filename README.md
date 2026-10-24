# F1 Strategy Lab — Web Frontend

A dark motorsport-style web interface for your existing GNU Octave F1 Strategy Lab simulation.

## What is included

- `app.py` — Flask web server and JSON API
- `templates/index.html` — page structure
- `static/style.css` — responsive dark racing UI
- `static/app.js` — controls, API calls, strategy rendering and lap-time chart
- `f1_strategy_lab.m` — a copy of your original integrated Octave script for reference and standalone use
- `engine/` — the same engine functions split into individual `.m` files so Flask can call them reliably without triggering the command-line UI

The tyre and fuel model and optimizer remain in Octave. This project is an educational simulation using hypothetical values, not a real F1 prediction.

## Requirements

- Python 3.10 or newer
- GNU Octave installed and accessible as `octave` in your terminal
- Internet connection for the Google Fonts and Chart.js CDN used by the UI (the app can be adapted to bundle these locally)

## macOS setup

1. Extract this project folder.
2. Open Terminal and `cd` into the extracted `f1_strategy_lab_web` folder.
3. Check Octave:

   ```bash
   octave --version
   ```

   If the command is missing, install GNU Octave using your preferred package manager or the official GNU Octave distribution. On a Mac with Homebrew, you can usually run:

   ```bash
   brew install octave
   ```

4. Create and activate a Python virtual environment:

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   ```

5. Install Flask:

   ```bash
   python -m pip install --upgrade pip
   python -m pip install -r requirements.txt
   ```

6. Start the web server:

   ```bash
   python app.py
   ```

7. Open `http://127.0.0.1:5000` in your browser.

8. Change race distance or pit-stop loss, choose whether two compounds are required, then click **Optimize Strategy**. The optimizer considers one-, two-, and three-stop plans. The browser uses deterministic coarse-to-fine search so longer races remain responsive; it is not an exhaustive proof over every possible pit-lap combination.

## Windows setup

1. Install GNU Octave and Python 3.10+.
2. Open PowerShell in the extracted project folder.
3. Confirm that `octave --version` and `py --version` work. If Octave is not on PATH, add its installation folder to PATH or update `app.py` to point to the full `octave-cli.exe` path.
4. Create and activate a virtual environment:

   ```powershell
   py -m venv .venv
   .\.venv\Scripts\Activate.ps1
   py -m pip install -r requirements.txt
   ```

5. Start Flask:

   ```powershell
   py app.py
   ```

6. Visit `http://127.0.0.1:5000`.

## How the connection works

The browser sends race settings to `POST /api/optimize`. Flask writes a temporary JSON settings file and a temporary Octave driver, starts Octave, runs `default_params`, `optimize_strategy`, and `simulate_strategy`, then reads the JSON result. Each request gets its own temporary directory.

Health check: `GET /api/health`

## Troubleshooting

- **"GNU Octave was not found"**: make sure `octave --version` works in the same terminal where Flask is started.
- **"Octave simulation failed"**: the error message includes the last part of Octave's diagnostic output. Check that the installed Octave version can run the supplied `.m` file.
- **Browser loads but charts are blank**: check your internet connection because Chart.js is loaded from a CDN.
- **First run takes time**: the optimizer evaluates many candidate strategies. Shorter races run faster.
- **Port 5000 already in use**: stop the other process or change the port at the bottom of `app.py`.

## Important implementation note

The adapter uses the individual function files in `engine/`, which avoids script-local function visibility issues. The original simulation logic is preserved; only the packaging is changed for web integration.


## Reliability model integration

The web app now loads `engine/v5_reliability_web.m`, adapted from the integrated `v5_reliability.m` model. The interactive command-line entry point was removed so Flask can call the model functions directly. The default web run enables the simplified tyre-temperature model. Thermal values, event probabilities, tyre wear and fuel coefficients are educational model assumptions, not official telemetry or race predictions. Monte Carlo reliability metrics remain unavailable unless scenario simulation is explicitly enabled.
