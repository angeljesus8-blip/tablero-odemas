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

   26-sep-2026, «que se fuerce la actualización aunque no salgan y vuelvan»:

     4. preguntar también cada 5 minutos con la app a la vista
     5. la SEGUNDA versión nueva de la sesión también recarga (la bandera
        contra el bucle se quedaba puesta todo el día)
     6. no recargar encima de trabajo a medias (`HES_ocupado`, o alguien
        escribiendo), sino en cuanto se libera; y un tope de 30 min para lo
        abandonado, solo con la app en segundo plano
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const codigo = fs.readFileSync(path.join(__dirname, '..', 'continuidad.js'), 'utf8');

function montar(conSW, opciones){
  const o = opciones || {};
  const oyentesDoc = {}, oyentesSW = {};
  const est = { updates:0, recargas:0, registrado:conSW };
  const intervalos = [];                     // [{f, ms}]
  const reloj = { t: o.t || 1e12 };
  class RelojDate extends Date {
    constructor(...a){ a.length ? super(...a) : super(reloj.t); }
    static now(){ return reloj.t; }
  }
  const ss = o.ss || {};                     // sessionStorage: sobrevive a una recarga
  const caja = {
    console,
    location: { pathname:'/t/tablero.html', search:'', hash:'', replace(){}, href:'',
                reload(){ est.recargas++; } },
    document: { visibilityState:'visible', body:{ scrollHeight:1000, appendChild(){} },
                activeElement: null,
                createElement: () => ({ style:{}, setAttribute(){} }),
                addEventListener:(t,f)=>{ (oyentesDoc[t]=oyentesDoc[t]||[]).push(f); } },
    localStorage: { getItem:()=>null, setItem(){}, removeItem(){} },
    sessionStorage: { getItem:k=>(k in ss?ss[k]:null), setItem:(k,v)=>{ss[k]=String(v);}, removeItem:k=>{delete ss[k];} },
    performance: { getEntriesByType: () => [{ type:'navigate' }] },
    setInterval: (f, ms) => { intervalos.push({ f, ms, sig: reloj.t + ms }); return intervalos.length; },
    clearInterval: () => {}, setTimeout: () => 1,
    Date: RelojDate, JSON, Math,
  };

  caja.navigator = conSW ? {
    serviceWorker: {
      getRegistration: () => Promise.resolve({ update(){ est.updates++; } }),
      addEventListener: (t,f)=>{ (oyentesSW[t]=oyentesSW[t]||[]).push(f); },
    }
  } : {};
  caja.window = caja;
  caja.window.addEventListener = (t,f)=>{ (oyentesDoc[t]=oyentesDoc[t]||[]).push(f); };
  caja.__ocupado = !!o.ocupado;
  if (o.ocupado !== undefined) caja.HES_ocupado = () => caja.__ocupado;
  vm.createContext(caja);
  vm.runInContext(codigo, caja, { filename:'continuidad.js' });
  /* Adelanta el reloj y dispara, en orden, los intervalos que tocaban en ese rato. */
  function pasan(ms){
    const fin = reloj.t + ms;
    for(;;){
      const x = intervalos.slice().sort((p, q) => p.sig - q.sig)[0];
      if(!x || x.sig > fin) break;
      reloj.t = x.sig; x.sig += x.ms; x.f();
    }
    reloj.t = fin;
  }
  return { est, caja, ss, pasan, reloj,
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

// 2 · Y cada vez que se vuelve a la app.
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
ok('pero NO se recarga dos veces seguidas (sería un bucle)', a.est.recargas === 1, a.est.recargas + ' recargas');
ok('deja marcado el aviso «Se actualizó la app»', a.ss.hes_actualizada === '1');

// 4 · Sin service worker no se cae. Pasa en navegadores viejos y en http.
let err = null;
try { montar(false); } catch(e){ err = e.message; }
ok('sin service worker la app sigue funcionando', !err, err);

// 5 · Con la app abierta y a la vista, sin salir: pregunta cada 5 minutos.
let b = montar(true);
await respirar();
const antes = b.est.updates;
b.pasan(4 * 60 * 1000 + 59 * 1000); await respirar();
ok('abierta 4:59 min: todavía no vuelve a preguntar', b.est.updates === antes, (b.est.updates - antes) + ' veces');
b.pasan(1000); await respirar();
ok('abierta 5 min: pregunta sola', b.est.updates === antes + 1, (b.est.updates - antes) + ' veces');
b.pasan(10 * 60 * 1000); await respirar();
ok('y sigue cada 5 min', b.est.updates === antes + 3, (b.est.updates - antes) + ' veces');
b.irseAlFondo(); await respirar(); const enFondo = b.est.updates;
b.pasan(15 * 60 * 1000); await respirar();
ok('en segundo plano no gasta preguntando', b.est.updates === enFondo, (b.est.updates - enFondo) + ' veces');

// 6 · La SEGUNDA versión del día también recarga. Una recarga real reinicia la
//     página pero NO sessionStorage: se monta otra vez con el mismo.
const c1 = montar(true);
c1.llegaVersionNueva();
ok('primera versión nueva: recarga', c1.est.recargas === 1);
const c2 = montar(true, { ss: c1.ss, t: c1.reloj.t + 2 * 60 * 60 * 1000 });   // dos horas después
c2.llegaVersionNueva();
ok('segunda versión nueva, horas después: también recarga', c2.est.recargas === 1, c2.est.recargas + ' recargas');
const c3 = montar(true, { ss: c2.ss, t: c2.reloj.t + 3000 });                 // 3 s después: bucle
c3.llegaVersionNueva();
ok('otra recarga a los 3 s: se frena (bucle)', c3.est.recargas === 0, c3.est.recargas + ' recargas');

// 7 · No se recarga encima de trabajo a medias; sí en cuanto se libera.
const d = montar(true, { ocupado:true });
d.llegaVersionNueva();
ok('ocupado: NO recarga al llegar la versión', d.est.recargas === 0);
d.pasan(60 * 1000);
ok('ocupado: tampoco al minuto', d.est.recargas === 0);
d.caja.__ocupado = false;
d.pasan(15 * 1000);
ok('se libera: recarga en ≤ 15 s', d.est.recargas === 1, d.est.recargas + ' recargas');

const e = montar(true);
e.caja.document.activeElement = { tagName:'INPUT', type:'text' };
e.llegaVersionNueva();
ok('escribiendo en un campo: NO recarga', e.est.recargas === 0);
e.caja.document.activeElement = null;
e.pasan(15 * 1000);
ok('deja de escribir: recarga', e.est.recargas === 1);

const g = montar(true);
g.caja.HES_ocupado = () => { throw new Error('pantalla rota'); };
g.llegaVersionNueva();
ok('si la pantalla no sabe decir si está ocupada, no se arriesga', g.est.recargas === 0);

// 8 · Tope: lo "a medias" abandonado no deja la app vieja para siempre, pero
//     solo se recarga con la app en segundo plano.
const h = montar(true, { ocupado:true });
h.llegaVersionNueva();
h.pasan(31 * 60 * 1000);
ok('ocupado 31 min a la vista: sigue sin recargar', h.est.recargas === 0);
h.irseAlFondo();
ok('ocupado 31 min y se va a otra app: recarga', h.est.recargas === 1, h.est.recargas + ' recargas');
const k = montar(true, { ocupado:true });
k.llegaVersionNueva(); k.pasan(10 * 60 * 1000); k.irseAlFondo();
ok('ocupado 10 min y se va a otra app (la cámara): NO recarga', k.est.recargas === 0);

if(fallos.length){
  console.log('actualización: ' + fallos.length + ' fallo(s)');
  fallos.forEach(x => console.log('   · ' + x));
  process.exit(1);
}
console.log('actualización: pregunta al abrir, al volver y cada 5 min; recarga cada versión nueva, sin pisar trabajo a medias');
})();
