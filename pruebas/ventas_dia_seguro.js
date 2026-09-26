/* ============================================================
   «Ventas del día» dice cuáles llevaron seguro
   ============================================================
   6-sep-2026. Corre en cada commit desde `verificar.py`.

   `ventas_detalle` devolvía `con_seguro` desde el primer día —en las tres
   clases de fila— y el mapeo del cliente lo tiraba al traducir las filas de
   Supabase a las claves cortas del panel. La pantalla no podía enseñar un dato
   que sí tenía, y nadie podía ver qué se fue sin proteger sin abrir venta por
   venta.

   No da error, y por eso la prueba mira LO PINTADO y no el mapeo: un campo que
   se pierde en la traducción deja la pantalla exactamente igual de callada que
   un campo que no existe.

   Las tres cosas que, rotas, no avisan:

     1. `null` NO es «sin seguro». Son las capturas anteriores al dato. Pintarlas
        en gris inventa ventas sin proteger que nadie registró así, y de paso
        hunde el porcentaje de abajo.
     2. El attach del día EXCLUYE las entregas e INCLUYE los cobros — el mismo
        criterio de `ventas_hoy`, que es el número que se reporta. Contar todas
        las filas daría otro attach del mismo día, sin que ninguno esté mal.
     3. La insignia se pinta también en entregas y cobros: el cliente se llevó
        su seguro aunque el dinero entrara otro día.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal'];
const STORE  = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'tok12345',
                 vendedores:EQUIPO };
const EMP    = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'gerente' };

const esperar = () => new Promise(r => setTimeout(r, 30));

/* Un día con las cinco situaciones que existen de verdad. Los campos son los
   que devuelve `ventas_detalle` (ver supabase_venta_grupo.sql), no los cortos
   del panel: lo que se prueba es justo la traducción entre unos y otros. */
const FILAS = [
  { serie:'S-CON',  sku:'900001', descripcion:'PURA 80 PRO',   precio:24999,
    vendedor:'Luis', con_seguro:true,  vendida_en:'2026-09-06T11:00:00',
    captura_id:'c1', tiene_foto:false, entrega:null, cobrado_en:null,
    clase:'venta',   venta_num:1 },
  { serie:'S-SIN',  sku:'900002', descripcion:'BAND 11',       precio:1999,
    vendedor:'Luis', con_seguro:false, vendida_en:'2026-09-06T12:00:00',
    captura_id:'c2', tiene_foto:false, entrega:null, cobrado_en:null,
    clase:'venta',   venta_num:2 },
  { serie:'S-VIEJA', sku:'900003', descripcion:'WATCH FIT 5',  precio:3499,
    vendedor:'Luis', con_seguro:null,  vendida_en:'2026-09-06T13:00:00',
    captura_id:'c3', tiene_foto:false, entrega:null, cobrado_en:null,
    clase:'venta',   venta_num:3 },
  { serie:'S-ENT',  sku:'900004', descripcion:'MATE X7',       precio:59999,
    vendedor:'Luis', con_seguro:true,  vendida_en:'2026-09-06T14:00:00',
    captura_id:'c4', tiene_foto:false, entrega:'preventa', cobrado_en:'2026-08-20T10:00:00',
    clase:'entrega', venta_num:4 },
  { serie:null,     sku:'900005', descripcion:'PURA 90S',      precio:29999,
    vendedor:'Luis', con_seguro:true,  vendida_en:'2026-09-06T15:00:00',
    captura_id:null, tiene_foto:false, entrega:'preventa', cobrado_en:'2026-09-06T15:00:00',
    clase:'cobro',   venta_num:5 }
];

