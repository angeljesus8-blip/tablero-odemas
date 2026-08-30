/* ============================================================
   Salir de una pantalla y volver: todas las combinaciones
   ============================================================
   Corre en cada commit desde `verificar.py`.

   `continuidad.js` cruza cuatro cosas: de qué pantalla sales, cómo sales,
   si Android mató la app, y cómo vuelve el menú. El 8-ago-2026 se
   publicaron tres arreglos seguidos porque cada uno se probó por su
   camino, y los fallos vivían en los cruces: con la app inservible dos
   veces —no se podía llegar al menú desde ninguna pantalla— y una tercera
   en la que no reanudaba al volver desde apps recientes.

   Probarlas todas tarda menos de un segundo. Probarlas de una en una
   costó tres publicaciones.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const codigo = fs.readFileSync(path.join(__dirname, '..', 'continuidad.js'), 'utf8');

const LS = {};
let SS = {};
function relanzarApp(){ SS = {}; }   // Android mató la app: la pestaña empieza de cero

function abrirPagina(pagina, hash, tipoNav){
  const oyentes = {};
  global.__irA = null;
  global.window = global;
  global.scrollY = 0;
  global.innerHeight = 800;
  global.scrollTo = (x, y) => { global.scrollY = y; };
  global.location = {
    pathname:'/tablero-hes1217/' + pagina, search:'', hash:hash || '',
    replace(u){ global.__irA = { modo:'replace', url:u }; },
    set href(u){ global.__irA = { modo:'href', url:u }; }, get href(){ return ''; }
  };
  global.localStorage  = { getItem:k => (k in LS ? LS[k] : null),
                           setItem:(k, v) => { LS[k] = String(v); }, removeItem:k => { delete LS[k]; } };
  global.sessionStorage= { getItem:k => (k in SS ? SS[k] : null),
                           setItem:(k, v) => { SS[k] = String(v); }, removeItem:k => { delete SS[k]; } };
  global.document = { visibilityState:'visible', body:{ scrollHeight:4000 },
                      addEventListener:(t, f) => { (oyentes[t] = oyentes[t] || []).push(f); } };
  global.window.addEventListener = (t, f) => { (oyentes[t] = oyentes[t] || []).push(f); };
  global.performance = { getEntriesByType: () => [{ type: tipoNav || 'navigate' }] };
  /* Sin service worker: aquí solo se prueba a dónde te lleva el menú. Que la app
     se ponga al día sola es otra cosa y se comprueba en `actualizacion.js`. */
  Object.defineProperty(global, 'navigator', { configurable:true, writable:true, value:{} });
  global.setInterval = () => 1; global.clearInterval = () => {};
  vm.runInThisContext(codigo, { filename:'continuidad.js' });
  return oyentes;
}
function avisar(oyentes, evento){ (oyentes[evento] || []).forEach(f => f()); }
function clicEnMenu(oyentes){
  (oyentes['click'] || []).forEach(f => f({ target:{ closest:s => s.indexOf('index.html') >= 0 ? {} : null } }));
}

const APPS    = ['tablero.html', 'captura_series.html', 'comisiones.html', 'admin.html'];
/* La última es un CRUCE, y por eso está: salir al menú a propósito y que Android
   mate la app después. El candado de sesión, que cubre todo lo demás, aquí no
   sirve —se vacía al relanzar— y lo único que impide volver a la pantalla que
   abandonaste es que `pagehide` no haya revivido la marca al salir.
   Sin esta fila, quitar esa protección no rompía ninguna prueba. */
const SALIDAS = ['toco el botón de menú', 'me voy sin más', 'Android mata la app',
                 'cambio a otra app', 'toco el botón y luego Android mata la app'];
const VUELTAS = ['recargando', 'restaurando'];

const fallos = [];
let probadas = 0;

for(const app of APPS)
 for(const salida of SALIDAS)
  for(const vuelta of VUELTAS)
   for(const conSesion of [true, false]){
     probadas++;
     for(const k of Object.keys(LS)) delete LS[k];
     if(conSesion) LS['hes_store'] = '{"store_id":"1217"}';
     relanzarApp();

     abrirPagina('index.html', '', 'navigate');          // abro la app
     const oy = abrirPagina(app, '#promo');              // entro a la pantalla

     if(salida.indexOf('toco el botón') === 0) clicEnMenu(oy);
     global.document.visibilityState = 'hidden';
     avisar(oy, 'pagehide'); avisar(oy, 'visibilitychange');
     if(salida.indexOf('Android mata la app') >= 0) relanzarApp();

     abrirPagina('index.html', '', vuelta === 'restaurando' ? 'back_forward' : 'navigate');
     const fue = global.__irA ? global.__irA.url : null;

     /* Solo hay UN caso en que el menú debe devolverte: cuando Android mató la
        app y hay sesión. En todos los demás llegaste al menú porque quisiste, y
        moverte de ahí es quitarte el control. */
     const debeDevolver = (salida === 'Android mata la app' && conSesion);
     const bien = debeDevolver ? (fue && fue.indexOf(app) === 0) : (fue === null);
     if(!bien){
       fallos.push(app + ' · ' + salida + ' · el menú vuelve ' + vuelta +
                   ' · ' + (conSesion ? 'con sesión' : 'sin sesión') +
                   '  ->  ' + (fue ? 'me manda a ' + fue : 'me deja en el menú') +
                   '   (debía ' + (debeDevolver ? 'devolverme a ' + app : 'dejarme en el menú') + ')');
     }
   }

/* Y que el menú quede en el historial: con `location.replace` el botón atrás
   del teléfono sacaba de la app entera en vez de llevar al menú. */
for(const k of Object.keys(LS)) delete LS[k];
LS['hes_store'] = '{"store_id":"1217"}';
relanzarApp();
abrirPagina('index.html', '', 'navigate');
const oy = abrirPagina('tablero.html', '#promo');
global.document.visibilityState = 'hidden'; avisar(oy, 'visibilitychange');
relanzarApp();
abrirPagina('index.html', '', 'navigate');
probadas++;
if(!global.__irA || global.__irA.modo !== 'href'){
  fallos.push('el menú debe EMPUJAR la pantalla al historial, no reemplazarse: ' +
              'con replace, el botón atrás saca de la app en vez de volver al menú');
}

if(fallos.length){
  console.log('navegación: ' + fallos.length + ' de ' + probadas + ' combinaciones fallan');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('navegación: ' + probadas + ' combinaciones de salir y volver, todas correctas');
