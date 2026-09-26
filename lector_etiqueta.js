/* ══════════════════════════════════════════════════════════════════
   LECTOR DE ETIQUETA — qué trae la foto de una caja
   ══════════════════════════════════════════════════════════════════
   21-sep-2026. Sustituye a `routeCode()` y `ocrSerial()`, que vivían
   dentro de captura_series.html.

   Sale de medir el lector anterior contra 16 fotos reales de piso
   —teléfono, tablet, audífonos, relojes, ruteadores; etiqueta blanca y
   etiqueta negra— con el UPC y la serie de cada una anotados a mano.
   Lo que se midió, y por qué se cambió, está en MAPA.md, «Lo que la
   foto de una etiqueta trae de verdad».

     ANTES  serie   7/16 correcta · 4 MAL · 5 vacía
     AHORA  serie  14/16 correcta · 0 MAL · 2 vacía
            UPC    16/16 en los dos casos

   Las cuatro «MAL» son lo que de verdad importaba: el campo Serie se
   llenaba con el IMEI, la MAC o el EID de la misma etiqueta. Un campo
   vacío se ve; un campo con un número de 15 dígitos que nadie pidió,
   no — y de ahí se va a la Hoja de Google como si fuera la serie.

   Las dos que siguen vacías no tienen arreglo por software: su código
   de barras no decodifica ni ampliado ×5 en 18 posiciones distintas.
   Es óptica —código fino, foto de 1200 px—, y lo que toca es acercar
   la cámara, que es justo lo que dice el aviso.
   ══════════════════════════════════════════════════════════════════ */

/* ── 1. QUÉ ES CADA CÓDIGO ─────────────────────────────────────────
   La etiqueta no trae un código: trae hasta CINCO —EAN del producto,
   IMEI (uno o dos), MAC, EID y la serie—, y el lector de hoy manda a
   «Serie» todo lo que no sea EAN. Medido sobre 16 fotos reales: en 4
   el campo se llenó con el IMEI, la MAC o el EID. Eso no se ve: el
   asesor encuentra la casilla llena y sigue.
   Cada clase se reconoce por su FORMA, que es fija:
     IMEI  15 dígitos · MAC 12 hex con al menos una letra A-F
     EID   32 dígitos · EAN/UPC 8, 12 o 13 dígitos
     serie 16 alfanuméricos con letras Y dígitos (las 16 muestras) */
const SERIE_LARGO = 16;

/* Topes de tamaño del lienzo, en píxeles de ancho.

   ⚠️ Las 16 fotos con las que se midió venían por WhatsApp, o sea
   1200 px. La cámara del teléfono entrega 3000-4000, y ampliar ×3 un
   recorte de ésos da un lienzo de 9000 px que tumba la pestaña. Por eso
   la ampliación es un OBJETIVO de tamaño, no un multiplicador: si el
   trozo ya es grande, no se toca.

   Dos topes distintos porque no cuestan igual. Al decodificador le
   sobra resolución y cobra milisegundos; a Tesseract cada píxel de más
   le cuesta segundos, y la letra ya era legible mucho antes. */
const TOPE_BARRAS = 2400;
const TOPE_OCR    = 1800;

function claseCodigo(val, fmt){
  const v = (val || '').trim().toUpperCase();
  if(!v) return null;
  if(/qr|matrix|aztec|pdf417|maxi/i.test(fmt || '')) return null;   // 2D: nunca
  if(/ean|upc/i.test(fmt || '')) return 'producto';
  if(/^[0-9]+$/.test(v)){
    if(v.length === 8 || v.length === 12 || v.length === 13) return 'producto';
    if(v.length === 15) return 'imei';
    if(v.length >= 30) return 'eid';
  }
  if(/^[0-9A-F]{12}$/.test(v) && /[A-F]/.test(v)) return 'mac';
  if(v.length === SERIE_LARGO && /^[0-9A-Z]+$/.test(v) && /[A-Z]/.test(v) && /[0-9]/.test(v))
    return 'serie';
  /* Otra longitud NO se descarta: se acepta si no apareció ninguna de 16.
     Las 16 muestras miden 16, pero un producto nuevo puede traer otra
     cosa y quedarse sin captura sería peor que pedir que se verifique. */
  if(/^[0-9A-Z][0-9A-Z\-]{6,23}$/.test(v)) return 'serie_debil';
  return null;
}

