/* ============================================================
   Captura de Series: quién puede empezar a capturar
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe porque esta pantalla dejó tirados a los asesores dos veces
   seguidas (8-ago-2026) y en ninguna de las dos lo vio una prueba: no
   había ninguna. El bloqueo no se ve leyendo el código —depende de qué
   trae la sesión guardada en ESE teléfono— así que hay que ejecutarla con
   cada combinación.

   Cada escenario dice lo que DEBE pasar. Si cambias el comportamiento a
   propósito, cambia aquí lo esperado en el mismo commit.

   Solo se cargan los <script> clásicos: el bloque type="module" (el
   decodificador de códigos de barras) corre aparte en el navegador y su
   `await` de nivel superior no puede mezclarse con estos.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const RUTA = path.join(__dirname, '..', 'captura_series.html');
const html = fs.readFileSync(RUTA, 'utf8');

const { crearEntorno } = require('./dom.js');

/* El entorno vive en `dom.js` desde el 17-ago-2026. Antes esta prueba tenía su
   propio DOM, que devolvía un elemento para CUALQUIER id y llevaba setters a
   medida para el gate. Con el compartido:

     · un id que se pinta por debajo del <script> devuelve null durante la
       carga, como el navegador — así se caza tocar algo que aún no existe
     · `classList` es de verdad, así que "¿se ocultó el gate?" se lee del
       elemento en vez de espiar un `add()` con truco

   El resultado de cada escenario sale ahora de mirar el DOM, no de contadores
   propios. Un `hideGate()` que no se llame se ve igual, y uno que se llame de
   más también. */
function escenario(store, empleado) {
  const ls = {};
  if (store) ls['odemas_store'] = JSON.stringify(store);
  if (empleado) ls['odemas_empleado'] = JSON.stringify(empleado);

  const ent = crearEntorno({ html, ruta:'/t/captura_series.html', ls });
  if (ent.err) return { error: ent.err };

  /* El gate arranca VISIBLE, igual que en el HTML (<div id="gate"> sin la clase
     `hide`). Empezar en "indeterminado" fue lo que dejó pasar el bloqueo del
     8-ago: el código identificaba al asesor y se olvidaba de llamar a
     `hideGate()`, la pantalla se quedaba encima y vacía, y la prueba lo daba por
     bueno porque nadie había tocado el gate. No tocarlo NO es esconderlo. */
  const gateOculto = ent.tiene('gate', 'hide');
  const gateHTML   = ent.htmlDe('gateNames');
  const nombres    = (gateHTML.match(/gate-name/g) || []).length;
  const resultado  = gateOculto ? 'captura' : (nombres ? 'elegir' : 'atascado');

  return { resultado, nombres, vendedor: ent.el('vendLabel').textContent,
           tieneSalida: gateHTML.indexOf('index.html') >= 0 };
}

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal', 'Ana Ramirez solis'];
const conLista = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'t', vendedores:EQUIPO };
const sinLista = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'t', vendedores:[] };
const EMP      = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'asesor' };
const EMP_FUERA= { empno:'9', nombre:'Alguien Que No Vende', puesto:'gerente' };

/* `captura` = entra directo a capturar.  `elegir` = pregunta con la lista.
   `atascado` = el gate sin nombres; solo se admite cuando de verdad no hay
   forma de saber quién es, y aun así tiene que ofrecer salida. */
const CASOS = [
  ['gerente con todo',                    conLista, EMP,       'captura'],
  ['asesor sin la lista pero con sesion', sinLista, EMP,       'captura'],
  ['empleado que no esta en la lista',    conLista, EMP_FUERA, 'captura'],
  ['con lista y sin saber quien entro',   conLista, null,      'elegir'],
  ['sin lista y sin saber quien entro',   sinLista, null,      'atascado'],
  ['sin sesion de tienda',                null,     null,      'atascado'],
];

