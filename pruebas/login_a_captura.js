/* ============================================================
   Del login a poder capturar: el camino entero
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Las otras pruebas miran una pantalla cada una. Ésta sigue el dato de
   punta a punta, que es donde se escondió el bloqueo del 8 y 9 de agosto
   de 2026: cada pieza estaba bien por separado —la base devolvía el
   equipo, el menú lo guardaba, Captura lo leía— y aun así el asesor no
   podía capturar.

   Se usa la respuesta REAL de `login_empleado`, copiada tal cual: la
   forma exacta de esos campos es justo lo que se pierde al mirar cada
   archivo por su lado.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const raiz = path.join(__dirname, '..');

/* Respuesta real de login_empleado (9-ago-2026), con el token cambiado: este
   repo es público. Lo que importa es la FORMA.

   La tienda también es inventada. `gas_url` y `sheet_url` ya no salen de aquí
   ni se guardan en la sesión: no hay Apps Script ni hoja de Google.

   Los nombres son INVENTADOS desde el 28-ago-2026 — antes eran los del equipo,
   que es justo lo que este comentario decía estar evitando. Lo que se conserva
   es la forma que importa: la lista trae grafías flojas —minúsculas y sin
   acentos— y una que difiere del nombre oficial en UNA letra («bravvo» contra
   «Bravo»), que es el caso que descuadró las comisiones de agosto. */
const RESPUESTA_ASESOR = [{
  store_id: '9999', nombre: 'Tienda de prueba', ciudad: 'Ciudad',
  vendedores: ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal',
               'Elena Navarro Galvez', 'Maria Fuentes bravvo', 'Ana Ramirez solis'],
  emp_no: '1000004', emp_nombre: 'Jorge Medina Rejón',
  emp_puesto: 'Asesor de Tienda', emp_admin: false,
  gas_token: 'xxxx', hoja_auth: 'Elena Navarro Galvez',
}];

const fallos = [];
function ok(t, c, d){ if(!c) fallos.push(t + (d ? '  -> ' + d : '')); }

/* ── 1 · Lo que el menú guarda con esa respuesta ─────────────
   Se copia el armado de `cfg` desde index.html en vez de reescribirlo: si
   alguien añade un campo allí y se olvida aquí, esta prueba lo dice. */
