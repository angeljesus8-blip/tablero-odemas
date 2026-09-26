/* ============================================================
   Quién capturó la venta viaja con la venta
   ============================================================
   21-sep-2026 en la 1217, traída aquí el 26-sep. Corre en cada commit desde
   `verificar.py`.

   El caso que lo trae: apareció en la 1217 una venta de PRUEBA a nombre de
   alguien que no es de la tienda. Se pudo reconstruir de dónde salía cada
   campo —de los archivos de `pruebas/`— menos lo único que servía para que no
   se repita: **quién la metió**. Y no por falta de rastro, sino porque
   `public.ventas` no lo guardaba.

   Lo que se prueba aquí es el lado del cliente, que es el que se puede probar
   sin base: que el número de empleado de la sesión SALE con la venta, y que la
   pantalla lo enseña cuando viene.

   ⚠️ ESTA PRUEBA PASA AUNQUE EL SQL NO ESTÉ APLICADO. Es del cliente. El
   parámetro `p_quien` lo tiene que aceptar `venta_guardar`
   (supabase_venta_capturado_por.sql) ANTES de publicar la app: una app que
   manda un parámetro que la función no tiene recibe PGRST202 y deja de
   guardar ventas. El orden está escrito en la cabecera de ese SQL.

   Y lo que no se confunde: `p_vendedor` es quién COBRA la comisión, `p_quien`
   es quién TECLEÓ. En una venta normal son la misma persona; en la que motivó
   todo esto, no.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');
const { crearEntorno } = require('./dom.js');

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal'];
const STORE  = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'tok12345',
                 vendedores:EQUIPO };
const EMP    = { empno:'7', nombre:'Jorge Medina Rejon', puesto:'gerente' };

const esperar = () => new Promise(r => setTimeout(r, 30));

function entorno(filas){
  const fetchFalso = (url) => {
    const fn = String(url).split('/rpc/')[1] || '';
    const cuerpo = (fn === 'ventas_detalle') ? (filas || []) : [];
    return Promise.resolve({
      ok:true, status:200,
      json: () => Promise.resolve(cuerpo),
      text: () => Promise.resolve(JSON.stringify(cuerpo))
    });
  };
  return crearEntorno({
    html, ruta:'/t/captura_series.html', fetch: fetchFalso,
    ls: { odemas_store: JSON.stringify(STORE), odemas_empleado: JSON.stringify(EMP) }
  });
}

(async () => {
  const fallos = [];
  const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

  /* ── 1 · El número de quien captura sale con la venta ─────────────── */
  const ent = entorno([]);
  ok('la pantalla arranca', !ent.err, ent.err);

  if(!ent.err){
    const cuerpo = ent.correr(`JSON.stringify(_sbCuerpo({
      serie:'S-1', sku:'900001', desc:'PURA 80 PRO', precio:'24999',
      vend:'Luis de Jesus Ortega Vidal', seguro:true,
      fecha:'21/9/2026', hora:'4:27 p', id:'i1'
    }))`);
    let c = {};
    try{ c = JSON.parse(cuerpo); }catch(e){}

    ok('la venta lleva quién la capturó', c.p_quien === '7', JSON.stringify(c));
    /* Lo que no se puede confundir: quién vendió y quién tecleó son campos
       distintos aunque casi siempre coincidan. */
    ok('y sigue llevando aparte a quién le toca la comisión',
       c.p_vendedor === 'Luis de Jesus Ortega Vidal', JSON.stringify(c));
    ok('no se pierde nada de lo que ya mandaba',
       c.p_serie === 'S-1' && c.p_sku === '900001' && c.p_captura_id === 'i1' &&
       c.p_seguro === true && c.p_store === '1217', JSON.stringify(c));
  }

  /* ── 2 · La pantalla lo enseña cuando viene ───────────────────────── */
  const fila = (quien) => ([{
    serie:'S-VER', sku:'900001', descripcion:'MATEPAD 12X', precio:14999,
    vendedor:'Jorge Medina Rejon', con_seguro:true,
    vendida_en:'2026-09-21T16:27:00', captura_id:'i1', tiene_foto:false,
    entrega:null, cobrado_en:null, clase:'venta', venta_num:1,
    capturado_por: quien
  }]);

  const con = entorno(fila('7'));
  if(!con.err){
    con.correr('cargarVentasDia(new Date());');
    await esperar();
    con.correr('abrirEditarVenta(0);');
    const txt = con.el('edQuien').textContent || '';
    ok('el modal dice quién la capturó', txt.indexOf('7') >= 0, txt);
    /* Y que era uno mismo se dice, porque cambia a quién hay que preguntarle. */
    ok('y avisa cuando fuiste tú', txt.indexOf('tú') >= 0, txt);
  }

  /* Las ventas viejas no traen el dato. Ahí no se inventa ni se pinta un
     hueco: la línea no aparece. */
  const sin = entorno(fila(null));
  if(!sin.err){
    sin.correr('cargarVentasDia(new Date());');
    await esperar();
    sin.correr('abrirEditarVenta(0);');
    const el = sin.el('edQuien');
    ok('una venta sin el dato no enseña una línea vacía',
       (el.textContent || '') === '' && el.style.display === 'none',
       JSON.stringify({ txt: el.textContent, display: el.style.display }));
  }

  if(fallos.length){
    console.error('FALLA · venta_quien:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('venta quien: el numero de quien captura viaja con la venta y la ' +
              'pantalla lo enseña, sin inventar las viejas (3 bloques)');
})();
