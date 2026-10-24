const form = document.getElementById("strategy-form");
const laps = document.getElementById("laps");
const lapsValue = document.getElementById("laps-value");
const pitLoss = document.getElementById("pit-loss");
const pitLossValue = document.getElementById("pit-loss-value");
const runButton = document.getElementById("run-button");
const resetButton = document.getElementById("reset-button");
const toast = document.getElementById("toast");
let lapChart = null;
let fuelChart = null;
let ageChart = null;
let degradationChart = null;

laps.addEventListener("input", () => lapsValue.textContent = laps.value);
pitLoss.addEventListener("input", () => pitLossValue.textContent = Number(pitLoss.value).toFixed(1));
resetButton.addEventListener("click", () => {
  laps.value = 30;
  pitLoss.value = 22;
  document.getElementById("two-compounds").checked = true;
  lapsValue.textContent = "30";
  pitLossValue.textContent = "22.0";
  document.getElementById("empty-state").classList.remove("hidden");
  document.getElementById("result-state").classList.add("hidden");
  document.getElementById("result-tag").textContent = "READY";
  document.getElementById("strategy-table").innerHTML = '<tr><td colspan="6" class="table-empty">Your ranked strategies will appear here after optimization.</td></tr>';
  for (const chart of [lapChart, fuelChart, ageChart, degradationChart]) { if (chart) chart.destroy(); }
  lapChart = fuelChart = ageChart = degradationChart = null;
  document.getElementById("model-params").textContent = "Run an optimization to load the mathematical model coefficients.";
  showToast("Settings reset to the default 30-lap race.");
});

function showToast(message) {
  toast.textContent = message;
  toast.classList.remove("hidden");
  window.clearTimeout(showToast.timer);
  showToast.timer = window.setTimeout(() => toast.classList.add("hidden"), 7000);
}
function fmtSeconds(seconds) {
  const mins = Math.floor(seconds / 60);
  const secs = (seconds % 60).toFixed(3).padStart(6, "0");
  return `${mins}:${secs}`;
}
function tyreName(code) { return ({1:"Soft", 2:"Medium", 3:"Hard"})[Number(code)] || "Unknown"; }
function tyreColor(code) { return ({1:"#ed3542", 2:"#f2c14e", 3:"#b8c0ca"})[Number(code)] || "#87909d"; }
function tyreInitial(code) { return ({1:"S",2:"M",3:"H"})[Number(code)] || "?"; }

async function checkHealth() {
  const status = document.getElementById("engine-status");
  try {
    const response = await fetch("/api/health");
    const data = await response.json();
    status.textContent = data.octaveAvailable ? "Connected · Octave detected" : "Octave not detected";
    status.style.color = data.octaveAvailable ? "#57d5a0" : "#ef7a82";
  } catch (_) {
    status.textContent = "Backend unavailable";
  }
}
checkHealth();

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  runButton.disabled = true;
  runButton.setAttribute("aria-busy", "true");
  runButton.querySelector("span:first-child").textContent = "RUNNING OPTIMIZER…";
  document.getElementById("result-tag").textContent = "CALCULATING";
  try {
    const response = await fetch("/api/optimize", {
      method: "POST",
      headers: {"Content-Type":"application/json"},
      body: JSON.stringify({
        laps: Number(laps.value),
        pitLoss: Number(pitLoss.value),
        requireTwoCompounds: document.getElementById("two-compounds").checked
      })
    });
    const data = await response.json();
    if (!response.ok) throw new Error(data.error || "The simulation failed.");
    renderResults(data);
    document.getElementById("result-tag").textContent = "OPTIMAL FOUND";
  } catch (error) {
    document.getElementById("result-tag").textContent = "ERROR";
    showToast(error.message || "Could not reach the simulation engine.");
  } finally {
    runButton.disabled = false;
    runButton.removeAttribute("aria-busy");
    runButton.querySelector("span:first-child").textContent = "OPTIMIZE STRATEGY";
  }
});

