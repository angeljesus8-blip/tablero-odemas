/* ============================================================
   El bloqueo por demasiados intentos se dice, y no se salta
   ============================================================
   2-oct-2026. Corre en cada commit desde `verificar.py`.

   `login_empleado` no tenía límite de intentos: con la clave publicable del
   HTML cualquiera podía probar números de empleado hasta acertar uno y llevarse
   la clave de escritura de esa tienda. supabase_login_limite.sql bloquea la IP
   15 minutos tras 15 fallos y responde un ERROR `demasiados_intentos`.

   Lo que se prueba aquí es el lado del cliente:
     1 · Con el bloqueo, la pantalla lo dice y NO sigue por `login_asesor` ni por
         el camino viejo: seguiría probando y el bloqueo no serviría de nada.
     2 · Lo dice también en el intento automático (a los 5 dígitos): callarse se
         vería como una app que no responde.
     3 · Un número equivocado de siempre sigue diciendo «No reconozco ese número».
     4 · Horarios no confunde el bloqueo con «no te han dado de alta».

   ⚠️ ESTA PRUEBA PASA AUNQUE EL SQL NO ESTÉ APLICADO. Es inofensiva sin él: una
   app que espera un error que la base todavía no manda simplemente no lo ve.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const { crearEntorno } = require('./dom.js');
const raiz = path.join(__dirname, '..');
const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

(async () => {
  const html = fs.readFileSync(path.join(raiz, 'index.html'), 'utf8');

  function entorno(respuestaEmpleado){
    const llamadas = [];
    const sbFalso = {
      rpc: (fn, args) => {
        llamadas.push(fn);
        if(fn === 'login_empleado') return Promise.resolve(respuestaEmpleado);
        return Promise.resolve({ data: [], error: null });   // login_asesor: cerrado
      },
      from: () => { llamadas.push('from(tiendas)'); return { select: () => ({ eq: () => ({ eq: () => ({ maybeSingle: () => Promise.resolve({ data: null }) }) }) }) }; },
      auth: { getSession: () => Promise.resolve({ data: { session: null } }),
              onAuthStateChange: () => ({ data: { subscription: { unsubscribe(){} } } }) }
    };
    const ent = crearEntorno({ html, ruta: '/t/index.html',
      extras: { supabase: { createClient: () => sbFalso } } });
    return { ent, llamadas };
  }

  const BLOQUEO = { data: null, error: { code: 'P0001', message: 'demasiados_intentos' } };

  /* 1 · Bloqueado, tecleando el número completo */
  {
    const { ent, llamadas } = entorno(BLOQUEO);
    ok('index.html arranca', !ent.err, ent.err);
    if(!ent.err){
      ent.correr('initSB()');
      await ent.correr("pinVal = '100001'; pinCheck()");
      const msg = ent.el('pinErr').textContent;
      ok('el bloqueo se dice en pantalla', /Demasiados intentos/.test(msg), msg);
      ok('y no se sigue por login_asesor', llamadas.indexOf('login_asesor') < 0, llamadas.join(','));
      ok('ni por el camino viejo (leer tiendas)', llamadas.indexOf('from(tiendas)') < 0, llamadas.join(','));

      /* 2 · Lo mismo en el intento automático */
      ent.el('pinErr').textContent = '';
      llamadas.length = 0;
      await ent.correr("pinVal = '10000'; pinCheck(true)");
      ok('el intento automático también lo dice', /Demasiados intentos/.test(ent.el('pinErr').textContent),
         ent.el('pinErr').textContent);
      ok('y tampoco sigue por la ruta de respaldo', llamadas.indexOf('login_asesor') < 0, llamadas.join(','));
    }
  }

  /* 3 · Un número equivocado: sin cambios */
  {
    const { ent, llamadas } = entorno({ data: [], error: null });
    if(!ent.err){
      ent.correr('initSB()');
      await ent.correr("pinVal = '999999'; pinCheck()");
      ok('un número equivocado sigue diciendo «No reconozco»',
         /No reconozco/.test(ent.el('pinErr').textContent), ent.el('pinErr').textContent);
    }
  }

  /* 4 · Horarios, a la vista */
  {
    const h = fs.readFileSync(path.join(raiz, 'horarios.html'), 'utf8');
    ok('Horarios distingue el bloqueo de «no reconozco ese número»',
       /resp\.error && \/demasiados_intentos\/\.test\(resp\.error\.message/.test(h));
  }

  if(fallos.length){
    console.error('FALLA · login_limite:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('login: el bloqueo por intentos se dice (también en el intento automático) y no se salta por la ruta de respaldo');
})();
