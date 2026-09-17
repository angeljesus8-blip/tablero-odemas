/* ============================================================
   Un CEA de lanzamiento también tiene fecha, y sin fecha no se sube nada
   ============================================================
   17-sep-2026. Corre en cada commit desde `verificar.py`.

   El caso que lo trae, con el comunicado real:
   **CEA HUAWEI 269 LANZAMIENTO HUAWEI WATCH GT 7 Y GT 7 PRO** (10-sep-2026).

   El lector leyó sus 11 renglones perfectos —SKU, descripción, $8,999 → $6,999,
   los MSI— y la nube no guardó **ninguno**. `carga_promos` descarta toda fila
   sin `vigente_hasta`, y `_ceaVigencia` devolvió vacío porque ese CEA **no dice
   "Vigencia: X al Y"**: es de lanzamiento, y el precio nuevo no trae fecha de
   término anunciada. Lo único fechado es:

     "Las promociones se verán reflejadas en punto de venta
      a partir de 11 de septiembre 2026"

   Seis días cobrando $8,999 donde el CEA manda $6,999, en 11 SKU.

   ⚠️ **Y no se enteró nadie.** Con `promos: 0` la pantalla caía a un mensaje
   VERDE —"Enviado (11 promos, 0 EOL)"— que contaba las leídas del archivo, no
   las guardadas. Por eso esta prueba mira las dos mitades: que la fecha se lea,
   y que cuando no haya fecha la pantalla FRENE en vez de dar por bueno.

   ⚠️ La fecha de FIN sigue sin inventarse. "Sin fecha de fin" ya significó una
   vez "vigente para siempre" y se cobraron promociones terminadas; la escribe
   el gerente antes de subir.

   ⚠️ Los textos de abajo son los de pdf.js —no los de otro extractor—, tomados
   del navegador con la misma versión que carga `admin.html` (3.11.174). pdf.js
   parte los números: "3 0 de septiembre", "202 6". Están así a propósito.
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
  console.log('vigencia de CEA: admin.html no cargó -> ' + ent.err);
  process.exit(1);
}

const vigencia = flat =>
  JSON.parse(ent.correr('JSON.stringify(_ceaVigencia(' + JSON.stringify(flat) + '))'));

/* ── 1 · CEA 269 · lanzamiento, sin "Vigencia:" ─────────────────────────── */
/* Las tres "a partir de" del comunicado, en su orden real. Las dos primeras
   son de DISPONIBILIDAD —cuándo se puede vender—; la tercera es de PRECIO
   —cuándo la caja cobra la promoción—, y es la única que sirve. */
{
  const CEA269 =
    'CEA HUAWEI 269 LANZAMIENTO HUAWEI WATCH GT 7 Y GT 7 PRO EQUIPO DE TIENDAS: ' +
    'Huawei continúa fortaleciendo su portafolio de wearables. FECHAS DE VENTA ' +
    'A partir del 10 de septiembre , las tiendas podrán realizar la venta de los ' +
    'productos bajo el esquema de venta exclusiva. ' +
    'A partir del 17 de septiembre, comenzará la venta oficial para todo el publico. ' +
    'PUNTOS PARA CONSIDERAR 1. Las promociones se verán reflejadas en punto de venta ' +
    'a partir de 11 de septiembre 202 6 . 2. Verificar siempre la vigencia de las ' +
    'promociones antes de aplicarlas.';

  const v = vigencia(CEA269);
  ok('CEA 269 · toma la fecha de PUNTO DE VENTA', v.d1 === '2026-09-11',
     'leyó ' + (v.d1 || 'vacío') + ' y el CEA manda 2026-09-11');
  ok('CEA 269 · NO toma la de venta exclusiva (10-sep)', v.d1 !== '2026-09-10',
     'tomó la fecha de disponibilidad, no la del precio');
  ok('CEA 269 · NO toma la de venta al público (17-sep)', v.d1 !== '2026-09-17',
     'tomó la fecha de disponibilidad, no la del precio');
  ok('CEA 269 · el año partido "202 6" se lee como 2026',
     (v.d1 || '').slice(0,4) === '2026', 'leyó el año ' + (v.d1 || '').slice(0,4));
  /* Lo que el documento no dice, no se inventa. */
  ok('CEA 269 · la fecha de FIN se queda vacía', !v.d2,
     'se inventó un fin: ' + v.d2);
}

