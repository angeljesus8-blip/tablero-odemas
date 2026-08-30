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
  if (store) ls['hes_store'] = JSON.stringify(store);
  if (empleado) ls['hes_empleado'] = JSON.stringify(empleado);

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
