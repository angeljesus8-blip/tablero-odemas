/* ============================================================
   Las comisiones son de cada quien, y la pantalla sobrevive al cambio
   ============================================================
   Corre en cada commit desde `verificar.py`.

   El 20-sep-2026 se portó de la 1217 el filtro por persona. Son DOS mitades y
   ninguna sirve sola:

     · `supabase_comisiones_privadas.sql` — la firma de tres argumentos, que
       filtra en el servidor, y la revocación de la de uno, que era la que
       dejaba volcar el sueldo del equipo —de CUALQUIER tienda de la red— con
       la clave publicable que viaja dentro del HTML.
     · este cliente, que sabe llamar las dos.

   Y el orden importa: primero se publica la app, después se pega el SQL. Lo
   que se comprueba aquí es justo lo que hace que ese orden no tenga que salir
   bien por suerte.

   LAS CUATRO QUE, ROTAS, NO DAN NINGUNA SEÑAL

     1. Con el SQL sin pegar (404 a la firma nueva) la pantalla SIGUE pintando.
        Rota, el día que se publique la app y antes de pegar el SQL, todo el
        mundo ve «la nube no contestó» con el reporte subido.

     2. Un 403 NO se reintenta con la firma vieja. Rota, la pantalla se salta
        el filtro por la puerta de atrás y el arreglo entero no vale nada — y
        se vería bien, porque el asesor seguiría viendo su tarjeta.

     3. El gerente que entra con su CORREO firma la petición con su sesión, no
        con la clave publicable. Rota, `admin_de` responde que no y el dueño se
        queda sin ver a su equipo en su propia tienda, sin un solo error. Es el
        mismo fallo que ya costó dos días en la 1217, tres veces.

     4. El token de la tienda viaja en el cuerpo. Rota, `escritura_ok_` dice
        que no y no vuelve ni una fila — para nadie.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'comisiones.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

const STORE = { store_id:'1217', nombre:'Angelopolis', gas_token:'TOKEN-DE-LA-TIENDA' };
const ASESOR = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'asesor' };

// Lo que devolvería la firma VIEJA: el equipo entero, que es el problema.
const EQUIPO = [
  { empno:'1', nombre:'Jorge Medina Rejon',         puesto:'gerente', venta:180000,
    ppto_pct:95, alcance:98, gar_pct:31, gar_pzas:12, gar_elegible:38, gar_monto:4200,
    periodo:'sep-2026', periodo_gar:'sep-2026', actualizado:'2026-09-20T10:00:00Z' },
  { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'asesor',  venta:90000,
    ppto_pct:80, alcance:82, gar_pct:22, gar_pzas:6,  gar_elegible:27, gar_monto:1800,
    periodo:'sep-2026', periodo_gar:'sep-2026', actualizado:'2026-09-20T10:00:00Z' },
  { empno:'3', nombre:'Elena Navarro Galvez',        puesto:'asesor',  venta:75000,
    ppto_pct:70, alcance:71, gar_pct:19, gar_pzas:4,  gar_elegible:21, gar_monto:1200,
    periodo:'sep-2026', periodo_gar:'sep-2026', actualizado:'2026-09-20T10:00:00Z' }
];

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

const NUEVA = 'p_empno,p_store,p_token';
const VIEJA = 'p_store';

/* Un servidor de mentira que apunta cada petición. `responder` recibe el cuerpo
   ya interpretado y decide qué contesta — es donde se dice «el SQL está pegado»
   o «todavía no». */
function montar(responder, empleado){
  const llamadas = [];
  const ls = { odemas_store: JSON.stringify(STORE) };
  if(empleado) ls.odemas_empleado = JSON.stringify(empleado);

  const ent = crearEntorno({
    html, ruta:'/t/comisiones.html', ls,
    fetch: function(url, init){
      const cuerpo = JSON.parse((init && init.body) || '{}');
      const auth = String(((init && init.headers) || {}).Authorization || '');
      llamadas.push({ url:String(url), cuerpo, auth,
                      args: Object.keys(cuerpo).sort().join(',') });
      const r = responder(cuerpo) || {};
      return Promise.resolve({
        ok: (r.status || 200) === 200,
        status: r.status || 200,
        json: () => Promise.resolve(r.filas || [])
      });
    }
  });
  return Object.assign(ent, { llamadas,
    /* La pantalla se refresca SOLA al cargar (`refreshComisionesCloud()` al
       final del script). Esa vuelta hay que dejarla terminar y luego borrar su
       rastro; si no, sus peticiones aterrizan dentro del escenario y se leen
       como si fueran suyas — lo cual además es engañoso, porque en el arranque
       todavía no se ha puesto la sesión de mentira y van firmadas con la clave
       publicable. Nada de esto pasa en el navegador: allí supabase-js se carga
       con `defer`, o sea antes de DOMContentLoaded, y `supaListo_` lo espera.
       Es el arnés, que declara el documento «complete» desde el primer
       instante. */
    reposar: async () => {
      for(let i = 0; i < 20; i++) await new Promise(r => setImmediate(r));
      llamadas.length = 0;
    } });
}