/* ── 2 · CEA 265 y 267 · los que SÍ traen "Vigencia:" no cambian ────────── */
/* El arreglo añade un camino nuevo y no puede tocar el viejo: estos dos se
   leían bien y se tienen que seguir leyendo igual. */
{
  const CEA265 =
    'Con el objetivo de agotar e impulsar el desplazamiento de los productos EOL ' +
    'en la Serie Pura 80, se comparten las nuevas promociones vigentes para el mes ' +
    'de septiembre de 2026. Asegurar su correcta ejecución durante la vigencia ' +
    'establecida. Vigencia: 7 al 3 0 de septiembre de 2026 . PROMOCIONES PARTICIPANTES';
  const v = vigencia(CEA265);
  ok('CEA 265 · inicio 7-sep', v.d1 === '2026-09-07', 'leyó ' + (v.d1 || 'vacío'));
  ok('CEA 265 · fin 30-sep',   v.d2 === '2026-09-30', 'leyó ' + (v.d2 || 'vacío'));

  const CEA267 =
    'Se comparte la nueva actualización de promociones vigentes para el mes de ' +
    'septiembre de 2026. Asegurar su correcta ejecución durante la vigencia ' +
    'establecida. Vigencia: 9 al 3 0 de septiembre de 2026 . PROMOCIONES PARTICIPANTES';
  const w = vigencia(CEA267);
  ok('CEA 267 · inicio 9-sep', w.d1 === '2026-09-09', 'leyó ' + (w.d1 || 'vacío'));
  ok('CEA 267 · fin 30-sep',   w.d2 === '2026-09-30', 'leyó ' + (w.d2 || 'vacío'));
}

/* ── 3 · CEA 223 · su "punto de venta" no trae día, y el EOL sí ─────────── */
/* Aquí está la trampa del camino nuevo. El 223 dice "en punto de venta a partir
   de la fecha de inicio de cada vigencia" —sin número— y DOS renglones después
   "los artículos EOL se verán reflejadas a partir del 5 de junio 2026".
   Si el camino nuevo agarrara esa segunda fecha, le pondría a TODAS las promos
   el 5 de junio y borraría el 3 de junio que sí trae el documento.

   ⚠️ Lo que lo impide NO es el `if(!d1)` —comprobado quitándolo: el 223 sigue
   saliendo bien—. Lo impide el regex, que exige un DÍA justo después de
   "a partir de" y en la misma oración que "punto de venta": la del 223 sigue
   con "la fecha de inicio", y la del 5 de junio está en otra oración y no
   dice "punto de venta". El `if(!d1)` cubre un caso distinto, y es el §4. */
{
  const CEA223 =
    'CEA HUAWEI 223 PROMOCIONES JUNIO 2026 EQUIPO DE TIENDAS: Se comparten las ' +
    'nuevas promociones vigentes para el mes de junio 2026. Vigencia: 0 3 al 30 de ' +
    'junio de 2026 SKU DESCRIPCIÓN PRECIO PROMOCIÓN ESTATUS 18MSI 12MSI ' +
    'PUNTOS PARA CONSIDERAR 1. Las promociones se verán reflejadas en punto de venta ' +
    'a partir de la fecha de inicio de cada vigencia. 1.1. Las promociones de los ' +
    'artículos EOL se verán reflejadas a partir del 5 de junio 2026 . ' +
    '2. Verificar siempre la vigencia de las promociones antes de aplicarlas.';

  const v = vigencia(CEA223);
  ok('CEA 223 · inicio 3-jun', v.d1 === '2026-06-03', 'leyó ' + (v.d1 || 'vacío'));
  ok('CEA 223 · fin 30-jun',   v.d2 === '2026-06-30', 'leyó ' + (v.d2 || 'vacío'));
  ok('CEA 223 · los EOL siguen arrancando el 5-jun', v.eolD1 === '2026-06-05',
     'leyó ' + (v.eolD1 || 'vacío'));
  ok('CEA 223 · el 5-jun de los EOL no se le pega al resto', v.d1 !== '2026-06-05',
     'el camino de lanzamiento pisó la vigencia real');
}

