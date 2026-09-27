/* ============================================================
   Un cambio de PRECIO DE LISTA no es una promoción
   ============================================================
   26-sep-2026. Corre en cada commit desde `verificar.py`.

   CEA HUAWEI 273 «BAJA DE PRECIO EN MATEPAD» (15-sep-2026): siete MatePad
   cambian de precio REGULAR a partir del 15 de septiembre, sin fecha de fin.
   Su tabla:

     SKU · DESCRIPCIÓN · PRECIO REGULAR ANTERIOR · PRECIO REGULAR NUEVO
         · 18MSI · 12MSI · 9MSI · 6MSI

   Por Promos entraba como oferta: `_ceaPrecios` tomaba el anterior por
   regular y, sin columna de promo, el nuevo por precio de promoción. Promos
   exige fecha de fin, así que hubo que inventarla (30-sep), y el 1 de octubre
   la app volvía a cobrar el precio viejo mientras Sonar no se pusiera al día.

   La muestra `cea/cea273_items.json` son los fragmentos de la página 1 del PDF
   real, sacados con la MISMA pdf.js que carga admin.html (3.11.174). La
   página 2 —firmas— no se guarda: no hace falta y trae nombres.

   Lo que se exige aquí:
     1. el lector lo reconoce como cambio de lista, con sus 7 SKU, precio
        anterior y nuevo, desde el 15-sep, sin fecha de fin, y sus MSI;
     2. un CEA de promociones de verdad (dos columnas de promo) NO se confunde;
     3. la pantalla no pide fecha de fin y sube a `carga_precio_lista`,
        no a `carga_promos`.

   La regla del lado de la base (el trigger que no deja a Sonar regresar el
   precio) se probó contra Postgres de verdad al escribirla; ver el encabezado
   de supabase_precio_lista.sql.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const raiz = path.join(__dirname, '..');
const admin = fs.readFileSync(path.join(raiz, 'admin.html'), 'utf8');
const items = JSON.parse(fs.readFileSync(path.join(__dirname, 'cea', 'cea273_items.json'), 'utf8'));
const { crearEntorno } = require('./dom.js');

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra !== undefined ? ' -> ' + JSON.stringify(extra) : '')); };

const ent = crearEntorno({
  html: admin, ruta: '/t/admin.html',
  ls: { odemas_store: JSON.stringify({ store_id:'9999', nombre:'Tienda Demo', gas_token:'t', vendedores:[] }),
        odemas_role: 'gerente' }
});
if(ent.err){ console.log('cea precio de lista: admin.html no cargó -> ' + ent.err); process.exit(1); }

/* El CEA 273 tal cual: 7 SKU, anterior → nuevo. */
const ESPERADO = {
  '100219923': ['6,999.00', '4,999.00'], '100219940': ['6,999.00', '4,999.00'],
  '100270526': ['7,990.00', '5,990.00'], '100270542': ['8,999.00', '6,999.00'],
  '100270551': ['8,990.00', '7,990.00'], '100270585': ['9,999.00', '8,999.00'],
  '100270577': ['9,999.00', '8,999.00'],
};