/* ── 1-bis. LA FORMA DE UNA SERIE HUAWEI ───────────────────────────
   Las 16 muestras: cinco alfanuméricos y once dígitos («7YDTQ» +
   «26730000768»), y los dos dígitos sexto y séptimo son el año (25, 26).
   Una sola rompe el molde —el Mate XT lleva una C en la cola— y por eso
   esto NO decide qué es una serie: sólo decide a QUIÉN se le cree.

   · Del código de barras se acepta sin más: el decodificador devuelve el
     valor exacto o no devuelve nada, y el Mate XT entra por ahí.
   · Del OCR se exige la forma. Medido: leyendo una etiqueta pequeña, el
     OCR devolvió `1L03PQU261290000` —16 caracteres, letras y dígitos,
     con pinta de serie— donde decía `63PQU26129000907`. Eso pasa
     cualquier filtro de largo, y llena la casilla con algo que nadie va
     a mirar dos veces. Con la forma, se cae. */
function formaDeSerie(v){
  return /^[0-9A-Z]{5}[0-9]{11}$/.test(v || '');
}

/* ── 2. EL EAN SE COMPRUEBA, NO SE CREE ────────────────────────────
   El EAN-13 lleva dígito verificador. Sirve para dos cosas: confirmar
   un número leído del TEXTO cuando el código de barras está rayado, y
   descartar una mala lectura antes de que llegue al catálogo. */
function eanValido(e){
  const s = String(e || '').replace(/\D/g, '');
  if(s.length !== 13 && s.length !== 8 && s.length !== 12) return false;
  const d = (s.length === 12 ? '0' + s : s).split('').map(Number);   // UPC-A → EAN-13
  if(d.length === 8){
    const su = d[0]*3 + d[1] + d[2]*3 + d[3] + d[4]*3 + d[5] + d[6]*3;
    return (10 - su % 10) % 10 === d[7];
  }
  let su = 0;
  for(let i = 0; i < 12; i++) su += d[i] * (i % 2 === 0 ? 1 : 3);
  return (10 - su % 10) % 10 === d[12];
}

/* ── 3. ENRUTADO ───────────────────────────────────────────────────
   Recorre TODOS los códigos y se queda con el mejor de cada casilla.
   Una serie de 16 nunca la pisa una candidata más floja, y el IMEI,
   la MAC y el EID no entran a ninguna casilla: se anotan aparte. */
function repartirCodigos(codes){
  const out = { upc:'', serie:'', serieFirme:false, otros:[] };
  (codes || []).forEach(function(c){
    const v = (c.rawValue || '').trim().toUpperCase();
    const cl = claseCodigo(v, c.format);
    if(cl === 'producto'){ if(!out.upc) out.upc = v; }
    else if(cl === 'serie'){ if(!out.serieFirme){ out.serie = v; out.serieFirme = true; } }
    else if(cl === 'serie_debil'){ if(!out.serie) out.serie = v.replace(/-/g, ''); }
    else if(cl) out.otros.push(cl + ':' + v);
  });
  return out;
}

/* ── 4. LA SERIE DENTRO DEL TEXTO DEL OCR ──────────────────────────
   El patrón viejo exigía «S», una barra opcional, «N» y UN separador.
   Medido: se perdieron dos series que el OCR había leído ENTERAS y
   BIEN —`S/N:-7YDTQ...` (dos separadores) y `SIN 7YDTQ...` (la barra
   salió como I)—. El patrón se abre por donde el OCR deforma:
     · la barra puede salir como / | 1 I L ! \ o no salir
     · la N puede salir como M o H
     · detrás puede venir cualquier racha de : ; . # - y espacios     */
