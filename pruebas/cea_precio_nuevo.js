/* ============================================================
   El precio que se cobra es el NUEVO, no el que se venía cobrando
   ============================================================
   10-sep-2026. Corre en cada commit desde `verificar.py`.

   El caso que lo trae, con el comunicado real:
   **CEA HUAWEI 265 PROMOCIONES EOL SEPTIEMBRE 2026 3ER BLOQUE** (7-sep-2026),
   cuya tabla es:

     SKU · DESCRIPCIÓN · PRECIO REGULAR · PROMOCIÓN ANTERIOR · PROMOCIÓN NUEVA
          · 18MSI · 12MSI · 9MSI · 6MSI

   `_ceaPrecios` buscaba la columna a cobrar con `/NUEVA\s*PROMO/i`, que es la
   FRASE del CEA 257 ("NUEVA PROMO"). El 265 titula esa misma columna al revés
   —"PROMOCIÓN NUEVA"— así que no casaba, se caía al comodín `/PROMO/` y ahí
   ganaba **"PROMOCIÓN ANTERIOR"** por venir antes en el renglón.

   O sea: se cobraba el precio del que la promoción venía a bajar.

     Pura 80 Ultra   el CEA manda $23,698   se leía $31,999
     Pura 80 Pro     el CEA manda $15,548   se leía $20,998
     Pura 80 6.6"    el CEA manda  $8,890   se leía $11,990

   ⚠️ **Dos columnas de promo en el mismo renglón es lo normal, no la rareza.**
   Todo CEA que quiera enseñar la rebaja trae el precio viejo al lado del nuevo.
   Por eso no basta con acertarle a un título: hay que saber cuál de los dos es
   el viejo. `_CEA_PROMO_VIEJA` es esa lista, y el orden de las palabras del
   título no puede volver a decidir cuánto se cobra.

   ⚠️ Esta prueba mira SOLO la lectura del PDF. Que el precio leído llegue a la
   tienda es otra cadena —`saveEolFromPdf` manda hoy el PRECIO REGULAR y
   `eol_precio_venta` lo divide entre dos—, y eso se arregla aparte.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const raiz  = path.join(__dirname, '..');
const admin = fs.readFileSync(path.join(raiz, 'admin.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

const ent = crearEntorno({
  html: admin,
  ruta: '/t/admin.html',
  ls: { odemas_store: JSON.stringify({ store_id:'1217', nombre:'Angelopolis',
                                    gas_token:'t', vendedores:[] }),
        odemas_role: 'gerente',
        odemas_empleado: JSON.stringify({ empno:'1000001', nombre:'Quien sea',
                                       puesto:'Gerente de Tienda', admin:true }) }
});

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

if(ent.err){
  console.log('lector de CEA: admin.html no cargó -> ' + ent.err);
  process.exit(1);
}

/* Llama a `_ceaPrecios` dentro del ámbito del script de la página: es una
   `function` de nivel superior, pero `_CEA_NO_PRECIO` y `_CEA_PROMO_VIEJA` son
   `const` y no aparecen en el objeto global. */
function precios(columnas, tokens){
  const codigo = '(function(){' +
    'var COLS=' + JSON.stringify(columnas) + ';' +
    'function etiqueta(c){var m=null,d=1e9;' +
    '  COLS.forEach(function(k){var dd=Math.abs(k.c-c); if(dd<d){d=dd;m=k;}});' +
    '  return m?m.et:"";}' +
    'var px=' + JSON.stringify(tokens) + ';' +
    'return JSON.stringify(_ceaPrecios(px, etiqueta));})()';
  return JSON.parse(ent.correr(codigo));
}

/* Los precios llegan a `_ceaPrecios` ya sin el "$" (se lo quita `_ceaFila`). */
const P = (v, c) => ({ v: v, c: c });

