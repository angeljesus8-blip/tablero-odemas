/* ============================================================
   Una venta que sobra se puede borrar
   ============================================================
   21-sep-2026. Corre en cada commit desde `verificar.py`.

   El caso que lo trae: apareció en la 1217 una venta a nombre de «ANA
   QUIROGA», que no es nadie de la tienda —vendedor sacado de
   `casos_tablero.js` y serie de `ocr_ticket_real11.txt`, o sea una venta de
   prueba escrita en la base de producción— y **no había forma de quitarla**.

   Borrar existía, pero sólo en la lista local del día (`window.del`), que son
   las capturas hechas EN ESE teléfono. Lo que está en la nube y no en el
   aparato sólo se podía CORREGIR, y corregir no sirve cuando la venta entera
   sobra: se queda contando en el inventario, en el conteo del día y en el
   attach de Assurant.

   ⚠️ Y el daño que no se ve: `ventas` tiene UNIQUE (store_id, serie). Mientras
   la fila falsa esté ahí, esa serie está OCUPADA — el día que se venda de
   verdad, el alta se rechaza por duplicada y nadie va a saber por qué.

   Lo que se fija aquí:

     1. El gerente ve el botón; el asesor no. Mismo permiso que corregir.
     2. Sólo se ofrece donde hay `captura_id`: sin id no hay por dónde agarrar
        la fila, y un botón que no puede funcionar es peor que no tenerlo.
     3. Se le pide a la base la fila QUE SE TOCÓ, no otra.
     4. Si la base dice que no, se enseña SU razón y no se toca nada local.
        El caso real es la entrega de un apartado: `venta_eliminar` contesta
        «deshazla desde Preventa», y resumir eso a «no se pudo» deja al gerente
        probando lo mismo otra vez.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');
const { crearEntorno } = require('./dom.js');

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal'];
const STORE  = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'tok12345',
                 vendedores:EQUIPO };
const GERENTE = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'gerente' };
const ASESOR  = { empno:'7', nombre:'Jorge Medina Rejon',         puesto:'asesor' };

const esperar = () => new Promise(r => setTimeout(r, 30));

/* Dos filas del día: una normal y un cobro de preventa sin `captura_id`. */
const FILAS = [
  { serie:'S-SOBRA', sku:'900001', descripcion:'MATEPAD 12X', precio:14999,
    vendedor:'ANA QUIROGA', con_seguro:true, vendida_en:'2026-09-21T16:27:00',
    captura_id:'i1790029640903bmcb', tiene_foto:false, entrega:null,
    cobrado_en:null, clase:'venta', venta_num:1 },
  { serie:null, sku:'900005', descripcion:'PURA 90S', precio:29999,
    vendedor:'Jorge Medina Rejon', con_seguro:true, vendida_en:'2026-09-21T17:00:00',
    captura_id:null, tiene_foto:false, entrega:'preventa',
    cobrado_en:'2026-09-21T17:00:00', clase:'cobro', venta_num:2 }
];

/* Abre el panel y devuelve lo pintado, además de las llamadas que salieron.
   `respuesta` es lo que contesta `venta_eliminar`. */
async function panel(empleado, respuesta, confirmar){
  const llamadas = [];
  const fetchFalso = (url, opts) => {
    const fn = String(url).split('/rpc/')[1] || String(url);
    let cuerpo = [];
    if(fn === 'ventas_detalle') cuerpo = FILAS;
    if(fn === 'venta_eliminar'){
      let params = {};
      try{ params = JSON.parse((opts && opts.body) || '{}'); }catch(e){}
      llamadas.push({ fn: fn, params: params });
      cuerpo = respuesta || { ok:true };
    }
    return Promise.resolve({
      ok:true, status:200,
      json: () => Promise.resolve(cuerpo),
      text: () => Promise.resolve(JSON.stringify(cuerpo))
    });
  };

  const ent = crearEntorno({
    html, ruta:'/t/captura_series.html', fetch: fetchFalso,
    confirm: confirmar !== false,
    ls: { odemas_store: JSON.stringify(STORE),
          odemas_empleado: JSON.stringify(empleado) }
  });
  if(ent.err) return { error: ent.err };
  try{
    ent.correr('cargarVentasDia(new Date());');
    await esperar();
  }catch(e){ return { error:(e && e.message) || String(e) }; }
  return { ent: ent, lista: ent.htmlDe('vdLista'), llamadas: llamadas };
}

