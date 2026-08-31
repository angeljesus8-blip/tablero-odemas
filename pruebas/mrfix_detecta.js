/* ============================================================
   Mr Fix: el TICKET decide si es accesorio o reparacion
   ============================================================
   Corre en cada commit desde `verificar.py`.

   El asesor ya no elige el tipo a mano: los accesorios se reconocen por su
   codigo de articulo (43739 y los dos de Office) y las reparaciones por los
   suyos, que el gerente configura en Admin. Los dos salen del ticket detras de
   `SERVICIO:`.

   Lo que se vigila aqui no es que acierte, sino CUANDO SE CALLA. Equivocarse
   no es un campo mal puesto: manda la venta a la otra tabla. Un accesorio
   guardado como reparacion no entra en el Excel regional y esa comision no se
   le paga a nadie, sin que nada avise. Y el OCR de esta impresora falla de
   verdad: `CARGA100WTS` se leyo `CARGATOONTS 2 77`.

   Por eso hay tres casos que NO puede decidir: ticket con las dos cosas,
   ticket sin codigos reconocibles, y codigos sin configurar.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');
const codigos = fs.readFileSync(path.join(__dirname, '..', 'acc_codigos.js'), 'utf8');

/* Se ejecutan SOLO las piezas que deciden, no la pantalla entera: `accClave`
   y `accPrefijo` de acc_codigos.js, y `accCodigos` + `accQueEs` de la pagina.
   Asi la prueba falla por la regla y no por cualquier otra cosa del panel.

   `SKUS_REP` se saca del propio HTML y no se reescribe aqui: si se copiara, el
   dia que cambie como se parte la lista —hoy por coma, espacio o salto— esta
   prueba seguiria probando la version vieja y diria que todo va bien. */
function motor(skusRep, storeId){
  const trozo = (nombre) => {
    const i = html.indexOf('function ' + nombre + '(');
    if(i < 0) throw new Error('no encuentro ' + nombre + ' en captura_series.html');
    let j = html.indexOf('{', i), hondo = 0, k = j;
    for(; k < html.length; k++){
      if(html[k] === '{') hondo++;
      else if(html[k] === '}'){ hondo--; if(!hondo) break; }
    }
    return html.slice(i, k + 1);
  };
  /* Igual que SKUS_REP y ACC_SKUS: las declaraciones se traen del HTML en vez
     de copiarse. `ACC_RE_PIE` es el ancla del pie del ticket y se construye con
     el numero de tienda; copiarla aqui seria probar una version congelada que
     seguiria diciendo que todo va bien el dia que cambie. */
  const declConst = (nombre) => {
    const i = html.indexOf('const ' + nombre + ' =');
    if(i < 0) throw new Error('no encuentro `const ' + nombre + '` en captura_series.html');
    return html.slice(i, html.indexOf(';', i) + 1);
  };

  const decl = html.indexOf('var SKUS_REP =');
  if(decl < 0) throw new Error('no encuentro `var SKUS_REP =` en captura_series.html');
  const finDecl = html.indexOf(';', decl);

  /* `ACC_SKUS` tambien sale del HTML. Copiar aqui los tres codigos de
     accesorio seria tener la lista en dos sitios: el dia que se añada uno, la
     prueba seguiria comprobando los de antes y diria que todo va bien. */
  const dAcc = html.indexOf('var ACC_SKUS =');
  if(dAcc < 0) throw new Error('no encuentro `var ACC_SKUS =` en captura_series.html');
  const finAcc = html.indexOf(';', dAcc);

  /* `store_id` va aqui porque el ancla del pie del ticket se construye con el
     numero de tienda, no con un `1217` escrito en el codigo: cada tienda lo
     tiene distinto. Los tickets de `pruebas/` son de la 1217, asi que la sesion
     simulada tiene que decir 1217 o no casaria el pie — y sin pie no hay fecha
     ni folio. Ese es justo el caso que cubre `sin sesion de tienda` mas abajo. */
  const caja = { _cfgCS: { sku_reparacion: skusRep, store_id: storeId || '1217' },
                 _accTipo: 'acc', RegExp, String };
  vm.createContext(caja);
  /* `accPartirSkus` va aparte desde el 24-ago: SKUS_REP dejo de ser constante
     porque `abrirAcc` lo refresca del servidor, y partir la lista se saco a su
     propia funcion. Se traen las dos del HTML, sin copiar ninguna. */
  vm.runInContext(codigos + '\n' +
    declConst('ACC_TIENDA') + '\n' + declConst('ACC_RE_PIE') + '\n' +
    trozo('accPartirSkus') + '\n' +
    html.slice(dAcc, finAcc + 1) + '\n' + html.slice(decl, finDecl + 1) + '\n' +
    /* `accCodigos` se carga aunque `accQueEs` ya no lo use: si alguien vuelve
       a leerlo de ahi —el fallo del 24-ago— la prueba tiene que fallar diciendo
       QUE decidio mal, no «accCodigos is not defined», que suena a prueba rota
       y no a deteccion rota. */
    trozo('accCodigos') + '\n' +
    trozo('accNum') + '\n' + trozo('accNum3') + '\n' +
    trozo('accLineasArticulo') + '\n' +
    trozo('accSkuNorm') + '\n' + trozo('accDistancia') + '\n' + trozo('accSkusDeLineas') + '\n' +
    trozo('accExtraer') + '\n' + trozo('accQueEs'), caja);
  const fn = (texto) => vm.runInContext('accQueEs(' + JSON.stringify(texto) + ')', caja);
  fn.extraer = (texto, tipo) => {
    caja._accTipo = tipo || 'acc';
    return vm.runInContext('accExtraer(' + JSON.stringify(texto) + ')', caja);
  };
  return fn;
}