/* Abre el panel con las filas que se le pasen y devuelve lo pintado. */
async function panelCon(filas){
  const fetchFalso = (url) => {
    const fn = String(url).split('/rpc/')[1] || String(url);
    const cuerpo = (fn === 'ventas_detalle') ? filas : [];
    return Promise.resolve({
      ok:true, status:200,
      json: () => Promise.resolve(cuerpo),
      text: () => Promise.resolve(JSON.stringify(cuerpo))
    });
  };

  const ent = crearEntorno({
    html, ruta:'/t/captura_series.html', fetch: fetchFalso,
    ls: { odemas_store: JSON.stringify(STORE), odemas_empleado: JSON.stringify(EMP) }
  });
  if(ent.err) return { error: ent.err };

  try{
    ent.correr('cargarVentasDia(new Date());');
    await esperar();
  }catch(e){ return { error: (e && e.message) || String(e) }; }

  return { lista: ent.htmlDe('vdLista'), ayuda: ent.htmlDe('vdAyuda') };
}

/* El trozo de HTML de una fila, para poder preguntarle a UNA sola. Cada fila
   abre con `<div class="vd-fila…`, así que se parte por ahí. */
function filaDe(listaHtml, serie){
  const trozos = String(listaHtml).split('<div class="vd-fila');
  return trozos.find(t => t.indexOf(serie) >= 0) || '';
}

(async () => {
  const fallos = [];
  const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

  const r = await panelCon(FILAS);
  ok('el panel abre y pinta', !r.error && !!r.lista, r.error || 'lista vacía');

  if(!r.error && r.lista){
    /* ── 1 · Cada fila dice lo suyo ──────────────────────────────────── */
    const con   = filaDe(r.lista, 'S-CON');
    const sin   = filaDe(r.lista, 'S-SIN');
    const vieja = filaDe(r.lista, 'S-VIEJA');
    const ent   = filaDe(r.lista, 'S-ENT');

    ok('la venta con seguro lleva la insignia',
       con.indexOf('vd-seg') >= 0 && con.indexOf('Assurant') >= 0, con.slice(0, 200));
    ok('la venta sin seguro lo dice, en gris',
       sin.indexOf('vd-seg no') >= 0 && sin.indexOf('sin seguro') >= 0, sin.slice(0, 200));

    /* La que más importa: una captura vieja no tiene por qué parecer una venta
       que se dejó ir sin proteger. */
    ok('una captura vieja (null) no dice ni una cosa ni la otra',
       vieja.indexOf('vd-seg') < 0, vieja.slice(0, 200));

    /* La entrega se cobró semanas antes, pero el equipo salió con su seguro y
       eso es lo que se pregunta mirando la lista. */
    ok('una entrega de apartado también enseña su seguro',
       ent.indexOf('vd-seg') >= 0 && ent.indexOf('Assurant') >= 0, ent.slice(0, 200));

    /* ── 2 · El attach del día, con el criterio del KPI ──────────────── */
    ok('la lista dice el attach del día', r.ayuda.indexOf('Assurant del día') >= 0, r.ayuda);

    /* Cuentan: S-CON (sí), S-SIN (no) y el cobro (sí). Fuera: la entrega, que
       no es del corte de hoy, y la vieja, que no tiene dato.
       Si alguna de las dos exclusiones se cae, este número cambia. */
    ok('cuenta los cobros y deja fuera entregas y capturas sin dato',
       r.ayuda.indexOf('2 de 3') >= 0, r.ayuda);
    ok('y da el porcentaje del KPI', r.ayuda.indexOf('(67%)') >= 0, r.ayuda);
  }

  /* ── 3 · Sin una sola fila con dato, no se inventa un porcentaje ───── */
  const soloViejas = await panelCon([FILAS[2]]);
  if(!soloViejas.error){
    ok('un día entero de capturas viejas no enseña un attach de cero',
       soloViejas.ayuda.indexOf('Assurant del día') < 0, soloViejas.ayuda);
  }

  if(fallos.length){
    console.log('ventas del día · seguro: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('ventas del día · seguro: la insignia se pinta por artículo y el attach usa el criterio del KPI');
})();