/* ── 4 · Un CEA con LAS DOS frases: manda "Vigencia:" ───────────────────── */
/* Esto es lo que guarda el `if(!d1)`, y no se cubría solo. Un comunicado puede
   traer su ventana completa Y ADEMÁS decir desde cuándo la caja la refleja:
   son dos datos distintos, y el bueno es el de la ventana. Sin el guard, la
   frase de punto de venta pisa el inicio real —aquí, 5 de junio donde el
   documento manda 3— y la tienda deja de cobrar la promo dos días. */
{
  const DOBLE =
    'Se comparten las nuevas promociones vigentes para el mes de junio 2026. ' +
    'Vigencia: 0 3 al 30 de junio de 2026 SKU DESCRIPCIÓN PRECIO PROMOCIÓN ' +
    'PUNTOS PARA CONSIDERAR 1. Las promociones se verán reflejadas en punto de venta ' +
    'a partir de 5 de junio 2026 . 2. Verificar siempre la vigencia.';

  const v = vigencia(DOBLE);
  ok('las dos frases · manda la ventana de "Vigencia:"', v.d1 === '2026-06-03',
     'leyó ' + (v.d1 || 'vacío') + ' — la frase de punto de venta pisó la vigencia');
  ok('las dos frases · el fin sigue siendo el de la ventana', v.d2 === '2026-06-30',
     'leyó ' + (v.d2 || 'vacío'));
}

/* ── 5 · Sin fecha de fin, la pantalla FRENA ────────────────────────────── */
/* La otra mitad del fallo. Que el lector no encuentre la fecha es recuperable
   —el gerente la escribe—; que la pantalla lo dé por bueno, no. */
function pasarPorPantallaPromos(filas, vig){
  ent.correr('parsePromosPDF = async function(){ return ' +
             JSON.stringify({ rows: filas, vig: vig || '' }) + '; };');
  const manejador = ent.el('filePromos').onchange;
  return Promise.resolve(manejador({ target: { files: [{ name: 'CEA.pdf' }] } }))
    .then(function(){
      return { apagado: ent.el('btnPromos').disabled,
               d1: ent.el('vigD1Promos').value,
               d2: ent.el('vigD2Promos').value,
               visible: ent.el('vigPromos').style.display,
               nota: ent.el('vigNotaPromos').innerHTML || '' };
    });
}

/* Las 11 del CEA 269 tal como salen del lector: con inicio y sin fin. */
const GT7 = [
  { sku:'100312757', desc:'HUAWEI WATCH GT7 PRO 46MM TI VD', pr:'8,999.00', pp:'6,999.00',
    est:'Activo', msi:'9,6', d1:'2026-09-11', d2:'' },
  { sku:'100312669', desc:'HUAWEI WATCH GT7 46MM AMOLED NG', pr:'6,999.00', pp:'4,999.00',
    est:'Activo', msi:'9,6', d1:'2026-09-11', d2:'' }
];

/* Las del 265, que sí traen las dos fechas. */
const CON_FIN = [
  { sku:'100269138', desc:'HUAWEI PURA 80 ULT 16/512GB DO', pr:'39,998.00', pp:'23,698.00',
    est:'EOL', msi:'', d1:'2026-09-07', d2:'2026-09-30' }
];

/* ── 6 · Lo que dice la pantalla DESPUÉS de subir ───────────────────────── */
/* El otro fallo del 269, y el que hizo que nadie se enterara en seis días: con
   `promos: 0` la pantalla pintaba VERDE —"Enviado (11 promos, 0 EOL)"— porque
   contaba las filas leídas del archivo, no las que la nube aceptó. Se leía
   como éxito habiendo entrado ninguna.

   Aquí se sustituye `sbCargaAdmin` por la respuesta real de `carga_promos`
   —{ok, promos, sin_fecha, precio_invalido}— para mirar sólo lo que se pinta.
   La clase la pone `showResult`: 'ok' es verde y 'bad' es rojo. */
function subirConRespuesta(resp){
  ent.correr('sbCargaAdmin = async function(){ return ' + JSON.stringify(resp) + '; };');
  return Promise.resolve(ent.correr('subirPromos()')).then(function(){
    return { clase: ent.el('resPromos').className,
             texto: (ent.htmlDe('resPromos') || '').replace(/<[^>]+>/g, ' ') };
  });
}

