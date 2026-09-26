/* ============================================================
   Una sesión ajena no entra como gerente, y la pantalla se refresca
   ============================================================
   14-sep-2026. Corre en cada commit desde `verificar.py`.

   Reportado en piso: «yo veo el horario correcto entrando con el correo, pero
   el equipo ve otro». Al recorrerlo salieron DOS agujeros distintos, y ninguno
   daba error por ningún lado.

   1 · `arrancar()` le creía a `localStorage`.
      La tienda salía de una clave que entonces se llamaba `hes_store` a secas, y
      `localStorage` es POR ORIGEN: todas las apps publicadas en el mismo usuario
      de GitHub Pages comparten el mismo almacén, así que esa clave la escribían
      los dos tableros —que ni siquiera usan la misma base—. Con eso, cualquier
      sesión abierta en ese navegador entraba aquí como gerente de la tienda que
      dijera esa clave. Después `cargarConfig` devolvía cuatro `null` —la RLS no
      da error, da CERO FILAS— y la app pintaba un horario salido del motor de
      rotación, con nombres de plantilla, rotulado «● Semana actual». Un horario
      inventado que se lee como el de verdad.

      Desde el 14-sep-2026 cada app lleva su prefijo (`hes1217_` / `odemas_`),
      pero eso solo SEPARA. Dentro de una misma app, quien manda en una tienda lo
      sigue diciendo el servidor, y es lo que prueba este archivo.

   2 · El horario se leía UNA vez y nunca más.
      En el celular, volver a la app restaura la pantalla sin recargarla, así que
      una semana ya publicada seguía viéndose vieja. El gerente, que entra fresco
      desde la computadora, veía lo nuevo: de ahí el «yo lo veo bien y ellos no».

   ⚠️ Lo que sostiene el arreglo del 1 es que la pregunta se le hace al SERVIDOR
   (`admin_de`), no al navegador. Y que responda por los dos caminos —dueña de la
   tienda o ficha activa con admin— es lo que deja al subgerente editando, que es
   lo que se ganó el 4-ago-2026. Por eso el caso del subgerente está aquí: si
   alguien «arregla» esto mirando solo `tiendas.user_id`, esta prueba truena.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const raiz = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(raiz, 'horarios.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

/* Nombres y números inventados: este repo es público. Lo que importa es la
   forma —dos de gestión y dos asesores—, no quién es. */
const EQUIPO = {
  horaApertura: 10, horaCierre: 21,
  gerentes: [
    { key:'G1', nombre:'ANA GERENTE', cargo:'Gerente de Tienda', emp:'900001', descFijo:5 },
    { key:'G2', nombre:'BENI SUBGER', cargo:'Subgerente',        emp:'900002', descFijo:4 }
  ],
  asesores: [
    { key:'A1', nombre:'CARO ASESORA', cargo:'Asesor', emp:'900003', descFijo:3 },
    { key:'A2', nombre:'DANI ASESOR',  cargo:'Asesor', emp:'900004', descFijo:1 }
  ]
};

const HES_STORE = JSON.stringify({ store_id:'1217', nombre:'Angelopolis' });
const SESION    = { user:{ id:'uuid-de-quien-sea', email:'alguien@odemas.com.mx' } };

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

/* Levanta la página con una sesión y un localStorage dados, y corre `arrancar()`
   entero. `manda` es lo que contesta `admin_de` en el servidor. */