/* Los DOS de la 1217, dichos por Angel el 24-ago-2026. Son dos y no uno, y esa
   es la razon de que la configuracion sea una lista: con uno solo configurado,
   las reparaciones cobradas con el OTRO se guardarian como accesorio y
   entrarian en el Excel de comisiones. */
const REP_A = '100175537', REP_B = '100175545';
const queEs = motor(REP_A + ',' + REP_B);
const soloUno = motor(REP_A);            // como si se hubiera configurado a medias
const sinConfigurar = motor('');
const conCeros = motor('000' + REP_B);   // mismo sku, escrito con ceros delante

/* EL TEXTO QUE DE VERDAD SALE DEL OCR, guardado tal cual en
   `pruebas/ocr_ticket_real.txt` (24-ago-2026).

   No es el ticket transcrito a mano: es lo que Tesseract devuelve al leer la
   foto, con el borde del papel convertido en `N`, `NN`, `ON`, con rayas donde
   el papel solo tiene separacion, y con el IMEI leido `SERIEDEMO0000001`.

   Las series, el telefono y los nombres van cambiados por otros de la misma
   forma y la misma longitud: son tickets de una tienda de verdad. Lo que NO se
   toco es nada de lo que la prueba mide —importes, numeros de ticket, fechas y
   los fallos del OCR—, porque ahi esta el valor de guardar el crudo.

   Esta es la diferencia entre las tres versiones que fallaron y esta. Las tres
   se escribieron contra el ticket COMO SE VE, y las tres pasaban sus pruebas.
   Un ticket transcrito por quien escribe el codigo confirma lo que ese codigo
   ya supone; el crudo es el unico que puede desmentirlo. */
const T_REAL_REP = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real.txt'), 'utf8');

/* SEGUNDA lectura del MISMO ticket, otra foto (24-ago-2026). El OCR no da dos
   veces lo mismo, y aqui salieron dos fallos que la primera no tenia:

     · el sku `100175545` se leyo `100175540` — el ultimo 5 por un 0;
     · el precio `1124.390` se leyo `1124390`, sin el punto.

   Los dos se ven en la misma linea: `(Ei 100175540 1 1124390 $1,124.39 1 0)`.
   Guardar las DOS lecturas del mismo papel es lo que obliga al codigo a
   aguantar un OCR que falla distinto cada vez, en vez de a acertar una. */