function renderResults(data) {
  document.getElementById("empty-state").classList.add("hidden");
  document.getElementById("result-state").classList.remove("hidden");
  document.getElementById("total-time").textContent = fmtSeconds(data.totalTime);
  document.getElementById("average-time").textContent = `${data.averageLap.toFixed(3)} seconds average per lap`;
  document.getElementById("stop-count").textContent = data.bestStrategy.pitLaps.length;
  document.getElementById("candidate-count").textContent = `${Number(data.candidatesEvaluated).toLocaleString()} strategies evaluated`;

  const compounds = data.bestStrategy.compounds.map(Number);
  const pitLaps = (Array.isArray(data.bestStrategy.pitLaps)
  ? data.bestStrategy.pitLaps
  : [data.bestStrategy.pitLaps]).map(Number);
  const edges = [0, ...pitLaps, Number(data.nLaps)];
  const track = document.getElementById("stint-track");
  track.innerHTML = "";
  compounds.forEach((compound, index) => {
    const start = edges[index] + 1;
    const end = edges[index + 1];
    const length = end - edges[index];
    const stint = document.createElement("div");
    stint.className = "stint";
    stint.style.flex = `${length} 1 0`;
    stint.style.setProperty("--stint-color", tyreColor(compound));
    stint.innerHTML = `<b>${tyreInitial(compound)} · ${tyreName(compound)}</b><small>Laps ${start}–${end}</small>`;
    track.appendChild(stint);
  });

  const pitDetails = document.getElementById("pit-details");
  pitDetails.innerHTML = "";
  if (!pitLaps.length) {
    pitDetails.innerHTML = '<span class="pit-pill">No pit stops in this strategy</span>';
  } else {
    pitLaps.forEach((lap, index) => {
      const pill = document.createElement("span");
      pill.className = "pit-pill";
      pill.innerHTML = `PIT ${index + 1} <b>· After lap ${lap}</b>`;
      pitDetails.appendChild(pill);
    });
  }

  const tbody = document.getElementById("strategy-table");
  tbody.innerHTML = "";
  data.topStrategies.forEach((strategy, index) => {
    const tr = document.createElement("tr");
    if (index === 0) tr.className = "best-row";
    const seq = strategy.compounds.map(tyreInitial).join(" → ");
    const stops = strategy.pitLaps.length;
    const pits = strategy.pitLaps.length ? strategy.pitLaps.join(", ") : "—";
    tr.innerHTML = `<td><span class="rank">${String(strategy.rank).padStart(2,"0")}</span></td>
      <td><span class="compound-seq">${seq}</span></td>
      <td>${pits}</td><td>${stops}</td>
      <td>${fmtSeconds(Number(strategy.totalTime))}</td>
      <td class="${index === 0 ? "gap-best" : ""}">${index === 0 ? "BEST" : `+${Number(strategy.gap).toFixed(3)} s`}</td>`;
    tbody.appendChild(tr);
  });

  drawChart(data);
  drawFuelChart(data);
  drawAgeChart(data);
  drawDegradationChart(data);
}
function drawChart(data) {
  const ctx = document.getElementById("lap-chart");
  const lapsArray = data.lapTimes.map((_, index) => index + 1);
  const pitLaps = (Array.isArray(data.bestStrategy.pitLaps)
  ? data.bestStrategy.pitLaps
  : [data.bestStrategy.pitLaps]).map(Number);
  const compounds = data.bestStrategy.compounds.map(Number);
  const edges = [0, ...pitLaps, Number(data.nLaps)];
  // Remove the fixed pit-loss penalty from the pit lap to show the underlying lap-time trend.
  const racingTimes = data.lapTimes.map((value, index) => pitLaps.includes(index + 1) ? value - Number(data.pitLoss) : value);
  const datasets = [1,2,3].map(code => {
    const values = racingTimes.map((value, index) => {
      let stintIndex = edges.findIndex((edge, i) => i < edges.length - 1 && index + 1 > edge && index + 1 <= edges[i+1]);
      return stintIndex >= 0 && compounds[stintIndex] === code ? value : null;
    });
    return {label:tyreName(code), data:values, borderColor:tyreColor(code), backgroundColor:tyreColor(code), pointRadius:2, pointHoverRadius:4, borderWidth:2, tension:.25, spanGaps:false};
  });
  if (lapChart) lapChart.destroy();
  lapChart = new Chart(ctx, {
    type:"line",
    data:{labels:lapsArray, datasets},
    options:{
      responsive:true, maintainAspectRatio:false, animation:{duration:250},
      plugins:{legend:{display:false}, tooltip:{backgroundColor:"#171c24",borderColor:"#303743",borderWidth:1,callbacks:{label:(item)=>`${item.dataset.label}: ${Number(item.raw).toFixed(3)} s`}}},
      scales:{
        x:{title:{display:true,text:"RACE LAP",color:"#727c88",font:{size:9}},ticks:{color:"#7e8793",maxTicksLimit:10,font:{size:9}},grid:{color:"#242a32"}},
        y:{title:{display:true,text:"SECONDS",color:"#727c88",font:{size:9}},ticks:{color:"#7e8793",font:{size:9}},grid:{color:"#242a32"}}
      }
    }
  });
}


