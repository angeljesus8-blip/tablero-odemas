/* ============================================================
   El menú: a quién se le vuelve a pedir el número de empleado
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe por el bloqueo del 8 y 9 de agosto de 2026: los asesores no
   podían capturar series porque su sesión, guardada días antes, no traía
   ni quién había entrado ni la lista del equipo. La base devolvía esos
   datos perfectamente; nadie se los estaba pidiendo, porque una sesión
   guardada no se refrescaba nunca.

   Aquí se fija el equilibrio entre las dos formas de fallar:

     · pedir de más  -> el equipo teclea su número cada vez que abre la app
     · pedir de menos-> alguien se queda sin poder trabajar y no se ve por qué

   Si cambias la regla, cambia aquí lo esperado en el mismo commit.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const bloques = html.match(/<script[^>]*>[\s\S]*?<\/script>/g) || [];
const js = bloques
  .filter(b => !/\ssrc=/.test(b.slice(0, b.indexOf('>'))))
  .filter(b => !/type="module"/.test(b.slice(0, b.indexOf('>'))))
  .map(b => b.slice(b.indexOf('>') + 1, b.lastIndexOf('</script>')))
  .join('\n;\n');

/* Del archivo entero solo interesa esta función, y montar el resto del menú
   —Supabase, el DOM, el teclado del PIN— para llegar a ella sería construir un
   navegador. Se extrae y se ejecuta sola. */
const trozo = js.match(/function queFaltaEnLaSesion\([\s\S]*?\n\}/);
if (!trozo) {
  console.log('menú: no encontré queFaltaEnLaSesion() en index.html — ¿se renombró?');
  console.log('   · es la que decide si hay que volver a pedir el número de empleado');
  process.exit(1);
}
const caja = { console };
vm.createContext(caja);
vm.runInContext(trozo[0] + '\n;globalThis.__f = queFaltaEnLaSesion;', caja, { filename:'index-trozo.js' });
const queFalta = caja.__f;

const EQUIPO = ['Jorge Medina Rejón', 'Luis de Jesús Ortega Vidal',
                'Elena Navarro Gálvez', 'María Fuentes Bravo', 'Ana Ramírez Solís'];
const conLista = { store_id:'1217', vendedores:EQUIPO };
const sinLista = { store_id:'1217', vendedores:[] };
const EMP = JSON.stringify({ empno:'1000004', nombre:'Jorge Medina Rejón' });

/* Se comprueba QUÉ dice que falta, no solo si falta algo: ese texto es lo que
   se le enseña al equipo y lo que llega en la foto cuando algo se tuerce. Una
   cadena vacía significa "la sesión está completa, déjale entrar". */
//        qué pasa                                  cfg        rol        empleado          qué debe faltar
const CASOS = [
  ['asesor con todo al día',                        conLista, 'asesor',   EMP,              ''],
  ['asesor sin saber quién entró (el bloqueo)',     conLista, 'asesor',   null,             'quién entró'],
  ['asesor sin la lista del equipo',                sinLista, 'asesor',   EMP,              'la lista del equipo'],
  ['asesor sin ninguna de las dos cosas',           sinLista, 'asesor',   null,             'quién entró y la lista del equipo'],
  ['asesor con el empleado guardado a medias',      conLista, 'asesor',   '{"empno":"1"}',  'quién entró'],
  ['asesor con el empleado ilegible',               conLista, 'asesor',   '{roto',          'quién entró'],
  ['gerente: entra con su correo, no se le pide',   sinLista, 'gerente',  null,             ''],
];

const fallos = [];
for (const [titulo, cfg, rol, emp, esperado] of CASOS) {
  let dio;
  try { dio = queFalta(cfg, rol, emp); }
  catch (e) { fallos.push(titulo + ': se cae -> ' + e.message); continue; }
  if (dio !== esperado) {
    fallos.push(titulo + ': esperaba "' + (esperado || '(nada)') + '" y dice "' + (dio || '(nada)') + '"');
  }
}

if (fallos.length) {
  console.log('menú: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('menú: ' + CASOS.length + ' sesiones, se pide el número solo cuando falta algo y se dice qué');