const T_REAL_REP2 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real2.txt'), 'utf8');

/* TERCER ticket (24-ago-2026), con el fallo mas raro de los tres: la CANTIDAD
   no esta en la linea del articulo.

       REP FUERA DE GARANTIA HW 1 1
       100175537 877.270 $877.27 | y

   El `1` se fue al renglon del nombre. Tres fotos, tres fallos distintos: el
   ruido del borde, un digito mal leido con el punto perdido, y ahora una
   columna que se muda de linea. Ninguno se habria adivinado leyendo el papel. */
const T_REAL_REP3 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real3.txt'), 'utf8');

/* CUARTO ticket, y el primero de ACCESORIO (24-ago-2026). Dos fallos mas:

     · el importe `$999.00` se leyo `$993.00`, asi que precio x cantidad no
       cerraba y el aviso mandaba a revisar una venta que estaba bien;
     · la fecha `23/8/26` se leyo `23/0/26` — mes cero, que no existe.

   El propio papel desmiente el importe dos veces: `Total 999.00` y
   `Recuento de articulos vendidos = 1`. Ese total solo vale con UN articulo, y
   por eso la correccion lo comprueba antes. */
const T_REAL_ACC4 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real4.txt'), 'utf8');

/* QUINTO ticket: otra foto del MISMO accesorio que el cuarto, con dos fallos
   que ningun otro tenia.

       000943739 1 999,000 $999,00 1 =

     · el sku `000043739` salio `000943739` — un 4 leido como 9. Los accesorios
       se comparaban por prefijo exacto, asi que la linea no se encontraba: ni
       sku ni precio. Y quitar los ceros de delante lo empeoraba, porque el
       fallo cae JUSTO en esa zona y los dos codigos acababan midiendo distinto.
     · el importe `$999,00` viene con COMA decimal, no con punto. Borrando las
       comas sin mirar salia 99900: cien veces mas. */
const T_REAL_ACC5 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real5.txt'), 'utf8');

/* SEXTO ticket: la linea del articulo PARTIDA EN DOS.

       10004373
       mer 149,000 $149.00 1

   El sku solo en un renglon y los numeros en el siguiente. Y encima el sku
   quedo irreconocible —`000043739` leido `10004373`: perdio el 9 del final y
   gano un 1 delante, seis digitos de diferencia—, asi que ni la tolerancia lo
   salva. Se usa igual porque en todo el ticket hay UNA sola linea de articulo:
   no hay nada que elegir. */
const T_REAL_ACC6 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real6.txt'), 'utf8');

/* SEPTIMO ticket: el PRECIO mal leido y sin `Total` con el que desempatar.

       000043739 1 399,000 $999,00 |

   El precio `999.000` salio `399,000` —un 9 por un 3— y el `Total` de ese papel
   quedo ilegible, asi que no habia con que comprobarlo. Pero el mismo numero
   esta dicho una tercera vez mas abajo:

       I-IVA 16% 861.21 137.79

   base mas impuesto, que suman exactamente 999.00. */
const T_REAL_ACC7 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real7.txt'), 'utf8');

/* OCTAVO ticket: el IMPORTE ilegible del todo.

       100175537 1 1013,200 SOI |

   Donde el papel dice `$1,013.20`, el OCR leyo `SOI`. Exigiendo el importe se
   perdia la linea entera, y con ella el sku y el precio, que estaban BIEN
   leidos. Ahora es opcional y lo rellena el `Total`, que en este ticket si se
   leyo. */
const T_REAL_REP8 = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real8.txt'), 'utf8');

/* El guardarrail del importe opcional: sin importe, el precio tiene que llevar
   decimales. Si no, la linea del PIE del ticket —presente en todos— pasaria por
   articulo: sku 1217, cantidad 2, precio 23. */
const T_SIN_IMPORTE_NI_DECIMAL = T_REAL_REP8
  .replace('100175537 1 1013,200 SOI |', '100175537 1 1013 SOI |');