async function arrancarCon({ ls, session, manda }){
  const llamadas = [];
  const resp = { equipo: null };          // se rellena tras saber la semana

  const SUPABASE_FALSO = {
    createClient: () => ({
      auth: {
        getSession: async () => ({ data:{ session: session || null } }),
        signInWithPassword: async () => ({ error:{ message:'no' } }),
        signOut: async () => ({})
      },
      /* Todo lo que pase por aquí es `horarios_config` bajo RLS. Devuelve CERO
         FILAS y sin error, que es exactamente lo que hace Supabase cuando la
         política no autoriza — el silencio que hacía inventar el horario. */
      from: () => ({ select(){ return this; }, eq(){ return this; },
                     maybeSingle: async () => ({ data:null, error:null }),
                     upsert: async () => ({ error:null }) }),
      rpc: async (nombre) => {
        llamadas.push(nombre);
        if(nombre === 'admin_de')       return { data: manda === true };
        if(nombre === 'horario_equipo') return { data: resp.equipo };
        return { data:null };
      }
    })
  };

  const ent = crearEntorno({ html, ruta:'/tablero-odemas/horarios.html', ls,
                             extras:{ supabase: SUPABASE_FALSO } });
  if(ent.err) return { error: ent.err };

  /* La semana que la página calculó sola: la clave de `semanas_guardadas`. Los
     turnos salen del motor real, así que el dato de prueba tiene la misma forma
     que el de producción — pero hay que aplicar el equipo ANTES, porque el motor
     lee `EQUIPO` del ámbito del archivo. */
  const semana = ent.correr('_semana');
  ent.correr('aplicarEquipo(' + JSON.stringify(EQUIPO) + ');');
  const dias = ent.correr('generarSemana(_semana, null, null)');
  resp.equipo = { equipo: EQUIPO, historial:{}, excepciones:{},
                  semanas_guardadas: { ['semana_' + semana]: { dias } } };

  try{ await ent.correr('arrancar()'); }
  catch(e){ return { error: (e && e.message) || String(e) }; }

  return { ent, llamadas, semana, resp,
           cuerpo: ent.htmlDe('cuerpo'), movil: ent.htmlDe('vista-movil'),
           puedeEditar: ent.correr('_puedeEditar'),
           empno: ent.correr('_empno'),
           /* `=== ''` y no `!== 'none'`: este DOM no lee el `style=` del HTML, así
              que un elemento que nadie tocó tiene `display` en `undefined` y
              cualquier «distinto de none» daría por visible medio archivo. Lo que
              se comprueba es lo que el código ESCRIBIÓ. */
           sinPermiso: ent.el('sin-permiso').style.display === '',
           login: ent.tiene('overlay-login', 'activo') };
}

