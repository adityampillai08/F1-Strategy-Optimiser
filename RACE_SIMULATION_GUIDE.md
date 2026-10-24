# Race Simulation (separate feature)

## Open it
Run the Flask app as usual and click **Race simulation**, or navigate to `/race-simulation`.

## Files added
- `templates/race_simulation.html` — dedicated Race Simulation view.
- `static/race-simulation.css` — isolated page styles; does not modify `static/style.css`.
- `static/race-simulation.js` — browser-side multi-car race model and UI.

## Scope protection
The Strategy Workspace HTML content and its `static/app.js` / `static/style.css` were retained from the uploaded working ZIP. The only existing-page change is converting the Race simulation sidebar placeholder into a link to the new route. A new Flask GET route serves the independent page. Existing optimizer endpoints and Octave engine were not changed.

## Simulation model
This is a deterministic educational simulation with fictional drivers and teams, synthetic lap-time variation, tyre wear, pit-stop penalties, live timing, position changes and a final classification. It is not live F1 data or a calibrated real-world race model.