/* NOVENO ticket: MIXTO de verdad. Una mica de $149 y una reparacion de
   $1,145.47 en el mismo papel:

       000043739 | 149,000 $149.00 |
       100175545 1 1145,470 $1,145.47 |

   La deteccion hacia lo correcto —decir que lleva las dos cosas y no decidir—
   pero `accExtraer` cogia SIEMPRE la linea de reparacion primero. Con el panel
   en Accesorio, eso proponia el producto del accesorio con el importe de la
   reparacion, y encima con un "la cuenta del ticket cuadra": cuadraba, pero de
   la linea que no era. Guardado asi quedaba una mica a mil ciento cuarenta y
   cinco pesos en el reporte de comisiones. */
const T_REAL_MIXTO = fs.readFileSync(
  path.join(__dirname, 'ocr_ticket_real9.txt'), 'utf8');

/* Y el guardarrail de eso: el MISMO ticket con una segunda linea de articulo.
   Con dos, un sku irreconocible ya no se puede resolver —habria que acertar
   cual es— y capturar el precio del otro articulo es peor que dejarlo vacio. */
const T_SKU_ROTO_Y_DOS = T_REAL_ACC6
  .replace('naci! SERIE / SERVICIO: MICATRANSPARENTE',
           '000043739 1 299.000 $299.00 1\nnaci! SERIE / SERVICIO: MICATRANSPARENTE');

/* El guardarrail del total: MISMO ticket pero con dos articulos. Aqui el total
   no dice nada del accesorio —un ticket de ocho articulos por $16,962.50
   llevaba un kit de $169— y corregir con el guardaria el total como precio del
   kit. En el reporte de comisiones eso no es un aviso, es dinero. */
const T_DOS_ARTICULOS = T_REAL_ACC4
  .replace('Recuento de artículos vendidos = 1', 'Recuento de artículos vendidos = 2')
  .replace('IMEI / SERIE / SERVICIO: CARGA TOONTS',
           'IMEI / SERIE / SERVICIO: CARGA TOONTS\n000043739 1 149.000 $149.00 1');

const T_REAL_ACC = [
  'Articulo    Cantidad    Precio     Importe',
  'MICA HR',
  '000043739        1      149.000    $149.00  I',
  'IMEI / SERIE / SERVICIO: 43739-MICAHR',
  'Atendido por:GARCIA SOTO,ANA'
].join('\n');

const T_MIX = [
  'Articulo    Cantidad    Precio     Importe',
  'MICA HR',
  '000043739        1      149.000    $149.00  I',
  'REP FUERA DE GARANTIA HW 2',
  '100175545        1      1124.390   $1,124.39  I'
].join('\n');

const T_NADA = 'ATENDIDO POR ARTURO\nTOTAL 149.00';

const CASOS = [
  ['ticket REAL de reparacion',     queEs,         T_REAL_REP,  'rep', true ],
  /* Segunda foto: el sku con un digito mal leido. Con comparacion exacta esto
     no reconocia la reparacion, y la venta se habria capturado como accesorio
     — o sea, al Excel de comisiones. */
  ['segunda foto, sku con un digito mal', queEs,   T_REAL_REP2, 'rep', true ],
  /* Tercer ticket: la cantidad se fue a la linea de arriba. Sin cantidad en la
     linea, el patron no encontraba el articulo y no habia ni sku ni precio. */
  ['tercer ticket, sin cantidad en la linea', queEs, T_REAL_REP3, 'rep', true ],
  ['ticket REAL de accesorio',      queEs,         T_REAL_ACC,  'acc', false],
  ['cuarto ticket, accesorio real', queEs,         T_REAL_ACC4, 'acc', false],
  ['quinto: sku de accesorio con un digito mal', queEs, T_REAL_ACC5, 'acc', false],
  ['sexto: la linea partida en dos',  queEs,         T_REAL_ACC6, 'acc', false],
  ['septimo: precio mal leido, sin Total', queEs,   T_REAL_ACC7, 'acc', false],
  ['octavo: importe ilegible',       queEs,         T_REAL_REP8, 'rep', true ],
  ['ticket con las DOS cosas',      queEs,         T_MIX,      null,  true ],
  ['sin lineas de articulo',        queEs,         T_NADA,     null,  false],
  ['codigos sin configurar',        sinConfigurar, T_REAL_REP, null,  false],
  /* Configurado a medias: el sku que falta se lee como ACCESORIO y esa
     reparacion acabaria en el Excel de comisiones. No es un fallo del codigo
     —hace lo que le dijeron— pero deja escrito, y comprobado, por que la lista
     lleva los dos y por que quitar uno no es inofensivo. */
  /* El catalogo guarda `000043739` y el ticket imprime `43739`; si alguien
     configura el sku de reparacion con ceros delante tiene que dar igual. Sin
     el recorte de ceros esto se leeria como accesorio y acabaria en el Excel. */
  ['sku configurado con ceros',     conCeros,      T_REAL_REP, 'rep', true ],
  ['solo un sku configurado',       soloUno,       T_REAL_REP, 'acc', false],
];