/* ── 1 · CEA 265 · "PROMOCIÓN ANTERIOR" y "PROMOCIÓN NUEVA" ─────────────── */
{
  const COLS = [
    { c:340, et:'PRECIO REGULAR' },
    { c:415, et:'PROMOCIÓN ANTERIOR' },
    { c:490, et:'PROMOCIÓN NUEVA' }
  ];
  /* Los tres renglones del comunicado, con sus cifras tal cual. */
  const casos = [
    { nom:'Pura 80 Ultra', reg:'39,998.00', ant:'31,999.00', nue:'23,698.00' },
    { nom:'Pura 80 Pro',   reg:'29,998.00', ant:'20,998.00', nue:'15,548.00' },
    { nom:'Pura 80 6.6"',  reg:'21,490.00', ant:'11,990.00', nue:'8,890.00'  }
  ];
  casos.forEach(function(k){
    const r = precios(COLS, [P(k.reg,340), P(k.ant,415), P(k.nue,490)]);
    ok('CEA 265 · ' + k.nom + ': se cobra la PROMOCIÓN NUEVA',
       r.pp === k.nue, 'leyó ' + r.pp + ' y el CEA manda ' + k.nue);
    ok('CEA 265 · ' + k.nom + ': NO se cobra la PROMOCIÓN ANTERIOR',
       r.pp !== k.ant, 'leyó el precio viejo ' + k.ant);
    ok('CEA 265 · ' + k.nom + ': el regular sigue siendo el regular',
       r.pr === k.reg, 'leyó ' + r.pr);
  });
}

/* ── 2 · CEA 257 · la frase al derecho, que ya funcionaba ───────────────── */
/* Esto es lo que el arreglo no podía romper: es el comunicado de v226, con
   "PROMO ACTUAL" de precio viejo y "NUEVA PROMO" de precio a cobrar. */
{
  const COLS = [
    { c:340, et:'PRECIO REGULAR' },
    { c:415, et:'PROMO ACTUAL' },
    { c:490, et:'NUEVA PROMO' }
  ];
  const r = precios(COLS, [P('12,999.00',340), P('9,999.00',415), P('7,499.00',490)]);
  ok('CEA 257 · sigue cobrando la NUEVA PROMO', r.pp === '7,499.00', 'leyó ' + r.pp);
  ok('CEA 257 · el regular sigue siendo el regular', r.pr === '12,999.00', 'leyó ' + r.pr);
}

/* ── 3 · PRICE MATCH · el DESCUENTO no es un precio ─────────────────────── */
/* La columna DESCUENTO dice cuánto se rebaja, no cuánto se cobra: quedarse con
   ella cobraría de menos por goleada. La filtra `_CEA_NO_PRECIO`, y el arreglo
   no la toca — se comprueba para que siga así. */
{
  const COLS = [
    { c:340, et:'PRECIO REGULAR' },
    { c:415, et:'DESCUENTO' },
    { c:490, et:'PRICE MATCH' }
  ];
  const r = precios(COLS, [P('19,999.00',340), P('3,000.00',415), P('16,999.00',490)]);
  ok('PRICE MATCH · se cobra el price match', r.pp === '16,999.00', 'leyó ' + r.pp);
  ok('PRICE MATCH · el descuento no se cobra', r.pp !== '3,000.00');
}

/* ── 4 · Una sola columna de promo, y es "ACTUAL" ───────────────────────── */
/* Aquí "PROMO ACTUAL" SÍ es el precio a cobrar: no hay otro. Descartarla por
   llamarse "actual" dejaría el renglón sin precio, que es peor. Por eso el
   último `find` vuelve a admitir las viejas. */
{
  const COLS = [
    { c:340, et:'PRECIO REGULAR' },
    { c:430, et:'PROMO ACTUAL' }
  ];
  const r = precios(COLS, [P('5,999.00',340), P('4,499.00',430)]);
  ok('promo única · se cobra aunque se llame ACTUAL', r.pp === '4,499.00', 'leyó ' + r.pp);
}

/* ── 5 · Sin encabezado legible, el más barato ──────────────────────────── */
/* Si las etiquetas no se pudieron leer no hay nada que preferir, y la regla de
   abajo de `_ceaPrecios` toma el más caro como regular y el más barato como
   precio a cobrar. Se comprueba porque el arreglo añade dos `find` más y
   ninguno debe colarse cuando no hay título que mirar. */
{
  const COLS = [{ c:340, et:'' }, { c:415, et:'' }, { c:490, et:'' }];
  const r = precios(COLS, [P('39,998.00',340), P('31,999.00',415), P('23,698.00',490)]);
  ok('sin encabezado · regular = el más caro', r.pr === '39,998.00', 'leyó ' + r.pr);
  ok('sin encabezado · a cobrar = el más barato', r.pp === '23,698.00', 'leyó ' + r.pp);
}

