/* ============================================================
   Lo que la foto de una etiqueta trae de verdad
   ============================================================
   21-sep-2026. Corre en cada commit desde `verificar.py`.

   El caso que lo trae, medido con 16 fotos reales de piso —teléfono,
   tablet, audífonos, relojes, ruteadores, etiqueta blanca y negra— con
   el UPC y la serie de cada una anotados a mano:

       ANTES  serie   7/16 correcta · 4 MAL · 5 vacía
       AHORA  serie  14/16 correcta · 0 MAL · 2 vacía

   ⚠️ LAS CUATRO «MAL» SON EL MOTIVO DE ESTE ARCHIVO, no las vacías. El
   lector viejo mandaba a Serie todo código que no fuera EAN, y la
   etiqueta trae hasta cinco: EAN, IMEI1, IMEI2, MAC, EID y la serie. Así
   que el campo se llenaba con el IMEI del teléfono, con la MAC del
   ruteador o con el EID del reloj. Y eso NO SE VE: el asesor encuentra
   la casilla llena, la da por buena y ese número viaja a la Hoja de
   Google como número de serie de la venta.

   Peor todavía: el campo lleno impedía que corriera el OCR, que era
   justo lo que habría sacado la serie de verdad.

   Los valores de abajo son de las fotos reales, no inventados. Si una
   regla se afloja, aquí se cae. */

const assert = require('assert');
const L = require('../lector_etiqueta.js');

let n = 0;
function prueba(nombre, fn){ n++; try{ fn(); }catch(e){
  console.error('FALLA · ' + nombre + '\n  ' + e.message); process.exit(1);
} }

/* ── 1 · Cada código se reconoce por su forma ───────────────── */
prueba('la serie de 16 se reconoce como serie', function(){
  ['63M0226306004887','4DB0225C18000141','5QJTQ25914000660','7YVYD26515419246',
   '54P7S26205002034','6DTQU26120000787','4ZHBB26421202653'].forEach(function(v){
    assert.strictEqual(L.claseCodigo(v, 'code_128'), 'serie', v);
  });
});

prueba('IMEI, MAC y EID NO son la serie', function(){
  // Los cuatro valores que de verdad acabaron en el campo Serie.
  assert.strictEqual(L.claseCodigo('864661080525904', 'code_128'), 'imei');
  assert.strictEqual(L.claseCodigo('868256082561829', 'code_128'), 'imei');
  assert.strictEqual(L.claseCodigo('78F09B5845A7', 'code_128'), 'mac');
  assert.strictEqual(L.claseCodigo('F83B7E8DDDAA', 'code_128'), 'mac');
  assert.strictEqual(L.claseCodigo('24A48768A0DB', 'code_128'), 'mac');
  assert.strictEqual(L.claseCodigo('89034011023210000000000100203045', 'code_128'), 'eid');
});

prueba('el QR se ignora venga como venga', function(){
  ['qr_code','QR_CODE','data_matrix','pdf417','aztec'].forEach(function(f){
    assert.strictEqual(L.claseCodigo('7YDTQ26730000768', f), null, f);
  });
});

/* ── 2 · El enrutado no deja que lo flojo pise lo firme ─────── */
prueba('con IMEI, EID y serie en la misma etiqueta, gana la serie', function(){
  // m03 · Watch Ultimate 2: el lector viejo se quedaba con el EID.
  const r = L.repartirCodigos([
    { rawValue:'6942103169380', format:'ean_13' },
    { rawValue:'860499080227831', format:'code_128' },
    { rawValue:'5QJTQ25914000660', format:'code_128' },
    { rawValue:'89034011023210000000000100203045', format:'code_128' }
  ]);
  assert.strictEqual(r.serie, '5QJTQ25914000660');
  assert.strictEqual(r.upc, '6942103169380');
  assert.ok(r.serieFirme);
});

prueba('la serie no la pisa la MAC que viene detrás', function(){
  // m16 · WiFi AX3S: la serie llegaba PRIMERO y la MAC la sobreescribía.
  const r = L.repartirCodigos([
    { rawValue:'6DTQU26120000787', format:'code_128' },
    { rawValue:'24A48768A0DB', format:'code_128' },
    { rawValue:'6942103173011', format:'ean_13' }
  ]);
  assert.strictEqual(r.serie, '6DTQU26120000787');
});