const fallos = [];
for(const [titulo, fn, texto, espera, debeDecir] of CASOS){
  let r;
  try{ r = fn(texto); }
  catch(e){ fallos.push(titulo + ': revienta -> ' + ((e && e.message) || e)); continue; }

  if(r.tipo !== espera){
    fallos.push(titulo + ': decidio "' + r.tipo + '" y tenia que ser "' + espera + '"' +
      (espera === null
        ? ' — decidir aqui manda la venta a una tabla sin poder saber si es la buena'
        : ''));
  }
  if(debeDecir && !r.porque){
    fallos.push(titulo + ': no explica por que. Sin motivo, el asesor no sabe si ' +
                'mirarlo o fiarse');
  }
}

/* ── Y los NUMEROS de la reparacion ──────────────────────────────────────
   `accExtraer` buscaba literalmente la linea del 43739, asi que en una
   reparacion no encontraba nada y devolvia cantidad, precio e importe VACIOS:
   el asesor tenia que teclear el importe a mano sin que nada dijera por que.
   Se vio capturando la primera reparacion de verdad, el 24-ago. */
const numeros = [
  ['reparacion', queEs.extraer(T_REAL_REP), 1124.39, '33671', '23/8/26'],
  /* Segunda foto: el precio venia sin el punto (`1124390`). Se corrige contra el
     importe, que se lee aparte y con otro formato. Sin eso, el precio salia mil
     veces mas grande y la cuenta del ticket no cerraba nunca. */
  ['segunda foto', queEs.extraer(T_REAL_REP2), 1124.39, '33671', ''],
  ['tercer ticket', queEs.extraer(T_REAL_REP3), 877.27, '33673', '23/8/26'],
  /* El importe venia mal leido ($993.00) y lo desempata el Total del ticket,
     que solo se usa porque hay UN articulo. */
  ['cuarto ticket', queEs.extraer(T_REAL_ACC4), 999, '33675', ''],
  /* Importe con coma decimal (`$999,00`) y sku con un digito mal leido. */
  ['quinto ticket', queEs.extraer(T_REAL_ACC5), 999, '33675', '23/8/26'],
  /* Linea partida y sku irreconocible: se usa porque es la unica del ticket. */
  ['sexto ticket', queEs.extraer(T_REAL_ACC6), 149, '33677', '23/8/26'],
  /* Sin `Total` legible: lo reconstruye la linea del IVA (base + impuesto). */
  ['septimo ticket', queEs.extraer(T_REAL_ACC7), 999, '33679', '23/8/26'],
  /* Importe ilegible: lo pone el `Total`, que aqui si se leyo. */
  ['octavo ticket', queEs.extraer(T_REAL_REP8), 1013.20, '33685', ''],
  ['accesorio',  queEs.extraer(T_REAL_ACC),  149,    '',      ''],
];
for(const [que, r, importe, ticket, fecha] of numeros){
  if(r.importe == null){
    fallos.push(que + ': no leyo el importe de la linea del articulo — el asesor ' +
                'tendria que teclearlo a mano sin saber por que');
  }else if(Math.abs(r.importe - importe) > 0.01){
    fallos.push(que + ': leyo un importe de ' + r.importe + ' y el ticket dice ' + importe);
  }
  if(!r.cuadra){
    fallos.push(que + ': precio x cantidad no cuadra con el importe (' +
                r.precio + ' x ' + r.cant + ' vs ' + r.importe + ')');
  }
  if(ticket && r.ticket !== ticket) fallos.push(que + ': leyo el ticket "' + r.ticket + '" y es ' + ticket);
  if(fecha && r.fecha !== fecha)   fallos.push(que + ': leyo la fecha "' + r.fecha + '" y es ' + fecha);
}