/* ── 6 · Un CEA con precio NO entra por la puerta de EOL ────────────────── */
/* El CEA 265 metido por la pestaña de EOL se guarda con el PRECIO REGULAR y la
   tienda cobra la mitad: $19,999 donde el comunicado manda $23,698. Y peor que
   el precio, los marca EOL, que para el equipo significa "aquí no se vende
   seguro" — sobre ocho SKU de la serie que más se mueve, contra el KPI crítico.

   Se comprueba el COMPORTAMIENTO de la pantalla, no solo el filtro: que no deje
   filas listas para guardar y que el aviso diga a dónde ir. Con solo mirar el
   valor que devuelve una función, el botón podría seguir armado. */
function pasarPorPantallaEol(filas){
  ent.correr('parseEolPDF = async function(){ return ' +
             JSON.stringify({ rows: filas, vig: '7 al 30 de septiembre de 2026' }) + '; };');
  const manejador = ent.el('filePdfEol').onchange;
  return Promise.resolve(manejador({ target: { files: [{ name: 'CEA.pdf' }] } }))
    .then(function(){
      return { rows: ent.el('btnSaveEol')._rows,
               aviso: ent.htmlDe('resEol'),
               abierto: ent.el('previewEol').style.display };
    });
}

/* Las tres filas del CEA 265, como salen de `parseEolPDF`. */
const CEA265 = [
  { sku:'100269138', desc:'HUAWEI PURA 80 ULT 16/512GB DO', pr:'39,998.00', pp:'23,698.00', d1:'', d2:'' },
  { sku:'100269162', desc:'HUAWEI PURA 80 PRO 12/512GB NG', pr:'29,998.00', pp:'15,548.00', d1:'', d2:'' },
  { sku:'100272644', desc:'HUAWEI PURA 80 6.6" 12/256GB NG', pr:'21,490.00', pp:'8,890.00',  d1:'', d2:'' }
];

/* El CEA 189 y sus adendums: SKU, descripción y estatus. Ni un precio. */
const CEA189 = [
  { sku:'100250576', desc:'MATEPAD PRO 13.2" 12/512GB DO', pr:'', pp:'', d1:'', d2:'' },
  { sku:'100274957', desc:'HUAWEI WATCH GT6 1.32" AMLD NG', pr:'', pp:'', d1:'', d2:'' }
];

Promise.resolve()
  .then(function(){ return pasarPorPantallaEol(CEA265); })
  .then(function(r){
    ok('CEA con precio · no deja filas listas para guardar', !r.rows || !r.rows.length,
       'quedaron ' + ((r.rows && r.rows.length) || 0) + ' filas armadas');
    ok('CEA con precio · no abre el panel de guardar', r.abierto !== 'block', 'display=' + r.abierto);
    ok('CEA con precio · el aviso manda a Promociones', /Promociones/.test(r.aviso), r.aviso.slice(0,90));
    ok('CEA con precio · el aviso dice el precio que manda el CEA', /23,698/.test(r.aviso), r.aviso.slice(0,90));
    ok('CEA con precio · el aviso dice lo que se cobraría por aquí', /19,999/.test(r.aviso), r.aviso.slice(0,90));
    ok('CEA con precio · el aviso menciona Assurant', /Assurant/.test(r.aviso));
  })
  .then(function(){ return pasarPorPantallaEol(CEA189); })
  .then(function(r){
    /* Y el camino bueno sigue abierto: el listado sin precio entra como siempre.
       Un aviso que también frene al 189 dejaría la tienda sin poder marcar EOL. */
    ok('listado EOL sin precio · sigue entrando', !!(r.rows && r.rows.length === 2),
       'quedaron ' + ((r.rows && r.rows.length) || 0) + ' filas');
    ok('listado EOL sin precio · abre el panel de guardar', r.abierto === 'block', 'display=' + r.abierto);
    ok('listado EOL sin precio · sin aviso de promociones', !/Promociones/.test(r.aviso), r.aviso.slice(0,90));
  })
  .then(function(){
    if(fallos.length){
      console.log('lector de CEA: ' + fallos.length + ' fallo(s)');
      fallos.forEach(f => console.log('   · ' + f));
      process.exit(1);
    }
    console.log('lector de CEA: el precio a cobrar es el nuevo, y un CEA con precio no entra por la puerta de EOL');
  })
  .catch(function(e){
    console.log('lector de CEA: la prueba reventó -> ' + (e && e.message));
    process.exit(1);
  });
