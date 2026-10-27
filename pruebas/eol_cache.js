/* ============================================================
   Lo que cambia en la nube llega al teléfono
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Port de la 1217 (v302/v303, 26-oct-2026). Allá el CEA 283 reactivó el
   MateBook D16 (100279926) y subió su regular de $14,999 a $22,999. La compu
   lo veía bien; NINGÚN teléfono, por dos fallas del cache `odemas_inv_cache`:

     · `aplicarEol` solo agregaba lo que traía la nube, nunca quitaba: un SKU
       que salía de EOL se quedaba en el teléfono para siempre.
     · `aplicarInventario` solo ponía el precio si el item no traía uno, y el
       del cache siempre trae: el precio nuevo no llegaba nunca.

   Lo que se exige:
     1. con el cache viejo, al arrancar el D16 es EOL y cuesta $14,999;
     2. llega la nube sin él en EOL → deja de serlo, y el cache ya no lo trae;
     3. llega la nube con $22,999 → ese precio; uno vacío no borra el bueno;
     4. una respuesta de Supabase SIN campo eol no borra los EOL buenos.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const { domFalso } = require('./entorno.js');

const raiz = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(raiz, 'tablero.html'), 'utf8');
const js = (html.match(/<script(?![^>]*\ssrc=)[^>]*>[\s\S]*?<\/script>/g) || [])
  .map(b => b.replace(/^<script[^>]*>/, '').replace(/<\/script>$/, '')).join('\n;\n');

domFalso();
Object.assign(global, require('../nombres.js'));
global.TIENDA = undefined;

// El cache tal como lo tenían los teléfonos: el D16 todavía EOL y a $14,999.
localStorage.setItem('odemas_inv_cache', JSON.stringify({
  guardado: Date.now() - 3600e3,
  inventario: [
    { sku:'100279926', producto:'MATEBOOK D16 CI5 16GB 512GB GR', precio:14999, stock:0, exhibe:1 },
    { sku:'900004',    producto:'PRUEBA EOL CON PISO',            precio:1999,  stock:0, exhibe:1 }
  ],
  eol: [ { sku:'100279926', precio:14999 }, { sku:'900004', precio:1999 } ]
}));

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra !== undefined ? ' -> ' + JSON.stringify(extra) : '')); };

try {
  vm.runInThisContext(js, { filename:'tablero.html' });
} catch(e){
  console.log('eol cache: el tablero se cayó al cargar -> ' + (e && e.message));
  process.exit(1);
}
const correr = s => vm.runInThisContext(s);
const precioD16 = () => correr('(D.inventario.find(x => x.sku === "100279926")||{}).precio');

// 1 · El escenario de los teléfonos
ok('ARRANQUE · con el cache viejo el D16 es EOL', correr('eolSkuSet.has("100279926")'));
ok('ARRANQUE · y cuesta $14,999', precioD16() === 14999, precioD16());

// 2 · La nube ya no lo trae en EOL
correr('aplicarEol([{ sku:"900004", precio:1999 }]); guardarInvCache();');
ok('NUBE · el D16 deja de ser EOL', !correr('eolSkuSet.has("100279926")'));
ok('NUBE · ya no está en D.eol', !correr('(D.eol||[]).some(e => e.sku === "100279926")'));
ok('NUBE · el otro EOL sigue', correr('eolSkuSet.has("900004")'));
const guardado = JSON.parse(localStorage.getItem('odemas_inv_cache') || 'null');
ok('CACHE · lo que se guarda ya no trae al D16 en EOL',
   guardado && Array.isArray(guardado.eol) && !guardado.eol.some(e => e.sku === '100279926'),
   guardado && guardado.eol);
correr('aplicarEol([{ sku:"900004", precio:2500 }]);');
ok('NUBE · el precio del EOL es el de la nube', correr('(D.eol.find(e => e.sku === "900004")||{}).precio') === 2500);

// 3 · El precio de la nube manda
correr('aplicarInventario({ "100279926": { d:"MATEBOOK D16 CI5 16GB 512GB GR", o:5, v:0, e:0, ev:0, p:22999 } });');
ok('PRECIO · el D16 toma el de la nube', precioD16() === 22999, precioD16());
correr('aplicarInventario({ "100279926": { d:"MATEBOOK D16 CI5 16GB 512GB GR", o:5, v:0, e:0, ev:0, p:null } });');
ok('PRECIO · uno vacío no borra el bueno', precioD16() === 22999, precioD16());

// 3c · El nombre de la nube manda, y lo que la nube ya no trae sale del teléfono
correr('aplicarInventario({ "100279926": { d:"MATEBOOK D16 NOMBRE NUEVO", o:5, v:0, e:0, ev:0, p:22999 } });');
ok('NOMBRE · el de la nube', correr('(D.inventario.find(x => x.sku === "100279926")||{}).producto') === 'MATEBOOK D16 NOMBRE NUEVO');
ok('BORRADO · el 900004 ya no está en la nube: sale del teléfono', !correr('D.inventario.some(x => x.sku === "900004")'),
   correr('JSON.stringify(D.inventario.map(x => x.sku))'));
correr('guardarInvCache();');
const g2 = JSON.parse(localStorage.getItem('odemas_inv_cache') || 'null');
ok('BORRADO · y tampoco se vuelve a guardar', g2 && !g2.inventario.some(x => x.sku === '900004'), g2 && g2.inventario.map(x => x.sku));

// 4 · Sin campo eol no es «cero EOL»
const sinEol = correr('typeof _deSupabase === "function" ? _deSupabase({ inventario:[], promos:[] }) : null');
if(sinEol){
  ok('SUPABASE · sin campo eol no se manda una lista vacía', sinEol.eol === undefined, sinEol.eol);
} else {
  fallos.push('no encontré la función que traduce la respuesta de Supabase (_deSupabase)');
}

if(fallos.length){
  console.log('FALLAS en eol_cache.js:\n  - ' + fallos.join('\n  - '));
  process.exit(1);
}
console.log('eol cache: lo que sale de EOL y el precio nuevo de la nube llegan al teléfono, y una respuesta incompleta no borra lo bueno');