prueba('si sólo hay MAC, la casilla se queda vacía', function(){
  // m11 · WiFi BE3: vale más vacía que con la MAC dentro.
  const r = L.repartirCodigos([
    { rawValue:'F83B7E8DDDAA', format:'code_128' },
    { rawValue:'6942103160486', format:'ean_13' }
  ]);
  assert.strictEqual(r.serie, '');
});

/* ── 3 · El texto del OCR, tal como sale de verdad ───────────
   Estas tres líneas están copiadas del texto que devolvió Tesseract
   sobre las fotos reales, con la basura pegada incluida. El patrón
   viejo —«S», barra opcional, «N», UN separador— tiraba las dos
   primeras, y eran series completas y correctas. */
prueba('«S/N:-» con dos separadores seguidos', function(){
  const r = L.serieDeTexto('TEECIMATTOCTEON 3\nS/N:-7YDTQ26730000768 3 RR 1');
  assert.strictEqual(r && r.v, '7YDTQ26730000768');
});

prueba('«SIN » cuando la barra sale como I', function(){
  const r = L.serieDeTexto('MITUM-B49 I\nSIN 7YDTQ26730000768 4 L E');
  assert.strictEqual(r && r.v, '7YDTQ26730000768');
});

prueba('una línea de IMEI sola no da serie', function(){
  assert.strictEqual(L.serieDeTexto('IMEI1:864558071207361 53421634DEEE'), null);
});

/* ── 4 · Lo que el OCR se inventa ────────────────────────────
   Los dos falsos positivos que aparecieron al medir. Los dos tienen 16
   caracteres y pinta de serie; ninguno lo es. */
prueba('16 letras seguidas no son una serie', function(){
  // El OCR pegó «BUSTA DISPOSITIVO» de la tabla de reciclaje italiana.
  assert.strictEqual(L.serieDeTexto('BUSTA DISPOSITIVO BUSTADISPOSITIVO LDPE 4'), null);
});

prueba('16 con letras en la cola no pasan del OCR', function(){
  // Salió `1L03PQU261290000` donde decía `63PQU26129000907`.
  assert.strictEqual(L.serieDeTexto('S/N:1L03PQU261290000 30'), null);
  assert.ok(!L.formaDeSerie('1L03PQU261290000'));
  assert.ok(L.formaDeSerie('63PQU26129000907'));
});

prueba('la forma se le exige al OCR, NO al código de barras', function(){
  /* El Mate XT rompe el molde: `4DB0225C18000141` lleva una C en la cola.
     Entra por código de barras, que devuelve el valor exacto o nada — y
     por eso el enrutado no le pide la forma. Si algún día se la pidiera,
     esa caja dejaría de capturarse y nadie sabría por qué. */
  assert.ok(!L.formaDeSerie('4DB0225C18000141'));
  const r = L.repartirCodigos([{ rawValue:'4DB0225C18000141', format:'code_128' }]);
  assert.strictEqual(r.serie, '4DB0225C18000141');
  assert.ok(r.serieFirme);
});

/* ── 5 · El UPC se comprueba antes de creerlo ────────────────
   Respaldo para cuando el EAN esté rayado: el número va impreso debajo
   del código y el OCR lo parte en grupos. Sin el dígito verificador, un
   dígito mal leído entra al catálogo como otro producto. */
prueba('el dígito verificador acepta los 16 EAN reales', function(){
  ['6942103187766','6942103149290','6942103169380','6942103164774','6942103198076',
   '6942103165450','6942103196782','6942103125379','6942103173004','6942103147746',
   '6942103160486','6942711308034','6942103193668','6942711308232','6942103173011'
  ].forEach(function(e){ assert.ok(L.eanValido(e), e); });
});

prueba('y rechaza el mismo EAN con un dígito cambiado', function(){
  assert.ok(!L.eanValido('6942103187767'));
  assert.ok(!L.eanValido('6942103187666'));
});

prueba('el UPC se junta aunque el OCR lo parta en grupos', function(){
  assert.strictEqual(L.upcDeTexto('HECHO EN CHINA\n6 942103 187766\nDual SIM'), '6942103187766');
});

prueba('un número de 13 dígitos que no verifica NO se usa', function(){
  // Antes cualquier tira de 12-13 dígitos pasaba por UPC.
  assert.strictEqual(L.upcDeTexto('ANATEL 04751250325 7 IC 25182'), null);
});

console.log('lector_etiqueta: ' + n + ' pruebas OK');