(async () => {
  ent.caja.__items = items;
  ent.correr('_ceaItemsPDF = async function(){ return __items; }');

  /* 1 · El lector, con el PDF real */
  const t = await ent.correr('_ceaTablaPDF({ name: "CEA_HUAWEI_273_BAJA_DE_PRECIO_EN_MATEPAD.pdf" })');
  ok('CEA 273 · se reconoce como cambio de precio de lista', t && t.tipo === 'lista', t && t.tipo);
  ok('CEA 273 · trae sus 7 SKU', t && t.rows.length === 7, t && t.rows.map(r => r.sku));
  (t ? t.rows : []).forEach(r => {
    const e = ESPERADO[r.sku];
    ok('CEA 273 · ' + r.sku + ' anterior y nuevo del renglón', e && r.pa === e[0] && r.pn === e[1], [r.pa, r.pn]);
    ok('CEA 273 · ' + r.sku + ' desde el 15 de septiembre', r.d1 === '2026-09-15', r.d1);
    ok('CEA 273 · ' + r.sku + ' sin fecha de fin', r.d2 === undefined, r.d2);
    ok('CEA 273 · ' + r.sku + ' con 9 y 6 MSI', r.msi === '9,6', r.msi);
  });
  ok('CEA 273 · el número del comunicado', t && t.cea === 'CEA 273', t && t.cea);

  /* 2 · Un CEA de promociones no se confunde: columnas del 265 y del 257. */
  const col = ets => JSON.stringify(ets.map((et, i) => ({ c: i * 50, et })));
  ok('CEA 265 (promoción anterior / nueva) sigue siendo promo',
     ent.correr('_ceaEsCambioLista(' + col(['SKU','DESCRIPCIÓN','PRECIO REGULAR','PROMOCIÓN ANTERIOR','PROMOCIÓN NUEVA','9MSI']) + ', "CEA HUAWEI 265 PROMOCIONES EOL")') === false);
  ok('CEA 257 (promo actual / nueva promo) sigue siendo promo',
     ent.correr('_ceaEsCambioLista(' + col(['SKU','DESCRIPCIÓN','PRECIO REGULAR','PROMO ACTUAL','NUEVA PROMO']) + ', "CEA 257 PROMOCIONES")') === false);
  ok('Un CEA de promo que dice «baja de precio» en la prosa sigue siendo promo',
     ent.correr('_ceaEsCambioLista(' + col(['SKU','PRECIO REGULAR','PRECIO PROMOCIÓN']) + ', "aprovecha la baja de precio en promociones")') === false);
  ok('Sin encabezado legible, el título «BAJA DE PRECIO» basta',
     ent.correr('_ceaEsCambioLista([], "CEA HUAWEI 273 BAJA DE PRECIO EN MATEPAD")') === true);

  /* 3 · La pantalla: sin fecha de fin, y a la función que toca */
  ent.correr('parsedPromos = ' + JSON.stringify(t) + ';');
  ent.el('vigD1Promos').value = '2026-09-15';
  ent.el('vigD2Promos').value = '';
  ent.correr('_vigPromosPintar()');
  ok('PANTALLA · sin fecha de fin el botón SÍ se enciende', ent.el('btnPromos').disabled === false);
  ent.el('vigD1Promos').value = '';
  ent.correr('_vigPromosPintar()');
  ok('PANTALLA · sin fecha de inicio NO', ent.el('btnPromos').disabled === true);
  ent.el('vigD1Promos').value = '2026-09-15';

  ent.correr(`window.__llamadas = [];
    sbCargaAdmin = async function(fn, p){ __llamadas.push({ fn: fn, p: p });
      return { ok:true, guardados:7, aplicados:5, sin_catalogo:2, promos_quitadas:7 }; };`);
  await ent.correr('subirPromos()');
  const ll = ent.correr('__llamadas');
  ok('SUBIR · va a carga_precio_lista', ll.length === 1 && ll[0].fn === 'carga_precio_lista', ll.map(x => x.fn));
  ok('SUBIR · nunca a carga_promos', !ll.some(x => x.fn === 'carga_promos'));
  ok('SUBIR · con las 7 filas y la fecha', ll[0] && ll[0].p.p_filas.length === 7 && ll[0].p.p_filas.every(f => f.d1 === '2026-09-15'));
  ok('SUBIR · con el número de CEA', ll[0] && ll[0].p.p_cea === 'CEA 273', ll[0] && ll[0].p.p_cea);
  const res = ent.el('resPromos').innerHTML;
  ok('SUBIR · dice cuántos, y lo de las promos quitadas', /7<\/b> precios de lista/.test(res) && /se quitaron 7 promociones/.test(res), res);

  if(fallos.length){
    console.log('FALLAS en cea_precio_lista.js:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('cea precio de lista: el CEA 273 entra como precio regular desde el 15-sep, sin fecha de fin, y los de promo siguen siendo promo');
})().catch(e => { console.log('FALLA cea_precio_lista.js: ' + (e && e.stack || e)); process.exit(1); });