function baseChartOptions(yTitle) {
  return {
    responsive:true, maintainAspectRatio:false, animation:{duration:220},
    plugins:{legend:{labels:{color:"#aab2bd",boxWidth:12,font:{size:10}}}, tooltip:{backgroundColor:"#171c24",borderColor:"#303743",borderWidth:1}},
    scales:{
      x:{title:{display:true,text:"RACE LAP / TYRE AGE",color:"#727c88",font:{size:9}},ticks:{color:"#7e8793",maxTicksLimit:12,font:{size:9}},grid:{color:"#242a32"}},
      y:{title:{display:true,text:yTitle,color:"#727c88",font:{size:9}},ticks:{color:"#7e8793",font:{size:9}},grid:{color:"#242a32"}}
    }
  };
}
function drawFuelChart(data) {
  const ctx = document.getElementById("fuel-chart");
  if (!ctx || !Array.isArray(data.fuelLoads)) return;
  if (fuelChart) fuelChart.destroy();
  fuelChart = new Chart(ctx, {type:"line", data:{labels:data.fuelLoads.map((_,i)=>i+1), datasets:[{label:"Fuel remaining",data:data.fuelLoads,borderColor:"#57d5a0",backgroundColor:"#57d5a022",fill:true,pointRadius:0,borderWidth:2,tension:.12}]}, options:baseChartOptions("FUEL (KG)")});
}
function drawAgeChart(data) {
  const ctx = document.getElementById("age-chart");
  if (!ctx || !Array.isArray(data.tyreAges)) return;
  if (ageChart) ageChart.destroy();
  const pitLaps = (Array.isArray(data.bestStrategy.pitLaps)?data.bestStrategy.pitLaps:[data.bestStrategy.pitLaps]).map(Number);
  ageChart = new Chart(ctx, {type:"line", data:{labels:data.tyreAges.map((_,i)=>i+1), datasets:[{label:"Tyre age",data:data.tyreAges,borderColor:"#f2c14e",backgroundColor:"#f2c14e22",fill:true,pointRadius:pitLaps.length?data.tyreAges.map((_,i)=>pitLaps.includes(i+1)?3:0):0,borderWidth:2,stepped:true}]}, options:baseChartOptions("LAPS ON CURRENT TYRE SET")});
}
function drawDegradationChart(data) {
  const ctx = document.getElementById("degradation-chart");
  const p = data.modelParams;
  if (!ctx || !p || !p.baseTime || !p.degradationA || !p.degradationB) return;
  if (degradationChart) degradationChart.destroy();
  const maxAge = Math.max(10, Math.min(40, Number(data.nLaps)-1));
  const ages = Array.from({length:maxAge+1},(_,i)=>i);
  const names = ["Soft","Medium","Hard"], colors = ["#ed3542","#f2c14e","#b8c0ca"];
  const datasets = names.map((name,i)=>({label:name,data:ages.map(age=>Number(p.baseTime[i])+Number(p.degradationA[i])*age+Number(p.degradationB[i])*age*age),borderColor:colors[i],backgroundColor:colors[i],pointRadius:0,borderWidth:2,tension:.18}));
  degradationChart = new Chart(ctx,{type:"line",data:{labels:ages,datasets},options:{...baseChartOptions("MODEL LAP TIME (SECONDS)"),scales:{...baseChartOptions("MODEL LAP TIME (SECONDS)").scales,x:{...baseChartOptions("MODEL LAP TIME (SECONDS)").scales.x,title:{display:true,text:"TYRE AGE (LAPS)",color:"#727c88",font:{size:9}}}}}});
  const fmt = arr => arr.map(v=>Number(v).toFixed(4)).join(" / ");
  document.getElementById("model-params").innerHTML = `<b>Base lap time (S / M / H):</b> ${fmt(p.baseTime)} s &nbsp; <b>Wear A:</b> ${fmt(p.degradationA)} &nbsp; <b>Wear B:</b> ${fmt(p.degradationB)} &nbsp; <b>Fuel coefficient:</b> ${Number(p.fuelCoeff).toFixed(4)} s/kg`;
}


// Scroll progress indicator, with reduced-motion users respected.
(() => {
  const bar = document.getElementById("scroll-progress");
  if (!bar) return;
  let scheduled = false;
  const update = () => {
    const max = document.documentElement.scrollHeight - window.innerHeight;
    const percent = max > 0 ? (window.scrollY / max) * 100 : 0;
    bar.style.width = `${Math.min(100, Math.max(0, percent))}%`;
    scheduled = false;
  };
  window.addEventListener("scroll", () => {
    if (!scheduled) {
      scheduled = true;
      window.requestAnimationFrame(update);
    }
  }, { passive: true });
  window.addEventListener("resize", update, { passive: true });
  update();
})();