const indexHtml = fs.readFileSync(path.join(raiz, 'index.html'), 'utf8');
const lineaCfg = (indexHtml.match(/^\s*const cfg = \{ store_id:data\.store_id.*$/m) || [])[0];
if(!lineaCfg){
  console.log('login a captura: no encontré dónde index.html arma la sesión del asesor');
  process.exit(1);
}
const guardado = {};
const cajaMenu = { console, data: RESPUESTA_ASESOR[0], Array, JSON,
  localStorage: { setItem:(k,v)=>{ guardado[k] = String(v); }, getItem:k=>guardado[k]||null,
                  removeItem:k=>{ delete guardado[k]; } } };
vm.createContext(cajaMenu);
vm.runInContext(lineaCfg + "\nglobalThis.__cfg = cfg;", cajaMenu, { filename:'index-cfg.js' });
const cfg = cajaMenu.__cfg;

ok('la sesión guarda la tienda',        cfg.store_id === '9999', JSON.stringify(cfg.store_id));
ok('la sesión guarda el token',         !!cfg.gas_token);
ok('la sesión guarda los 5 del equipo', Array.isArray(cfg.vendedores) && cfg.vendedores.length === 5,
   (cfg.vendedores || []).length + ' nombres');

/* ── 2 · Y con eso, ¿Captura deja trabajar? ──────────────── */
const capturaHtml = fs.readFileSync(path.join(raiz, 'captura_series.html'), 'utf8');
const js = (capturaHtml.match(/<script[^>]*>[\s\S]*?<\/script>/g) || [])
  .filter(b => !/\ssrc=/.test(b.slice(0, b.indexOf('>'))))
  .filter(b => !/type="module"/.test(b.slice(0, b.indexOf('>'))))
  .map(b => b.slice(b.indexOf('>') + 1, b.lastIndexOf('</script>')))
  .join('\n;\n');

const LS = { hes_store: JSON.stringify(cfg),
             hes_empleado: JSON.stringify({ empno: RESPUESTA_ASESOR[0].emp_no,
                                            nombre: RESPUESTA_ASESOR[0].emp_nombre,
                                            puesto: RESPUESTA_ASESOR[0].emp_puesto,
                                            admin: RESPUESTA_ASESOR[0].emp_admin }) };
const els = {};
/* El gate arranca VISIBLE, igual que en el HTML (<div id="gate"> sin la clase
   `hide`). Empezar en "indeterminado" fue lo que dejó pasar el bloqueo del
   8-ago: el código identificaba al asesor y se olvidaba de llamar a
   `hideGate()`, la pantalla se quedaba encima y vacía, y la prueba lo daba por
   bueno porque nadie había tocado el gate. No tocarlo NO es esconderlo. */
let gateOculto = false, gateHTML = '';
function el(id){
  if(!els[id]) els[id] = { id, style:{}, dataset:{}, value:'', textContent:'', children:[],
    set innerHTML(v){ if(id === 'gateNames') gateHTML = v; },
    get innerHTML(){ return id === 'gateNames' ? gateHTML : ''; },
    classList:{ add:()=>{ if(id === 'gate') gateOculto = true; },
                remove:()=>{ if(id === 'gate') gateOculto = false; }, toggle(){}, contains(){ return false; } },
    querySelectorAll:()=>[], addEventListener(){}, appendChild(){}, closest:()=>null,
    focus(){}, remove(){}, onclick:null, insertBefore(){}, scrollIntoView(){} };
  return els[id];
}
const caja = {
  console,
  location:{ href:'', search:'', hash:'', pathname:'/t/captura_series.html', replace(){}, reload(){} },
  navigator:{ serviceWorker:{ addEventListener(){}, ready:{ then(){ return { catch(){} }; } },
                              register(){ return { catch(){} }; } } },
  document:{ getElementById:el, querySelectorAll:()=>[], querySelector:()=>null,
    createElement:()=>el('t'+Math.random()), head:el('head'), body:el('body'),
    readyState:'complete', addEventListener(){} },
  localStorage:{ getItem:k=>(k in LS ? LS[k] : null), setItem:(k,v)=>{ LS[k] = String(v); },
                 removeItem:k=>{ delete LS[k]; } },
  sessionStorage:{ getItem:()=>null, setItem(){}, removeItem(){} },
  fetch:()=>Promise.reject(new Error('sin red')), alert:()=>{}, confirm:()=>true, prompt:()=>null,
  setInterval:()=>0, clearInterval:()=>{}, setTimeout:()=>0, clearTimeout:()=>{},
  scrollTo:()=>{}, addEventListener:()=>{}, removeEventListener:()=>{},
  AbortController: class { constructor(){ this.signal = {}; } abort(){} },
  Blob: class {}, URL:{ createObjectURL:()=>'', revokeObjectURL:()=>{} },
  XMLHttpRequest: class { open(){} send(){} setRequestHeader(){} },
  Image: class {}, FileReader: class {}, requestAnimationFrame:()=>0,
  URLSearchParams, TextEncoder, TextDecoder, Date, JSON, Math, RegExp,
  Promise, Array, Object, String, Number, Boolean, Error, Set, Map,
  isNaN, parseFloat, parseInt, encodeURIComponent, decodeURIComponent,
  btoa: s => Buffer.from(s, 'binary').toString('base64'),
};
caja.window = caja; caja.globalThis = caja;
vm.createContext(caja);
let err = null;
try { vm.runInContext(js, caja, { filename:'captura.js' }); } catch(e){ err = e.message; }

ok('Captura de Series no se cae con esa sesión', !err, err);
if(!err){
  ok('entra directo a capturar, sin preguntar quién es', gateOculto === true,
     'se quedó en el gate con ' + (gateHTML.match(/gate-name/g) || []).length + ' nombre(s)');
  // Sin acentos: gana la grafía de la LISTA, no la de la sesión. Eso es lo que
  // se está probando, y por eso los dos nombres no se escriben igual arriba.
  ok('y con el nombre del asesor puesto', el('vendLabel').textContent === 'Jorge Medina Rejon',
     '"' + el('vendLabel').textContent + '"');
}

if(fallos.length){
  console.log('login a captura: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('login a captura: con la respuesta real del login, el asesor entra y captura');
