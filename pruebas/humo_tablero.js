/* ============================================================
   El tablero se pinta entero y sus números cuadran
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe porque el 8-ago-2026 se publicaron tres versiones seguidas con
   fallos que una pasada por las seis pantallas habría cazado. Las
   comprobaciones viven en `casos_tablero.js`; esto solo monta el escenario.

   Se usa `vm.runInThisContext` y no `eval`: el JavaScript del tablero
   declara sus funciones al modo de una página web, y desde un módulo de
   Node un eval normal las encierra en su propio ámbito.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { domFalso, TIENDA } = require('./entorno.js');

const raiz = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(raiz, 'tablero.html'), 'utf8');
const js = (html.match(/<script(?![^>]*\ssrc=)[^>]*>[\s\S]*?<\/script>/g) || [])
  .map(b => b.replace(/^<script[^>]*>/, '').replace(/<\/script>$/, '')).join('\n;\n');

if(js.length < 1000){
  console.log('humo: no encontré el JavaScript de tablero.html');
  process.exit(1);
}

domFalso();
global.TIENDA = TIENDA;
global.__fallos = [];
global.ok = function(titulo, condicion, detalle){
  if(!condicion) global.__fallos.push(titulo + (detalle ? '  -> ' + detalle : ''));
};

const casos = fs.readFileSync(path.join(__dirname, 'casos_tablero.js'), 'utf8');
try {
  vm.runInThisContext(js + '\n;\n' + casos, { filename:'tablero+casos.js' });
} catch(e){
  console.log('humo: el tablero se cayó al cargar o al pintar');
  console.log('   · ' + (e && e.message));
  process.exit(1);
}

if(global.__fallos.length){
  console.log('humo: ' + global.__fallos.length + ' fallo(s)');
  global.__fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('humo: el tablero se pinta entero y los números cuadran');