/* ── La fecha aguanta que el OCR estropee el ancla ──────────────────────
   `accExtraer` saca ticket y fecha de la linea del pie —`1217 2 23/8/26 11:44
   AM 33671`—, y basta que lea mal un digito del 1217 para perder la fecha
   entera. El ticket ya tenia respaldo; la fecha no, y se quedaba vacia: la
   venta se guardaba con la de HOY, que en un corte mensual mueve de mes un
   ticket de fin de mes. */
const T_ANCLA_ROTA = T_REAL_REP.replace('1217 2 23/8/26', 'T2I7 2 23/8/26');
const rota = queEs.extraer(T_ANCLA_ROTA);
if(rota.fecha !== '23/8/26'){
  fallos.push('ancla rota: perdio la fecha ("' + rota.fecha + '") porque el OCR ' +
              'estropeo el 1217 del pie. La venta se guardaria con la fecha de hoy');
}

/* ── Y QUIEN ATENDIO se lee tambien en una reparacion ───────────────────
   «Lo atendio» es del TICKET desde v207, pero el codigo que lo rellena se
   quedo en la parte del accesorio: en una reparacion se salia antes de llegar
   y el campo no se rellenaba nunca, con el nombre impreso en el papel. */
const vend = queEs.extraer(T_REAL_REP).vend;
if(!vend || vend.toUpperCase().indexOf('GARCIA') < 0){
  fallos.push('no leyo quien atendio del ticket de reparacion (leyo "' + vend + '")');
}
{
  const orden = html.indexOf("if(_accTipo === 'rep'){");
  const dondeVend = html.indexOf('_accVendCasado = r.vend ?');
  if(dondeVend < 0 || dondeVend > orden){
    fallos.push('el vendedor se rellena DESPUES del corte de reparacion: en una ' +
                'reparacion no llega a ejecutarse y el campo se queda vacio');
  }
}

/* ── El total NO se usa cuando hay varios articulos ─────────────────────
   Es el guardarrail que evita guardar el total del ticket como precio de una
   linea. Con dos articulos, el importe mal leido tiene que quedarse mal leido y
   el aviso decir que no cuadra: mejor mandar a revisar que inventar un precio. */
const dos = queEs.extraer(T_DOS_ARTICULOS);
if(dos.cuadra || dos.importe === 999){
  fallos.push('con DOS articulos uso el Total del ticket para corregir (importe ' +
              dos.importe + '). El total no dice nada de una linea cuando hay varias');
}

/* ── La coma: unas veces es de miles y otras decimal ────────────────────
   El importe se imprime `$1,124.39` pero el OCR lo devuelve a veces `$999,00`.
   Borrar las comas sin mirar convertia eso en 99900. */
{
  const caja = { accNum: null };
  const i = html.indexOf('function accNum(x){');
  let j = html.indexOf('{', i), hondo = 0, k = j;
  for(; k < html.length; k++){
    if(html[k] === '{') hondo++;
    else if(html[k] === '}'){ hondo--; if(!hondo) break; }
  }
  const accNum = vm.runInNewContext(html.slice(i, k + 1) + '; accNum', {});
  for(const [txt, vale] of [['1,124.39', 1124.39], ['999,00', 999],
                            ['961,71', 961.71], ['16,962.50', 16962.50],
                            ['877.27', 877.27]]){
    const leido = accNum(txt);
    if(Math.abs(leido - vale) > 0.001){
      fallos.push('accNum("' + txt + '") = ' + leido + ' y vale ' + vale);
    }
  }
}