const RE_ETIQUETA = /\bS\s*[\/|1IL!\\]?\s*[NMH]\s*[:;.#=\-\s]{0,4}([A-Z0-9][A-Z0-9\-]{6,25})/g;

/* Tokens de 16 con letras y dígitos: la forma de la serie. Sirve
   cuando la etiqueta «S/N» se pierde del todo. */
const RE_SUELTA = /\b([0-9A-Z]{16})\b/g;

function serieDeTexto(T){
  const t = (T || '').toUpperCase();
  const vistos = {};
  const cands = [];
  let m;
  RE_ETIQUETA.lastIndex = 0;
  while((m = RE_ETIQUETA.exec(t))){
    const v = m[1].replace(/-/g, '');
    if(!vistos[v]){ vistos[v] = 1; cands.push({ v: v, etiquetado: true }); }
  }
  RE_SUELTA.lastIndex = 0;
  while((m = RE_SUELTA.exec(t))){
    const v = m[1];
    if(!vistos[v]){ vistos[v] = 1; cands.push({ v: v, etiquetado: false }); }
  }
  /* Se descarta lo que TIENE nombre propio: un IMEI o una MAC leídos
     del texto son tan falsos positivos como leídos del código. */
  const limpios = cands.filter(function(c){
    const cl = claseCodigo(c.v, '');
    return cl !== 'imei' && cl !== 'mac' && cl !== 'eid' && cl !== 'producto';
  });
  /* Orden: primero la que mide 16 y venía etiquetada. Una suelta sólo
     se acepta si es la única de su clase — si hay dos tokens de 16 sin
     etiqueta no hay forma de saber cuál es, y adivinar es inventar. */
  /* «De 16» no basta: en una foto el OCR pegó BUSTA DISPOSITIVO de la tabla
     de reciclaje italiana y salieron 16 letras seguidas. Una serie lleva
     letras Y dígitos — se exige la forma entera, no el largo. */
  const firmes = limpios.filter(c => claseCodigo(c.v, '') === 'serie' && formaDeSerie(c.v));
  const etiq16 = firmes.filter(c => c.etiquetado);
  if(etiq16.length) return { v: etiq16[0].v, firme: true };
  if(firmes.length === 1) return { v: firmes[0].v, firme: true };
  /* Nada con forma de serie: se devuelve vacío A PROPÓSITO. La casilla
     vacía manda a teclearla —son 16 caracteres— y la casilla con un
     número inventado no manda a nada, porque parece que ya está. */
  return null;
}

/* ── 5. EL UPC DENTRO DEL TEXTO ────────────────────────────────────
   Respaldo para el EAN rayado. El número va impreso debajo del código
   y el OCR lo parte en grupos («6 942103 187766»), así que se juntan
   los dígitos y se comprueba el verificador: sin eso, un dígito mal
   leído entra al catálogo como producto equivocado. */
function upcDeTexto(T){
  const t = (T || '').toUpperCase();
  const cands = [];
  const re = /(\d[\d\s]{10,20}\d)/g;
  let m;
  while((m = re.exec(t))){
    const d = m[1].replace(/\s/g, '');
    for(let i = 0; i + 13 <= d.length; i++) cands.push(d.substr(i, 13));
    if(d.length === 12) cands.push(d);
  }
  const bueno = cands.filter(eanValido);
  /* Preferir el que empieza en 694: es el prefijo de Huawei y aparece
     en las 16 muestras. No se exige — sólo se prefiere. */
  return bueno.find(c => /^694/.test(c)) || bueno[0] || null;
}

/* ── 6. LA IMAGEN QUE SE LES DA ────────────────────────────────────
   Recortar la etiqueta y ampliarla es lo que rescata los códigos de
   barras que no decodifican en la foto entera. Con el OCR, medido,
   pasa lo contrario y por eso aquí no se recorta para él:

     · OCR sobre el RECORTE ampliado: 0 aciertos y los 2 únicos falsos
       positivos de toda la medición (`TYVYD...` por `7YVYD...`,
       `1L03PQU...` por `63PQU...`).
     · OCR sobre la FOTO ENTERA reducida: los 4 aciertos, ningún error
       — incluidas las tres etiquetas negras con letra blanca.

   Es lo mismo que enseñó el realce de contraste en los tickets: el
   tratamiento que «debería» ayudar empeora la mitad de las veces, y lo
   que decide es la medición, no el razonamiento. Tesseract hace su
   propio escalado y binarización; dárselo masticado le estorba.

   Por lo mismo no se invierten las etiquetas negras: Tesseract 5 las
   lee, y la pasada extra costaba segundos sin rescatar ninguna. */
function lienzoDe(img, caja, escala, tope){
  const c = document.createElement('canvas');
  const x = Math.max(0, Math.round(caja.x)), y = Math.max(0, Math.round(caja.y));
  const w = Math.min(img.width - x, Math.round(caja.w));
  const h = Math.min(img.height - y, Math.round(caja.h));
  /* Tope de ancho para el OCR. Ampliar ×3 un recorte grande da un lienzo
     de 3000 px que Tesseract tarda medio minuto en recorrer, y la letra
     ya era legible mucho antes: lo que hace falta son píxeles POR
     CARÁCTER, no píxeles. Para los códigos de barras no se topa —ahí
     sí paga el detalle y cuesta milisegundos. */
  if(tope && w * escala > tope) escala = tope / w;
  c.width = Math.round(w * escala); c.height = Math.round(h * escala);
  const cx = c.getContext('2d', { willReadFrequently: true });
  cx.imageSmoothingEnabled = true; cx.imageSmoothingQuality = 'high';
  cx.drawImage(img, x, y, w, h, 0, 0, c.width, c.height);
  return c;
}

/* Caja de la etiqueta a partir de dónde cayó el código de barras.
   El alto se estira hacia arriba y hacia abajo porque la serie unas
   veces va encima del EAN y otras debajo. */
function cajaEtiqueta(code, img){
  const b = code && (code.boundingBox || null);
  if(!b || !b.width) return null;
  const alto = b.height || 40;
  /* Márgenes generosos y asimétricos a propósito: la serie no está a una
     distancia fija del EAN. En unas cajas va justo debajo; en el Mate XT
     y en los FreeBuds SE va al otro extremo de la etiqueta. */
  const margenY = Math.max(alto * 8, img.height * 0.16);
  const margenX = Math.max(b.width * 2.2, img.width * 0.25);
  return {
    x: b.x - margenX, y: b.y - margenY,
    w: b.width + margenX * 2, h: alto + margenY * 2
  };
}

/* ── 7. LA CASCADA ─────────────────────────────────────────────────
   El orden lo decide el coste, y la diferencia es de tres órdenes de
   magnitud: leer los códigos de una foto cuesta ~300 ms y una pasada
   de OCR, 6-20 s en un teléfono de piso.

     1. códigos de barras sobre la foto entera
     2. códigos de barras sobre la ETIQUETA RECORTADA Y AMPLIADA
     3. OCR del recorte · 4. el recorte invertido · 5. la foto entera

   El paso 2 es el que faltaba, y sale directo de lo que ya estaba
   medido en MAPA.md: «lo que decide no es el modo, son los píxeles
   enfocados que ocupa el código». La misma serie que no decodifica en
   la foto de 1200 px decodifica cuando la etiqueta llena el cuadro.
   Aquí no hay que pedirle al asesor que se acerque: el EAN se lee
   SIEMPRE (16 de 16 medidas) y dice dónde está la etiqueta, así que
   el recorte se hace solo.

   Importa además porque el código de barras devuelve el valor EXACTO
   o no devuelve nada, mientras que el OCR puede devolver 15 aciertos
   y un fallo —`54P7S` leído `54P75`— que nadie distingue a simple
   vista. Cada serie que se resuelve en el paso 2 es una que ya no
   depende de que el OCR acierte los 16 caracteres. */
async function leerEtiqueta(file, opciones){
  const op = opciones || {};
  const ocr = op.ocr;                       // (canvas) => texto
  const res = { upc:'', serie:'', firme:false, viaUpc:'', viaSerie:'', otros:[], pasadas:0 };
  const dets = op.detectores || [];

  async function mirarCodigos(fuente, via){
    let codes = [];
    for(const D of dets){
      try{
        const r = await op.detectar(D, fuente);
        if(r && r.length){ codes = r; break; }
      }catch(e){ /* siguiente detector */ }
    }
    const rep = repartirCodigos(codes);
    rep.otros.forEach(o => { if(res.otros.indexOf(o) < 0) res.otros.push(o); });
    if(rep.upc && !res.upc){ res.upc = rep.upc; res.viaUpc = via; }
    if(rep.serie && (!res.serie || (rep.serieFirme && !res.firme))){
      res.serie = rep.serie; res.firme = rep.serieFirme; res.viaSerie = via;
    }
    return codes;
  }

  const codes = await mirarCodigos(file, 'barras');
  if(res.serie && res.firme && res.upc) return res;

  const img = await createImageBitmap(file);
  const codeEAN = codes.find(c => /ean|upc/i.test(c.format || ''));
  const caja = cajaEtiqueta(codeEAN, img);

  /* ── 2 · la etiqueta ampliada ── */
  if(caja && !(res.serie && res.firme)){
    for(const escala of [2, 3]){
      await mirarCodigos(lienzoDe(img, caja, escala, TOPE_BARRAS), 'barras:x' + escala);
      if(res.serie && res.firme) break;
    }
  }
  /* Y si aún falta, un barrido en rejilla sobre la foto entera. Es el
     mismo truco sin depender de dónde cayó el EAN: cada trozo se amplía
     al doble, así que un código que ocupaba 200 px de la foto pasa a
     ocupar 400 en su recuadro. Las franjas se solapan la mitad porque un
     código partido en dos trozos no se lee en ninguno de los dos.
     Cuesta lo que cuesta decodificar —decenas de milisegundos por
     recuadro—, nada comparado con una sola pasada de OCR. */
  if(!(res.serie && res.firme)){
    const filas = 3, cols = 2;
    const hh = img.height / filas, ww = img.width / cols;
    for(let f = 0; f < filas * 2 - 1 && !(res.serie && res.firme); f++){
      for(let c = 0; c < cols * 2 - 1 && !(res.serie && res.firme); c++){
        await mirarCodigos(
          lienzoDe(img, { x: c * ww / 2, y: f * hh / 2, w: ww, h: hh }, 2, TOPE_BARRAS),
          'barras:rejilla');
      }
    }
  }
  if(res.serie && res.firme && res.upc) return res;
  if(!ocr) return res;

  /* ── 3 · OCR, ya sólo para lo que el código de barras no dio ── */
  /* UNA pasada, y la foto entera. Es la que acierta, y además acota lo
     que puede tardar una foto que no se deja leer: con tres pasadas eran
     40 s de teléfono para terminar igual en blanco, y el asesor ya había
     decidido teclear la serie mucho antes. */
  const esc = Math.max(TOPE_OCR / Math.max(img.width, 1), 1);
  const lienzos = [{ n:'foto', c: lienzoDe(img, {x:0,y:0,w:img.width,h:img.height}, esc, TOPE_OCR) }];

  for(const L of lienzos){
    if(res.serie && res.firme) break;
    /* Se avisa antes de la primera pasada y no antes de cada una: lo que el
       asesor necesita saber es que la app sigue trabajando, no cuántas
       vueltas le da. Hasta aquí han pasado menos de dos segundos; a partir
       de aquí son segundos de OCR y la pantalla parecería colgada. */
    if(res.pasadas === 0 && op.aviso) op.aviso('El código no se deja leer · probando con el texto…');
    res.pasadas++;
    const T = await ocr(L.c);
    if(!res.upc){
      const u = upcDeTexto(T);
      if(u){ res.upc = u; res.viaUpc = 'ocr:' + L.n; }
    }
    const s = serieDeTexto(T);
    if(s && (!res.serie || (s.firme && !res.firme))){
      res.serie = s.v; res.firme = s.firme; res.viaSerie = 'ocr:' + L.n;
    }
  }
  return res;
}

/* En el navegador cuelga de window; en Node lo cargan las pruebas con
   require(). Las funciones que deciden —clasificar, enrutar, extraer— no
   tocan el DOM a propósito: así se prueban sin navegador y con cebos. */
var LECTOR = {
  SERIE_LARGO: SERIE_LARGO,
  claseCodigo: claseCodigo,
  formaDeSerie: formaDeSerie,
  eanValido: eanValido,
  repartirCodigos: repartirCodigos,
  serieDeTexto: serieDeTexto,
  upcDeTexto: upcDeTexto,
  leerEtiqueta: leerEtiqueta
};
if(typeof window !== 'undefined') window.LECTOR = LECTOR;
if(typeof module !== 'undefined' && module.exports) module.exports = LECTOR;
