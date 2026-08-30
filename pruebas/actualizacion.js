/* ============================================================
   La app se pone al día sola
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe por lo del 9-ago-2026: un teléfono del equipo llevaba CUATRO
   versiones atrás. Se publicaba un arreglo, se comprobaba que el servidor
   lo servía, y en la tienda seguían con lo viejo — dos días arreglando a
   ciegas algo que ya estaba arreglado y no les llegaba.

   Registrar el service worker NO es pedirle que se actualice. Chrome lo
   comprueba por su cuenta, pero una PWA que se queda abierta días puede
   pasarse la semana sin mirarlo. Estas comprobaciones fijan las tres
   piezas que faltaban:

     1. preguntar al abrir
     2. volver a preguntar cada vez que la app vuelve a primer plano
     3. recargar cuando el nuevo toma el control, UNA sola vez
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const codigo = fs.readFileSync(path.join(__dirname, '..', 'continuidad.js'), 'utf8');

function montar(conSW){
  const oyentesDoc = {}, oyentesSW = {};
  const est = { updates:0, recargas:0, registrado:conSW };
  const caja = {
    console,
    location: { pathname:'/t/tablero.html', search:'', hash:'', replace(){}, href:'',
                reload(){ est.recargas++; } },
    document: { visibilityState:'visible', body:{ scrollHeight:1000 },
                addEventListener:(t,f)=>{ (oyentesDoc[t]=oyentesDoc[t]||[]).push(f); } },
    localStorage: { getItem:()=>null, setItem(){}, removeItem(){} },
    sessionStorage: (function(){ const m={}; return {
      getItem:k=>(k in m?m[k]:null), setItem:(k,v)=>{m[k]=String(v);}, removeItem:k=>{delete m[k];} }; })(),
    performance: { getEntriesByType: () => [{ type:'navigate' }] },
    setInterval: () => 1, clearInterval: () => {}, setTimeout: (f)=>{ return 1; },
    Date, JSON, Math,
  };
  caja.navigator = conSW ? {
    serviceWorker: {
      getRegistration: () => Promise.resolve({ update(){ est.updates++; } }),
      addEventListener: (t,f)=>{ (oyentesSW[t]=oyentesSW[t]||[]).push(f); },
    }
  } : {};
  caja.window = caja;
  caja.window.addEventListener = (t,f)=>{ (oyentesDoc[t]=oyentesDoc[t]||[]).push(f); };
  vm.createContext(caja);
  vm.runInContext(codigo, caja, { filename:'continuidad.js' });
  return { est, caja,
    volverAlFrente(){ caja.document.visibilityState = 'visible';
                      (oyentesDoc['visibilitychange']||[]).forEach(f=>f()); },
    irseAlFondo(){ caja.document.visibilityState = 'hidden';
                   (oyentesDoc['visibilitychange']||[]).forEach(f=>f()); },
    llegaVersionNueva(){ (oyentesSW['controllerchange']||[]).forEach(f=>f()); },
  };
}

const fallos = [];
function ok(t, c, d){ if(!c) fallos.push(t + (d ? '  -> ' + d : '')); }

/* `getRegistration()` devuelve una promesa, así que `update()` no se ha llamado
   todavía cuando vuelve el control. Sin esta espera la prueba mediría siempre
   cero y diría que nada funciona. */
const respirar = () => new Promise(r => setImmediate(r));

(async () => {

// 1 · Al abrir se pregunta si hay versión nueva
let a = montar(true);
await respirar();
ok('al abrir se pide la actualización', a.est.updates === 1, a.est.updates + ' veces');

// 2 · Y cada vez que se vuelve a la app. Es LO que faltaba: una PWA que no se
//     cierra nunca no vuelve a preguntar por su cuenta.
a.irseAlFondo(); a.volverAlFrente();
await respirar();
ok('al volver a primer plano se pregunta otra vez', a.est.updates === 2, a.est.updates + ' veces');
a.irseAlFondo(); a.volverAlFrente();
await respirar();
ok('y cada vez que se vuelve', a.est.updates === 3, a.est.updates + ' veces');

// 3 · Al tomar el control la versión nueva, se recarga UNA vez
a.llegaVersionNueva();
ok('llega la versión nueva y recarga', a.est.recargas === 1, a.est.recargas + ' recargas');
a.llegaVersionNueva(); a.llegaVersionNueva();
ok('pero NO se recarga dos veces (sería un bucle)', a.est.recargas === 1, a.est.recargas + ' recargas');

// 4 · Sin service worker no se cae. Pasa en navegadores viejos y en http.
let err = null;
try { montar(false); } catch(e){ err = e.message; }
ok('sin service worker la app sigue funcionando', !err, err);

if(fallos.length){
  console.log('actualización: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('actualización: la app pregunta al abrir, al volver, y recarga una sola vez');
})();
