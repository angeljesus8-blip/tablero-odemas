/* ============================================================
   Códigos de artículo de accesorios — la regla, en un solo sitio
   ============================================================
   20-ago-2026.

   Dos pantallas usan esto y tienen que estar de acuerdo:

     · captura_series.html — ADIVINA el producto a partir del código que el OCR
       leyó del ticket.
     · admin.html — AVISA al gerente cuando el código que está escribiendo va a
       empatar con otro que ya existe.

   Si fueran dos copias, el aviso podría dar por bueno un código que la
   adivinanza va a empatar. Nadie lo notaría al guardar: se vería meses después,
   como un producto que «dejó de proponerse solo» sin motivo aparente.
   ============================================================ */

/* Las confusiones del OCR en matriz de puntos, aplanadas.

   Medido en piso: `CARGA100WTS` se leyó `CARGATOONTS 2 77`. O sea 1→T, 0→O,
   W→N. Con `CARGA` coincidiendo pero `100W` no, empataba con CARGADOR 66W y no
   proponía nada — correcto pero inútil.

   La clave es aplicar el mismo mapa a LOS DOS lados: así las confusiones se
   cancelan en vez de tener que acertarlas. `CARGA100W` y `CARGATOONTS` acaban
   los dos en `CAR6A100W…` y el prefijo común pasa de 5 a 9.

   Se aplanan solo los pares que de verdad se confunden en esta impresora. Meter
   más no es más listo: dos artículos distintos podrían acabar iguales, y ahí la
   propuesta sería peor que no proponer. */
var ACC_OCR = { O:'0', D:'0', Q:'0', I:'1', L:'1', T:'1', '|':'1', ']':'1',
                Z:'2', S:'5', B:'8', G:'6', N:'W', M:'W' };

function accClave(s){
  return String(s || '').toUpperCase().replace(/[^A-Z0-9]/g, '')
           .replace(/^43739/, '')           // el prefijo lo llevan casi todos
           .replace(/[ODQILT|\]ZSBGNM]/g, function(c){ return ACC_OCR[c] || c; });
}

/* Cuántas letras comparten dos códigos DESDE EL PRINCIPIO. */
function accPrefijo(a, b){
  var corto = Math.min(a.length, b.length);
  var i = 0; while(i < corto && a[i] === b[i]) i++;
  return i;
}

/* Por debajo de esto no se propone nada: con cinco letras comunes, CARGADOR
   100W y CARGADOR 66W serían indistinguibles. */
var ACC_MIN_PREFIJO = 6;

/* ¿Este código va a empatar con alguno de la lista?

   Devuelve el producto con el que choca, o null. Lo usan el aviso de Admin y
   —por la misma regla— es lo que hace que la adivinanza calle: dos códigos que
   comparten el prefijo mínimo no se pueden distinguir cuando el ticket trae el
   más corto de los dos.

   `saltarId` es el producto que se está editando: no choca consigo mismo. */
function accChoca(codigo, lista, saltarId){
  var cod = accClave(codigo);
  if(cod.length < 4) return null;
  for(var i = 0; i < lista.length; i++){
    var c = lista[i];
    if(!c || !c.activo || !c.articulo) continue;
    if(saltarId != null && c.id === saltarId) continue;
    if(accPrefijo(accClave(c.articulo), cod) >= ACC_MIN_PREFIJO) return c;
  }
  return null;
}

/* Para que las pruebas puedan cargarlo con require() sin navegador. */
if(typeof module !== 'undefined' && module.exports){
  module.exports = { ACC_OCR: ACC_OCR, accClave: accClave, accPrefijo: accPrefijo,
                     ACC_MIN_PREFIJO: ACC_MIN_PREFIJO, accChoca: accChoca };
}
