(() => {
  const $ = id => document.getElementById(id);
  const drivers = [
    ['Lando Norris','McLaren', '#ff8700',0.00,'NOR',1],['Oscar Piastri','McLaren','#ff8700',.08,'PIA',81],
    ['George Russell','Mercedes','#00d2be',.11,'RUS',63],['Kimi Antonelli','Mercedes','#00d2be',.04,'ANT',12],
    ['Max Verstappen','Red Bull Racing','#3671c6',.02,'VER',3],['Isack Hadjar','Red Bull Racing','#3671c6',.20,'HAD',6],
    ['Charles Leclerc','Ferrari','#e8002d',.07,'LEC',16],['Lewis Hamilton','Ferrari','#e8002d',.13,'HAM',44],
    ['Alex Albon','Williams','#64c4ff',.29,'ALB',23],['Carlos Sainz','Williams','#64c4ff',.22,'SAI',55],
    ['Arvid Lindblad','Racing Bulls','#6692ff',.34,'LIN',41],['Liam Lawson','Racing Bulls','#6692ff',.28,'LAW',30],
    ['Lance Stroll','Aston Martin','#229971',.37,'STR',18],['Fernando Alonso','Aston Martin','#229971',.24,'ALO',14],
    ['Esteban Ocon','Haas','#b6babd',.30,'OCO',31],['Oliver Bearman','Haas','#b6babd',.25,'BEA',87],
    ['Nico Hulkenberg','Audi','#ff2d00',.31,'HUL',27],['Gabriel Bortoleto','Audi','#ff2d00',.36,'BOR',5],
    ['Pierre Gasly','Alpine','#ff87bc',.27,'GAS',10],['Franco Colapinto','Alpine','#ff87bc',.33,'COL',43],
    ['Sergio Perez','Cadillac','#eeeeee',.38,'PER',11],['Valtteri Bottas','Cadillac','#eeeeee',.32,'BOT',77]
  ].map(d=>({name:d[0],team:d[1],color:d[2],pace:d[3],code:d[4],number:d[5]}));
  let cars=[], timer=null, animationFrame=null, lap=0, totalLaps=12, running=false, finished=false, overtakes=0, eventCount=0, safetyCar=false, safetyLap=-1;
  const markerNodes = new Map();
  let trackPath = null, trackLength = 0, lastFrame = 0;
  const fmt = s => {const m=Math.floor(s/60), sec=(s%60).toFixed(3).padStart(6,'0');return `${m}:${sec}`;};
  const escapeHTML=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function pushEvent(message,label='RACE CONTROL') {const log=$('event-log');if(eventCount===0)log.innerHTML='';eventCount++;const el=document.createElement('div');el.className='event';el.innerHTML=`<span class="event-time">${escapeHTML(label)}</span><p>${escapeHTML(message)}</p>`;log.prepend(el);}
  function createCars(count){return drivers.slice(0,count).map((d,i)=>({...d,id:i,position:i+1,lap:0,total:0,lastLap:null,stops:0,pitLap:Math.max(3,Math.min(totalLaps-1,Math.round(totalLaps*(.34+(i%5)*.055)))),pitDone:false,tyre:['Soft','Medium','Hard'][i%3],tyreAge:0,fuel:100,history:[],sectors:[0,0,0],trackPos:(i/count),visualPos:(i/count),fastestLap:Infinity}));}
  function ensureMap(){
    const host=$('car-markers');
    if(!host)return;
    if(!trackPath){trackPath=document.querySelector('#circuit-map .track-line');trackLength=trackPath?.getTotalLength?.()||0;}
    const activeIds=new Set(cars.map(c=>c.id));
    markerNodes.forEach((node,id)=>{if(!activeIds.has(id)){node.remove();markerNodes.delete(id);}});
    cars.forEach(c=>{
      let g=markerNodes.get(c.id);
      if(!g){
        g=document.createElementNS('http://www.w3.org/2000/svg','g');
        g.innerHTML=`<circle r="10" fill="${c.color}" stroke="#fff" stroke-width="1.5"/><text y="3.5" text-anchor="middle" font-size="8" font-weight="800" fill="#071018">${c.number}</text>`;
        host.appendChild(g);markerNodes.set(c.id,g);
      }
    });
    updateMapPositions(true);
  }
  function updateMapPositions(snap=false){
    if(!trackPath||!trackLength)return;
    cars.forEach(c=>{
      let delta=c.trackPos-c.visualPos;
      if(delta>.5)delta-=1;else if(delta<-.5)delta+=1;
      c.visualPos=snap?c.trackPos:(c.visualPos+delta*.075+1)%1;
      const pt=trackPath.getPointAtLength(((c.visualPos%1)+1)%1*trackLength);
      const node=markerNodes.get(c.id);
      if(node)node.setAttribute('transform',`translate(${pt.x} ${pt.y})`);
    });
  }
  function animateMap(timestamp){
    if(timestamp-lastFrame>16){updateMapPositions(false);lastFrame=timestamp;}
    animationFrame=requestAnimationFrame(animateMap);
  }
  function renderTiming(){const sorted=[...cars].sort((a,b)=>b.lap-a.lap||a.total-b.total),leader=sorted[0];$('timing-body').innerHTML='';sorted.forEach((c,i)=>{const gap=i===0?'LEADER':c.lap===leader.lap?`+${(c.total-leader.total).toFixed(3)} s`:`${leader.lap-c.lap} LAP`;const tr=document.createElement('tr');tr.innerHTML=`<td>${String(i+1).padStart(2,'0')}</td><td><span class="driver-cell"><i class="team-stripe" style="background:${c.color}"></i><span><b>${escapeHTML(c.name)}</b><small class="team-name">${escapeHTML(c.team)} · #${c.number}</small></span></span></td><td><span class="tyre tyre-${c.tyre.toLowerCase()}">${c.tyre[0]}</span></td><td>${c.lastLap===null?'—':c.lastLap.toFixed(3)+' s'}</td><td>${c.sectors.map(v=>v?v.toFixed(2):'—').join(' / ')}</td><td>${c.fuel.toFixed(0)}%</td><td>${c.tyreAge} L</td><td>${gap}</td><td>${c.stops}</td>`;$('timing-body').appendChild(tr);c.position=i+1;});$('leader-name').textContent=leader?.name||'—';$('leader-time').textContent=leader?fmt(leader.total)+' elapsed':'No timing data yet';$('current-lap').textContent=lap;$('total-laps').textContent=totalLaps;$('race-progress').style.width=`${lap/totalLaps*100}%`;$('overtake-count').textContent=overtakes;$('timing-tag').textContent=finished?'FINAL ORDER':running?'LIVE TIMING':lap?'PAUSED':'GRID ORDER';ensureMap();const fastest=cars.reduce((best,c)=>c.fastestLap<best.fastestLap?c:best,cars[0]);$('fastest-driver').textContent=fastest&&Number.isFinite(fastest.fastestLap)?fastest.name:'—';$('fastest-time').textContent=fastest&&Number.isFinite(fastest.fastestLap)?fastest.fastestLap.toFixed(3)+' s':'No lap recorded';$('safety-car-status').textContent=safetyCar?'DEPLOYED':'INACTIVE';$('safety-car-indicator').textContent=`SAFETY CAR: ${safetyCar?'DEPLOYED':'INACTIVE'}`;$('track-state').textContent=safetyCar?'YELLOW':'GREEN';$('track-note').textContent=safetyCar?'Field speed reduced':'Normal racing conditions';}
  function renderClassification(){const sorted=[...cars].sort((a,b)=>b.lap-a.lap||a.total-b.total),host=$('classification');host.innerHTML='';if(!lap&&!finished){host.innerHTML='<div class="classification-empty">Start the race to populate the classification.</div>';return;}sorted.forEach((c,i)=>{const el=document.createElement('div');el.className='finish-card';el.style.setProperty('--team',c.color);el.innerHTML=`<div class="finish-pos">${String(i+1).padStart(2,'0')}</div><strong>${escapeHTML(c.name)}</strong><small>${escapeHTML(c.team)} · ${finished?fmt(c.total):`${c.lap}/${totalLaps} laps`}</small>`;host.appendChild(el);});$('classification-tag').textContent=finished?'CHEQUERED FLAG':'PROVISIONAL';}
  function render(){renderTiming();renderClassification();}
  function reset(){if(timer)clearInterval(timer);timer=null;running=false;finished=false;lap=0;overtakes=0;eventCount=0;safetyCar=false;safetyLap=-1;totalLaps=Number($('race-distance').value);cars=createCars(Number($('race-field').value));ensureMap();$('race-status').textContent='READY';$('race-status-note').textContent='Waiting for lights out';$('start-btn').disabled=false;$('start-btn').innerHTML='START RACE <span>↗</span>';$('pause-btn').disabled=true;$('pause-btn').textContent='PAUSE';$('event-log').innerHTML='<div class="event-empty">Race events will appear here after the start.</div>';$('classification-tag').textContent='PROVISIONAL';render();}
  function advanceLap(){if(!running||finished)return;lap++;const old=new Map(cars.map(c=>[c.id,c.position]));if(lap===Math.max(3,Math.floor(totalLaps*.55))&&totalLaps>=8){safetyCar=true;safetyLap=lap;pushEvent('Debris reported. Virtual safety car deployed; lap times reduced.','SAFETY CAR');}else if(safetyCar&&lap===safetyLap+2){safetyCar=false;pushEvent('Track clear. Green flag; racing resumes.','GREEN FLAG');}
    cars.forEach(c=>{let base=88.4+c.pace*2+(c.tyre==='Soft'?0:c.tyre==='Medium'?.32:.63);c.tyreAge++;const wear=(c.tyre==='Soft'?.055:c.tyre==='Medium'?.033:.018)*c.tyreAge;const fuelEffect=(c.fuel/100)*.28;const variability=Math.sin(lap*1.73+c.id*2.11)*.16+Math.cos(lap*.77+c.id)*.07;let lapTime=base+wear+fuelEffect+variability;if(safetyCar)lapTime+=9.5;if(!c.pitDone&&lap===c.pitLap&&lap<totalLaps){lapTime+=22;c.stops++;c.pitDone=true;c.tyre=c.tyre==='Soft'?'Medium':c.tyre==='Medium'?'Hard':'Medium';c.tyreAge=0;pushEvent(`${c.name} pits for ${c.tyre} tyres; simulated pit-lane loss applied.`,`LAP ${lap}`);}if(lap>2&&c.fuel>35&&Math.abs(c.pace-(cars[(c.id+1)%cars.length]?.pace||0))<.15&&lap%4===0){lapTime-=.16;pushEvent(`${c.name} uses DRS to gain time in the marked zone.`,`LAP ${lap}`);}c.lastLap=lapTime;c.total+=lapTime;c.history.push(lapTime);c.fastestLap=Math.min(c.fastestLap,lapTime);c.sectors=[lapTime*.29+Math.sin(c.id+lap)*.06,lapTime*.34+Math.cos(c.id+lap)*.05,lapTime*.37];c.fuel=Math.max(0,c.fuel-(100/totalLaps));c.trackPos=(lap/totalLaps+(c.id*.004)+(c.total/Math.max(1,cars.length*100000)))%1;});
    const sorted=[...cars].sort((a,b)=>b.lap-a.lap||a.total-b.total);sorted.forEach((c,i)=>{if(old.get(c.id)!==i+1&&i+1<old.get(c.id)){overtakes++;if(overtakes<=20)pushEvent(`${c.name} gains a position in the simulated timing order.`,`LAP ${lap}`);}c.position=i+1;});$('race-status').textContent=lap>=totalLaps?'FINISHED':safetyCar?'SAFETY CAR':'RUNNING';$('race-status-note').textContent=lap>=totalLaps?'Chequered flag — simulated classification confirmed':safetyCar?'Field circulating under virtual safety car':`Lap ${lap} completed`;render();if(lap>=totalLaps){finished=true;running=false;clearInterval(timer);timer=null;$('start-btn').disabled=true;$('pause-btn').disabled=true;$('timing-tag').textContent='FINAL ORDER';pushEvent(`Chequered flag! ${sorted[0].name} wins the simulated race in ${fmt(sorted[0].total)}.`,`FINISH`);renderClassification();}}
  function start(){if(finished||running)return;if(lap===0){totalLaps=Number($('race-distance').value);cars=createCars(Number($('race-field').value));pushEvent(`${cars.length} drivers away! ${totalLaps}-lap simulated race started.`,`LIGHTS OUT`);}running=true;$('race-status').textContent='RUNNING';$('race-status-note').textContent='Cars circulating';$('start-btn').disabled=true;$('pause-btn').disabled=false;$('pause-btn').textContent='PAUSE';$('start-btn').textContent='RACE IN PROGRESS';timer=setInterval(advanceLap,1000);}
  function pause(){if(!running)return;running=false;if(timer)clearInterval(timer);timer=null;$('race-status').textContent='PAUSED';$('race-status-note').textContent='Simulation paused';$('start-btn').disabled=false;$('start-btn').textContent='RESUME RACE';$('pause-btn').disabled=true;pushEvent('Simulation paused by race control.','CONTROL');}
  $('race-distance').addEventListener('input',()=>{$('distance-value').textContent=$('race-distance').value;if(!running&&lap===0)reset();});$('race-field').addEventListener('change',()=>{if(!running&&lap===0)reset();});$('start-btn').addEventListener('click',start);$('pause-btn').addEventListener('click',pause);$('reset-btn').addEventListener('click',reset);reset();if(!animationFrame)animationFrame=requestAnimationFrame(animateMap);
})();
