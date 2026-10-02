/* ============================================================
   Las lecturas del negocio viajan con el token
   ============================================================
   2-oct-2026. Corre en cada commit desde `verificar.py`.

   Hasta v37, `apartados_lista`, `tablero_todo` y las siete lecturas
   (inventario, catálogo, promos, EOL, avisos, combos, precio de EOL)
   contestaban a cualquiera con la clave publicable, y esa clave va en el HTML
   de un repo público: nombre y teléfono de cada cliente con apartado, y el
   stock de cualquier tienda. Ver supabase_candado.sql.

   Lo que se prueba aquí es el lado del cliente:
     1 · El tablero manda el token al pedir `tablero_todo` y `apartados_lista`.
     2 · `apartados_ok: false` se enseña como carga fallida, no como «no hay».
     3 · Un `{ok:false}` de `tablero_todo` no se aplica como inventario vacío.
     4 · Captura pide catálogo, promos y precio de EOL con el token.
     5 · Admin lee sus lecturas con el token.
     6 · `ventas_hoy` y `ventas_detalle` también (supabase_candado_ventas.sql).

   ⚠️ ESTA PRUEBA PASA AUNQUE EL SQL NO ESTÉ APLICADO. El SQL va ANTES de
   publicar: una app que manda `p_token` a una función que aún no lo tiene
   recibe PGRST202 y se queda sin catálogo ni promos.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const raiz = path.join(__dirname, '..');
const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };
const TOKEN = 'tok-candado-9999';

(async () => {

  /* ── 1-3 · Tablero ─────────────────────────────────────────────────── */
  {
    const { domFalso, TIENDA } = require('./entorno.js');
    const html = fs.readFileSync(path.join(raiz, 'tablero.html'), 'utf8');
    const js = (html.match(/<script(?![^>]*\ssrc=)[^>]*>[\s\S]*?<\/script>/g) || [])
      .map(b => b.replace(/^<script[^>]*>/, '').replace(/<\/script>$/, '')).join('\n;\n');
    domFalso();
    Object.assign(global, require('../nombres.js'));
    localStorage.setItem('odemas_store', JSON.stringify({ store_id:'9999', nombre:'Prueba',
                                                         gas_url:'', gas_token: TOKEN }));
    try{
      vm.runInThisContext(js, { filename:'tablero.html' });
    }catch(e){ ok('el tablero arranca', false, e && e.message); }

    const llamadas = [];
    let respuesta = null;
    global.fetch = (url, op) => {
      const fn = String(url).split('/rpc/')[1] || '';
      let body = {}; try{ body = JSON.parse((op && op.body) || '{}'); }catch(e){}
      llamadas.push({ fn, body });
      const r = fn === 'tablero_todo' ? respuesta : fn === 'apartados_lista' ? TIENDA.apartados : [];
      return Promise.resolve({ ok:true, status:200, json:() => Promise.resolve(r) });
    };
    const de = fn => llamadas.filter(l => l.fn === fn)[0];

    respuesta = JSON.parse(JSON.stringify(TIENDA));
    await vm.runInThisContext('cargarTodoSupabase()');
    ok('tablero_todo se pide con el token', de('tablero_todo') && de('tablero_todo').body.p_token === TOKEN,
       JSON.stringify(de('tablero_todo')));
    ok('con el servidor de antes (sin apartados_ok) los apartados cargan como siempre',
       vm.runInThisContext('CARGAS.apartados') === 'ok' && vm.runInThisContext('APARTADOS.length') === 4,
       vm.runInThisContext('CARGAS.apartados') + ' / ' + vm.runInThisContext('APARTADOS.length'));

    await vm.runInThisContext('cargarApartadosNube()');
    ok('apartados_lista se pide con el token', de('apartados_lista') && de('apartados_lista').body.p_token === TOKEN,
       JSON.stringify(de('apartados_lista')));

    await vm.runInThisContext('cargarVentasNube()');
    ok('ventas_hoy se pide con el token (2-oct-2026)', de('ventas_hoy') && de('ventas_hoy').body.p_token === TOKEN,
       JSON.stringify(de('ventas_hoy')));

    /* El servidor no aceptó el token. Lo que NO puede pasar es que la pestaña
       diga «no hay apartados»: el asesor le negaría el equipo al cliente. Tiene
       que quedar como carga fallida, y los de antes, a la vista. */
    respuesta = Object.assign(JSON.parse(JSON.stringify(TIENDA)), { apartados: [], apartados_ok: false });
    await vm.runInThisContext('cargarTodoSupabase()');
    ok('sin permiso, los apartados quedan como carga fallida', vm.runInThisContext('CARGAS.apartados') === 'error',
       vm.runInThisContext('CARGAS.apartados'));
    ok('y no se borran los que ya estaban en pantalla', vm.runInThisContext('APARTADOS.length') === 4,
       String(vm.runInThisContext('APARTADOS.length')));

    /* Sin token válido, `tablero_todo` contesta {ok:false}. El tablero no puede
       tomarlo por un inventario vacío —pintaría todo agotado—. */
    const antes = vm.runInThisContext('Object.keys(invBySku).length');
    respuesta = { ok:false, apartados_ok:false };
    const r3 = await vm.runInThisContext('cargarTodoSupabase()');
    ok('un {ok:false} no se aplica como inventario', r3 === false, String(r3));
    ok('y el inventario que había sigue ahí', vm.runInThisContext('Object.keys(invBySku).length') === antes,
       antes + ' → ' + vm.runInThisContext('Object.keys(invBySku).length'));
  }

  /* ── 4 · Captura pide catálogo, promos y precio de EOL con el token ── */
  {
    const { crearEntorno } = require('./dom.js');
    const html = fs.readFileSync(path.join(raiz, 'captura_series.html'), 'utf8');
    const llamadas = [];
    const ent = crearEntorno({
      html, ruta:'/t/captura_series.html',
      fetch: (url, op) => {
        const fn = String(url).split('/rpc/')[1] || '';
        let body = {}; try{ body = JSON.parse((op && op.body) || '{}'); }catch(e){}
        llamadas.push({ fn, body });
        return Promise.resolve({ ok:true, status:200, json:() => Promise.resolve([]), text:() => Promise.resolve('[]') });
      },
      ls: { odemas_store: JSON.stringify({ store_id:'9999', nombre:'Prueba', gas_url:'', gas_token: TOKEN, vendedores:['Prueba Uno'] }),
            odemas_empleado: JSON.stringify({ empno:'1', nombre:'Prueba Uno', puesto:'gerente' }) }
    });
    ok('Captura arranca', !ent.err, ent.err);
    if(!ent.err){
      for(const fn of ['catalogo_completo', 'promos_vigentes', 'eol_precio_venta']){
        llamadas.length = 0;
        await ent.correr(`sbRpcCS('${fn}')`);
        const c = llamadas.filter(l => l.fn === fn)[0];
        ok('Captura pide ' + fn + ' con el token', c && c.body.p_token === TOKEN, JSON.stringify(c && c.body));
      }
    }
    /* La llamada de verdad, la de la página: a la vista, para que nadie la
       quite sin que la prueba lo note. */
    ok('Captura pide ventas_detalle con el token en su código (2-oct-2026)',
       /sbCallCS\('ventas_detalle', \{\s*p_token: GAS_TOKEN/.test(html));
    ok('Captura llama apartados_lista con el token en su código',
       /sbCallCS\('apartados_lista', \{ p_token: GAS_TOKEN \}\)/.test(html));
  }

  /* ── 5 · Admin, a la vista: sus lecturas llevan el token ────────────── */
  {
    const admin = fs.readFileSync(path.join(raiz, 'admin.html'), 'utf8');
    for(const fn of ['bundles_vigentes', 'eol_lista', 'avisos_vigentes']){
      ok('Admin lee ' + fn + ' con el token',
         new RegExp("sbLeer\\('" + fn + "', \\{ p_token: GAS_TOKEN \\}\\)").test(admin));
    }
    ok('Admin pide tablero_todo con el token',
       /sb\.rpc\("tablero_todo", \{[^}]*p_token: GAS_TOKEN/.test(admin));
  }

  if(fallos.length){
    console.error('FALLA · candado_token:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('candado: las lecturas del negocio viajan con el token, y el «sin permiso» no se lee como «no hay»');
})();