(async () => {

/* ── 1 · Sesión que no manda, pero la persona sí se identificó ────────────
   Un asesor que alguna vez creó cuenta con su correo, o un aparato compartido
   donde quedó una sesión abierta. Tiene que ver SU horario, no uno inventado. */
{
  const r = await arrancarCon({
    session: SESION, manda: false,
    ls: { odemas_store: HES_STORE,
          odemas_empleado: JSON.stringify({ empno:'900003', nombre:'CARO ASESORA', puesto:'Asesor' }) }
  });
  ok('1 la página no arrancó', !r.error, r.error);
  if(!r.error){
    ok('1 se le preguntó al servidor si manda', r.llamadas.includes('admin_de'),
       'llamadas: ' + r.llamadas.join(', '));
    ok('1 acabó pidiendo el horario del equipo', r.llamadas.includes('horario_equipo'),
       'llamadas: ' + r.llamadas.join(', '));
    ok('1 NO entró como gerente', r.puedeEditar === false, 'puedeEditar=' + r.puedeEditar);
    ok('1 se le reconoció su número', r.empno === '900003', 'empno=' + r.empno);
    /* Lo que delataba el horario inventado: los nombres de EQUIPO_DEFAULT. Si
       aparecen, es que `aplicarEquipo(null)` volvió a colarse. */
    ok('1 no se pintó la plantilla inventada',
       !/ASESOR 1|SUBGERENTE —/.test(r.cuerpo + r.movil));
    ok('1 ve su propia tarjeta', /CARO ASESORA/.test(r.movil));
  }
}

/* ── 2 · Sesión que no manda y no sabemos quién es ────────────────────────
   El login pelado no sirve: su sesión sigue abierta y volvería a entrar por el
   mismo camino. Se le dice qué pasa y se le ofrece cerrarla. */
{
  const r = await arrancarCon({ session: SESION, manda: false, ls: { odemas_store: HES_STORE } });
  ok('2 la página no arrancó', !r.error, r.error);
  if(!r.error){
    ok('2 sale el aviso de sin permiso', r.sinPermiso === true);
    ok('2 no se pintó ningún horario', (r.cuerpo || '') === '', r.cuerpo.slice(0,80));
    ok('2 dice de qué tienda habla', r.ent.el('sp-tienda').textContent === '1217');
  }
}

/* ── 3 · El subgerente SIGUE editando ─────────────────────────────────────
   `admin_de` dice que sí por ficha activa con admin, no solo por ser la dueña
   de la tienda. Si esto se cambia por una consulta a `tiendas.user_id`, el
   subgerente deja de editar y nadie lo ata a este cambio. */
{
  const r = await arrancarCon({
    session: SESION, manda: true,
    ls: { odemas_store: HES_STORE,
          odemas_empleado: JSON.stringify({ empno:'900002', nombre:'BENI SUBGER', puesto:'Subgerente' }) }
  });
  ok('3 la página no arrancó', !r.error, r.error);
  if(!r.error){
    ok('3 entra con permiso de editar', r.puedeEditar === true, 'puedeEditar=' + r.puedeEditar);
    ok('3 no le sale el aviso de sin permiso', r.sinPermiso === false);
  }
}

/* ── 4 · La pantalla del equipo se vuelve a pedir ─────────────────────────
   Es lo que faltaba el 14-sep: el dato se leía al arrancar y nada lo refrescaba.
   Se comprueba que vuelve a preguntar Y que el pie dice cuándo se leyó — ese pie
   es la única pista de que una pantalla lleva horas abierta. */
{
  const r = await arrancarCon({
    session: null, manda: false,
    ls: { odemas_store: HES_STORE,
          odemas_empleado: JSON.stringify({ empno:'900003', nombre:'CARO ASESORA', puesto:'Asesor' }) }
  });
  ok('4 la página no arrancó', !r.error, r.error);
  if(!r.error){
    const antes = r.llamadas.filter(n => n === 'horario_equipo').length;
    ok('4 el pie dice cuándo se leyó', /Horario leído:/.test(r.ent.el('pie').textContent),
       r.ent.el('pie').textContent);

    // Recién leído: volver a la app no debe machacar la pantalla cada vez.
    await r.ent.correr('refrescarHorarioEquipo()');
    ok('4 no vuelve a pedirlo si acaba de leerlo',
       r.llamadas.filter(n => n === 'horario_equipo').length === antes);

    // Con la pantalla vieja, sí.
    r.ent.correr('_leido.hora = new Date(Date.now() - 3600000);');
    await r.ent.correr('refrescarHorarioEquipo()');
    ok('4 vuelve a pedirlo si la pantalla es vieja',
       r.llamadas.filter(n => n === 'horario_equipo').length === antes + 1,
       'pidió ' + r.llamadas.filter(n => n === 'horario_equipo').length + ' veces');
    ok('4 sigue viéndose su horario', /CARO ASESORA/.test(r.ent.htmlDe('vista-movil')));
  }
}

/* ── 5 · Al gerente NO se le repinta encima ───────────────────────────────
   Puede tener la semana a medio editar sin guardar. `_leido` solo se pone en la
   vista de solo lectura, y el refresco se planta si no está. */
{
  const r = await arrancarCon({
    session: SESION, manda: true, ls: { odemas_store: HES_STORE }
  });
  ok('5 la página no arrancó', !r.error, r.error);
  if(!r.error){
    ok('5 el gerente no queda marcado para refrescar', r.ent.correr('_leido') === null);
    const antes = r.llamadas.filter(n => n === 'horario_equipo').length;
    await r.ent.correr('refrescarHorarioEquipo()');
    ok('5 refrescar no hace nada con el gerente',
       r.llamadas.filter(n => n === 'horario_equipo').length === antes);
  }
}

if(fallos.length){
  console.error('horario_sesion_ajena: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.error('  - ' + f));
  process.exit(1);
}
console.log('horario_sesion_ajena: sesión ajena fuera, pantalla al día (5 casos)');

})();