const fallos = [];
/* ============================================================
   LOS TRES PASOS Y LAS CUATRO PESTAÑAS (21-sep-2026)
   ============================================================
   La pantalla pasó de un formulario de arriba abajo a «una cosa a la vez»:
   escanea → revisa → guarda, con las herramientas en pestañas arriba en vez
   de en una barra abajo.

   Lo que se comprueba aquí es lo que, roto, deja al asesor sin poder capturar
   y NO da ningún error:

     · que el paso 2 aparezca y el 1 se vaya (si los dos se ocultan, la
       pantalla se queda en blanco con el cliente enfrente);
     · que al terminar una venta se vuelva al paso 1, o el siguiente cliente
       se atiende sobre la ficha del anterior;
     · que sigan existiendo los identificadores que las pestañas heredaron de
       la barra de abajo — `btnCsv` y `lockMsg`—, porque el código que abre la
       hoja de ventas los busca por nombre y no se tocó.
   ============================================================ */
{
  const ent = crearEntorno({ html, ruta:'/t/captura_series.html',
    ls: { 'odemas_store': JSON.stringify(conLista),
          'odemas_empleado': JSON.stringify(EMP) } });

  if(ent.err){
    fallos.push('pasos: la pantalla se cae al cargar -> ' + ent.err);
  } else {
    const verPaso = () => ({
      uno: ent.el('paso1').style.display !== 'none',
      dos: ent.el('paso2').style.display !== 'none'
    });

    let v = verPaso();
    if(!v.uno || v.dos) fallos.push('pasos: al abrir no se ve el paso 1 solo');

    ent.correr('irPaso(2)');
    v = verPaso();
    if(v.uno || !v.dos) fallos.push('pasos: irPaso(2) no enseña la ficha');
    if(ent.el('lista').style.display !== 'none'){
      fallos.push('pasos: la lista del día sigue estorbando en el paso 2');
    }

    ent.correr('irPaso(1)');
    v = verPaso();
    if(!v.uno || v.dos) fallos.push('pasos: no se puede volver al paso 1');

    /* Nunca los dos ocultos: sería la pantalla en blanco. */
    for(const n of [1, 2, 3]){
      ent.correr('irPaso(' + n + ')');
      const x = verPaso();
      if(!x.uno && !x.dos) fallos.push('pasos: con irPaso(' + n + ') no se ve NINGÚN paso');
    }
    ent.correr('irPaso(1)');

    /* Los ids que las pestañas heredaron de la barra de abajo. Si alguien
       renombra uno, el botón se queda ahí sin abrir nada y sin dar error.

       Se mira el HTML DE VERDAD y no el DOM de pruebas: `crearEntorno` inventa
       un elemento para cualquier id que se le pida —así imita al navegador
       durante la carga—, así que preguntarle por uno que ya no existe habría
       contestado que sí. Probado con un cebo: renombrar `btnCsv` pasaba
       limpio, y por eso esta comprobación es sobre el texto del archivo. */
    for(const id of ['btnCsv', 'lockMsg', 'btnPhoto', 'btnGal',
                     'btnMano', 'btnVolver1', 'serie', 'sku', 'precio', 'desc', 'btnAdd',
                     'paso1', 'paso2', 'vendSeguros']){
      if(html.indexOf('id="' + id + '"') < 0){
        fallos.push('pasos: ya no existe id="' + id + '", y el código lo busca por nombre');
      }
    }

    /* Y el candado: cuando no hay permiso tiene que OCUPAR el sitio de
       «Ventas», no dejar un hueco (por eso es `flex` y no ''). */
    ent.correr('updateDownloadAccess()');
    const dv = ent.el('lockMsg').style.display;
    if(dv !== 'none' && dv !== 'flex'){
      fallos.push('pasos: el candado se muestra con display "' + dv + '" y el CSS lo tiene en none');
    }
  }
}

for(const [titulo, store, emp, espera] of CASOS){
  const r = escenario(store, emp);
  if(r.error){ fallos.push(titulo + ': la pantalla se cae -> ' + r.error); continue; }
  if(r.resultado !== espera){
    fallos.push(titulo + ': esperaba "' + espera + '" y hace "' + r.resultado + '"');
  }
  // Atascado sin salida es lo que dejo a la gente sin poder trabajar
  if(r.resultado === 'atascado' && !r.tieneSalida){
    fallos.push(titulo + ': el gate se queda sin nombres Y SIN SALIDA');
  }
}

if(fallos.length){
  console.log('captura: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('captura: ' + CASOS.length + ' formas de entrar, todas dejan trabajar o explican por que no');