Promise.resolve()
  .then(function(){ return pasarPorPantallaPromos(GT7, 'a partir del 11 de septiembre'); })
  .then(function(r){
    ok('sin fecha de fin · el botón de subir queda APAGADO', r.apagado === true,
       'el botón quedó armado y la nube habría rechazado las 11');
    ok('sin fecha de fin · se pide la vigencia a la vista', r.visible === 'block',
       'display=' + r.visible);
    ok('sin fecha de fin · el aviso dice que sin ella no se guarda nada',
       /no guarda ninguna/i.test(r.nota), r.nota.slice(0,90));
    ok('sin fecha de fin · el inicio leído del CEA ya viene puesto',
       r.d1 === '2026-09-11', 'precargó ' + (r.d1 || 'vacío'));
    ok('sin fecha de fin · el fin se queda vacío para que lo escriban', !r.d2,
       'precargó un fin inventado: ' + r.d2);
  })
  .then(function(){
    /* Y escribiendo la fecha, el botón se arma: el freno no puede ser una
       puerta cerrada. */
    ent.el('vigD2Promos').value = '2026-09-30';
    ent.correr('vigPromosTocada=true; _vigPromosPintar();');
    ok('con la fecha escrita a mano · el botón se arma',
       ent.el('btnPromos').disabled === false, 'siguió apagado con vigencia completa');
  })
  .then(function(){
    /* Vigencia al revés: la base tiene un CHECK y rechazaría en silencio. */
    ent.el('vigD1Promos').value = '2026-10-15';
    ent.correr('vigPromosTocada=true; _vigPromosPintar();');
    ok('vigencia al revés · el botón se apaga',
       ent.el('btnPromos').disabled === true, 'dejó subir con el inicio después del fin');
  })
  .then(function(){ return pasarPorPantallaPromos(CON_FIN, '7 al 30 de septiembre de 2026'); })
  .then(function(r){
    ok('CEA con las dos fechas · el botón se arma solo', r.apagado === false,
       'un CEA completo se quedó frenado');
    ok('CEA con las dos fechas · se precargan las del documento',
       r.d1 === '2026-09-07' && r.d2 === '2026-09-30',
       'precargó ' + r.d1 + ' al ' + r.d2);
  })
  .then(function(){ return pasarPorPantallaPromos(GT7, 'a partir del 11 de septiembre'); })
  .then(function(){
    ent.el('vigD2Promos').value = '2026-09-30';
    ent.correr('vigPromosTocada=true; _vigPromosPintar();');
    /* Lo que devolvió la nube con el CEA 269: leyó las filas y no guardó ninguna. */
    return subirConRespuesta({ ok:true, promos:0, sin_fecha:2, precio_invalido:0 });
  })
  .then(function(r){
    ok('ninguna guardada · el resultado se pinta en ROJO', /\bbad\b/.test(r.clase),
       'clase=' + r.clase + ' — cero guardadas se dio por bueno');
    ok('ninguna guardada · lo dice con todas sus letras',
       /no se guardó ninguna promoción/i.test(r.texto), r.texto.trim().slice(0,110));
    ok('ninguna guardada · dice POR QUÉ las rechazó',
       /sin fecha de vigencia/i.test(r.texto), r.texto.trim().slice(0,110));
    ok('ninguna guardada · avisa que el tablero sigue con el precio regular',
       /precio regular/i.test(r.texto), r.texto.trim().slice(0,110));
    ok('ninguna guardada · no cuenta las leídas como guardadas',
       !/\b2\b[^]{0,24}promos actualizadas/i.test(r.texto), r.texto.trim().slice(0,110));
  })
  .then(function(){
    /* Guardadas unas sí y otras no: el número que se anuncia es el de la nube. */
    return subirConRespuesta({ ok:true, promos:1, sin_fecha:1, precio_invalido:0 });
  })
  .then(function(r){
    ok('unas sí y otras no · se anuncia lo guardado, no lo leído',
       /1\s+de\s+2\s+promos actualizadas/i.test(r.texto), r.texto.trim().slice(0,110));
    ok('unas sí y otras no · las que faltan se quedan en pantalla',
       /se quedaron fuera/i.test(r.texto), r.texto.trim().slice(0,110));
  })
  .then(function(){
    return subirConRespuesta({ ok:true, promos:2, sin_fecha:0, precio_invalido:0 });
  })
  .then(function(r){
    ok('todas guardadas · verde, y con la vigencia con la que se subieron',
       /\bok\b/.test(r.clase) && /2026-09-11\s+al\s+2026-09-30/.test(r.texto),
       r.clase + ' | ' + r.texto.trim().slice(0,110));
  })
  .then(function(){
    if(fallos.length){
      console.log('vigencia de CEA: ' + fallos.length + ' fallo(s)');
      fallos.forEach(f => console.log('   · ' + f));
      process.exit(1);
    }
    console.log('vigencia de CEA: un lanzamiento sin "Vigencia:" tiene fecha de inicio, y sin fecha de fin no se sube nada');
  })
  .catch(function(e){
    console.log('vigencia de CEA: la prueba reventó -> ' + (e && e.message));
    process.exit(1);
  });