/* ── Un sku irreconocible NO se resuelve si hay varias lineas ───────────
   Con una sola linea de articulo no hay nada que elegir; con dos, acertar cual
   es seria adivinar, y capturar el precio del articulo equivocado es peor que
   dejar el campo vacio y que lo escriba el asesor. */
const roto2 = queEs.extraer(T_SKU_ROTO_Y_DOS);
if(roto2.importe === 149){
  fallos.push('con el sku irreconocible Y dos lineas, eligio una igual (importe ' +
              roto2.importe + '). Con varias no se puede saber cual era');
}

/* ── Sin importe, un precio SIN decimales no vale ───────────────────────
   Es lo que impide que la linea del pie del ticket pase por articulo ahora que
   el importe es opcional. */
const flojo = queEs.extraer(T_SIN_IMPORTE_NI_DECIMAL);
if(flojo.precio === 1013 || (flojo.precio != null && flojo.precio < 100)){
  fallos.push('sin importe acepto un precio sin decimales (' + flojo.precio +
              '): asi la linea del pie del ticket pasa por articulo');
}

/* ── Ticket MIXTO: cada tipo trae los numeros de SU linea ───────────────
   Es el fallo mas caro de todos los vistos, porque no da error ni aviso: los
   dos numeros existen, cuadran, y estan en el campo equivocado. */
{
  const lineas = queEs(T_REAL_MIXTO);
  if(lineas.tipo !== null){
    fallos.push('mixto: decidio "' + lineas.tipo + '" en un ticket que lleva ' +
                'accesorio Y reparacion. Ahi hay que preguntar');
  }
  const acc = queEs.extraer(T_REAL_MIXTO, 'acc');
  const rep = queEs.extraer(T_REAL_MIXTO, 'rep');
  if(Math.abs((acc.importe || 0) - 149) > 0.01){
    fallos.push('mixto/accesorio: importe ' + acc.importe + ' y la mica vale 149. ' +
                'Se esta cogiendo la linea de la reparacion');
  }
  if(Math.abs((rep.importe || 0) - 1145.47) > 0.01){
    fallos.push('mixto/reparacion: importe ' + rep.importe + ' y la reparacion vale 1145.47');
  }
}

/* ── Con el numero de OTRA tienda, la fecha se salva por el respaldo ────
   `ACC_RE_PIE` se arma con el numero de tienda de la sesion, asi que el pie del
   ticket —«1217 2 23/8/26 11:44 AM 33671»— no casa si la sesion dice 9999. Es
   el caso normal en una copia que usan varias tiendas, y tambien lo que pasa
   cuando el OCR lee mal un digito de ese numero.

   Lo que se comprueba es que ahi entre el RESPALDO. Sin el, la fecha se queda
   vacia y la venta se guarda con la de HOY: en un corte mensual, un ticket de
   fin de mes se contabiliza en el mes siguiente y esa comision se paga en el
   periodo equivocado. */
{
  const otra = motor(REP_A + ',' + REP_B, '9999');
  const r = otra.extraer(T_REAL_REP, 'rep');
  if(r.fecha !== '23/8/26'){
    fallos.push('numero de tienda distinto: perdio la fecha ("' + r.fecha + '"). ' +
                'La venta se guardaria con la de hoy');
  }
  if(!r.importe || Math.abs(r.importe - 1124.39) > 0.01){
    fallos.push('numero de tienda distinto: perdio el importe (' + r.importe + '). ' +
                'La linea del articulo no depende del pie y no deberia caerse con el');
  }
}

if(fallos.length){
  console.log('mrfix-detecta: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('mrfix-detecta: ' + CASOS.length + ' tickets, decide solo cuando el papel no deja dudas');