async function main(){

  /* ── 1 · El SQL todavía no está pegado: la firma nueva no existe ──────── */
  {
    const s = montar(function(cuerpo){
      // PostgREST ante una firma que no existe: 404. Es el mundo de hoy.
      if('p_token' in cuerpo) return { status:404 };
      return { filas: EQUIPO };
    }, ASESOR);

    ok('SIN SQL · la pantalla arranca', !s.err, s.err);
    if(!s.err){
      await s.reposar();
      await s.correr('refreshComisionesCloud()');

      ok('SIN SQL · se intenta PRIMERO la firma que filtra',
         s.llamadas[0] && s.llamadas[0].args === NUEVA,
         s.llamadas[0] && s.llamadas[0].args);
      ok('SIN SQL · ante el 404 se cae a la firma vieja',
         s.llamadas[1] && s.llamadas[1].args === VIEJA,
         s.llamadas.length + ' llamada(s): ' + s.llamadas.map(c => c.args).join(' | '));

      const vista = s.htmlDe('app');
      ok('SIN SQL · el asesor ve SU tarjeta', vista.indexOf('Luis de Jesus Ortega Vidal') >= 0);
      /* Y aquí está el límite honesto de esta mitad: el dato del equipo YA
         viajó al teléfono; lo único que pasa es que no se pinta. Por eso hace
         falta el SQL y no basta con publicar la app. */
      ok('SIN SQL · no ve a sus companeros', vista.indexOf('Elena Navarro Galvez') < 0);
      ok('SIN SQL · tampoco al gerente',     vista.indexOf('Jorge Medina Rejon') < 0);
    }
  }

  /* ── 2 · Con el SQL pegado: una sola llamada, y ya filtrada ───────────── */
  {
    const s = montar(function(cuerpo){
      if(!('p_token' in cuerpo)) return { status:403 };   // revocada
      return { filas: EQUIPO.filter(k => k.empno === cuerpo.p_empno) };
    }, ASESOR);

    ok('CON SQL · la pantalla arranca', !s.err, s.err);
    if(!s.err){
      await s.reposar();
      await s.correr('refreshComisionesCloud()');

      ok('CON SQL · NO se vuelve a preguntar con la firma vieja',
         s.llamadas.length === 1 && s.llamadas[0].args === NUEVA,
         s.llamadas.map(c => c.args).join(' | '));
      ok('CON SQL · el token de la tienda viaja en el cuerpo',
         s.llamadas[0] && s.llamadas[0].cuerpo.p_token === 'TOKEN-DE-LA-TIENDA',
         s.llamadas[0] && String(s.llamadas[0].cuerpo.p_token));
      ok('CON SQL · y el numero de quien mira tambien',
         s.llamadas[0] && s.llamadas[0].cuerpo.p_empno === '2',
         s.llamadas[0] && String(s.llamadas[0].cuerpo.p_empno));
      ok('CON SQL · el asesor ve su tarjeta',
         s.htmlDe('app').indexOf('Luis de Jesus Ortega Vidal') >= 0);
    }
  }

  /* ── 3 · Un 403 NO abre la puerta de atrás ────────────────────────────── */
  /* «No sé quién eres» es una RESPUESTA del filtro, no una firma que falte.
     Reintentar sin argumentos sería saltárselo, y con la firma vieja revocada
     hoy no se notaría: mañana, si alguien la vuelve a conceder «un momento para
     probar algo», el filtro entero deja de existir en silencio. */
  {
    const s = montar(function(){ return { status:403 }; }, ASESOR);

    ok('403 · la pantalla arranca', !s.err, s.err);
    if(!s.err){
      await s.reposar();
      await s.correr('refreshComisionesCloud()');

      ok('403 · una sola llamada, sin reintento a la firma vieja',
         s.llamadas.length === 1, s.llamadas.map(c => c.args).join(' | '));
      ok('403 · y no se pinta la comision de nadie',
         s.htmlDe('app').indexOf('Elena Navarro Galvez') < 0);
    }
  }

  /* ── 4 · El gerente que entra con su CORREO ───────────────────────────── */
  /* No tiene ficha de empleado —su cuenta vive en `tiendas.user_id`—, así que
     llega sin número. Lo único que puede identificarlo es el JWT de su sesión,
     y `admin_de` lo lee del lado del servidor. Si la petición se firma con la
     clave publicable, `auth.uid()` viene vacío y el dueño no ve nada. */
  {
    const s = montar(function(cuerpo){
      if(!('p_token' in cuerpo)) return { status:403 };
      return { filas: EQUIPO };          // manda: el equipo entero
    });   // ← sin `odemas_empleado`: es el caso del dueño

    ok('CORREO · la pantalla arranca', !s.err, s.err);
    if(!s.err){
      // El CDN de supabase-js no existe aquí; se pone una sesión de mentira que
      // dice que sí manda, que es lo que contestaría el servidor.
      s.caja.supabase = { createClient: () => ({
        auth: { getSession: async () => ({ data:{ session:{ access_token:'JWT-DEL-GERENTE' } } }) },
        rpc:  async (fn) => (fn === 'admin_de' ? { data:true } : { data:null })
      }) };

      await s.reposar();
      await s.correr('refreshComisionesCloud()');

      ok('CORREO · la peticion se firma con la SESION, no con la clave publicable',
         s.llamadas[0] && s.llamadas[0].auth === 'Bearer JWT-DEL-GERENTE',
         s.llamadas[0] && s.llamadas[0].auth);
      ok('CORREO · va sin numero, porque el dueno no tiene ficha',
         s.llamadas[0] && s.llamadas[0].cuerpo.p_empno === '',
         s.llamadas[0] && JSON.stringify(s.llamadas[0].cuerpo.p_empno));

      const vista = s.htmlDe('app');
      ok('CORREO · ve al equipo entero', vista.indexOf('Elena Navarro Galvez') >= 0
                                      && vista.indexOf('Luis de Jesus Ortega Vidal') >= 0);
      ok('CORREO · y se le dice que esta viendo al equipo', vista.indexOf('Equipo') >= 0);
    }
  }

  if(fallos.length){
    console.log('comisiones privadas: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('comisiones privadas: cada quien ve lo suyo, y la pantalla aguanta el cambio de firma');
}

main().catch(function(e){
  console.log('comisiones privadas: la prueba reventó -> ' + (e && e.message));
  process.exit(1);
});