function filaDe(listaHtml, texto){
  const trozos = String(listaHtml).split('<div class="vd-fila');
  return trozos.find(t => t.indexOf(texto) >= 0) || '';
}

(async () => {
  const fallos = [];
  const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

  /* ── 1 · Quién ve el botón ────────────────────────────────────────── */
  const g = await panel(GERENTE, { ok:true }, true);
  ok('el panel abre con el gerente', !g.error && !!g.lista, g.error || 'lista vacía');

  if(!g.error && g.lista){
    const sobra = filaDe(g.lista, 'S-SOBRA');
    ok('el gerente puede borrar la venta',
       sobra.indexOf('borrarVentaDia') >= 0, sobra.slice(0, 300));

    /* Sin `captura_id` no se puede identificar la fila: ahí no va el botón. */
    const cobro = filaDe(g.lista, 'PURA 90S');
    ok('sin captura_id no se ofrece borrar',
       cobro.indexOf('borrarVentaDia') < 0, cobro.slice(0, 300));
  }

  const a = await panel(ASESOR, { ok:true }, true);
  if(!a.error && a.lista){
    ok('el asesor NO puede borrar ventas',
       a.lista.indexOf('borrarVentaDia') < 0, a.lista.slice(0, 300));
    /* Y sigue sin poder corregirlas, que es el permiso que se copió. */
    ok('el asesor tampoco puede corregirlas',
       a.lista.indexOf('abrirEditarVenta') < 0, a.lista.slice(0, 300));
  }

  /* ── 2 · Se borra la fila que se tocó ─────────────────────────────── */
  if(!g.error){
    g.ent.correr('borrarVentaDia(0);');
    await esperar();
    const c = g.llamadas[0];
    ok('se le pide a la base borrar esa venta', !!c, 'no se llamó a venta_eliminar');
    if(c){
      ok('con el captura_id de la fila tocada',
         c.params.p_captura_id === 'i1790029640903bmcb', JSON.stringify(c.params));
      /* El token de la tienda: sin él la función contesta `no_autorizado` y el
         borrado se queda en la pantalla, no en la base. */
      ok('y con el token de la tienda',
         c.params.p_token === 'tok12345', JSON.stringify(c.params));
    }
  }

  /* ── 3 · Si no se confirma, no se borra nada ──────────────────────── */
  const n = await panel(GERENTE, { ok:true }, false);
  if(!n.error){
    n.ent.correr('borrarVentaDia(0);');
    await esperar();
    ok('si se cancela el aviso, no se llama a la base', n.llamadas.length === 0,
       JSON.stringify(n.llamadas));
  }

  /* ── 4 · El «no» de la base se enseña tal cual ────────────────────── */
  const apartado = 'esa venta es la entrega de un apartado: deshazla desde Preventa';
  const e = await panel(GERENTE, { ok:false, error: apartado }, true);
  if(!e.error){
    e.ent.correr('borrarVentaDia(0);');
    await esperar();
    const aviso = e.ent.htmlDe('toast') || (e.ent.el('toast') || {}).textContent || '';
    ok('se enseña la razón de la base, no un «no se pudo» genérico',
       String(aviso).indexOf('Preventa') >= 0, String(aviso).slice(0, 200));
  }

  if(fallos.length){
    console.error('FALLA · venta_borrar:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('venta borrar: el gerente puede quitar una venta que sobra, el asesor no, ' +
              'y el «no» de la base se explica (4 bloques)');
})();
