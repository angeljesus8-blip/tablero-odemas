/* ============================================================
   La recarga por versión nueva no saca a nadie de donde estaba
   ============================================================
   26-sep-2026. Corre en cada commit desde `verificar.py`.

   Desde v287 la app recarga sola cuando llega una versión nueva, aunque nadie
   salga y vuelva. Ángel: «necesito que se actualice pero que no los saque de
   la página que están viendo». La recarga ya deja la misma dirección y
   continuidad.js devuelve el scroll; lo que se perdía era lo que NO vivía en
   la dirección:

     · Admin volvía a 📦 Catálogo, estuviera en la pestaña que estuviera.
     · Captura, revisando una captura (paso 2), volvía al paso 1.
     · Horarios, el gerente viendo otra semana, volvía a la semana en curso.

   El tablero ya guardaba sección y búsqueda en la dirección desde v152 (lo
   cubre `navegacion.js`).
   ============================================================ */
'use strict';
process.env.TZ = 'America/Mexico_City';
const fs = require('fs'), path = require('path');
const { crearEntorno } = require('./dom.js');
const leer = f => fs.readFileSync(path.join(__dirname, '..', f), 'utf8');

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

const SUPA_NADA = { createClient: () => ({
  auth: { getSession: async () => ({ data:{ session:null } }), signOut: async () => ({}) },
  from: () => ({ select(){ return this; }, eq(){ return this; }, order(){ return this; },
                 maybeSingle: async () => ({ data:null }), upsert: async () => ({ error:null }) }),
  rpc: async () => ({ data:null }) }) };

/* sessionStorage que sobrevive a "recargar" (montar otra vez con el mismo objeto). */
function ssCompartido(){
  const m = {};
  return { getItem:k=>(k in m?m[k]:null), setItem:(k,v)=>{m[k]=String(v);}, removeItem:k=>{delete m[k];} };
}

(async () => {

  /* 1 · Admin: la pestaña va a la dirección y vuelve al recargar. */
  {
    const url = { hash:'' };
    const ent = crearEntorno({ html: leer('admin.html'), ruta:'/t/admin.html',
      ls:{ odemas_store: JSON.stringify({ store_id:'9999' }), odemas_role:'gerente' },
      extras:{ supabase: SUPA_NADA,
               history:{ replaceState:(a,b,h)=>{ url.hash = h; }, pushState(){}, back(){} } } });
    if(ent.err){ fallos.push('admin no carga: ' + ent.err); }
    else {
      // Botones de la barra de pestañas como los del HTML (el andamiaje no los enumera).
      ent.correr(`(function(){
        const hechos = [];
        window.__clics = hechos;
        const btn = (id, extra) => ({ classList:{ add(){}, remove(){} },
          getAttribute: () => "tab('" + id + "',this)" + (extra || ''),
          click(){ hechos.push(id); tab(id, this); } });
        const botones = [btn('cat'), btn('promos'), btn('eol'), btn('avisos',';cargarListaAvisos()')];
        const orig = document.querySelectorAll;
        document.querySelectorAll = sel => sel === '.tab-bar button' ? botones : orig(sel);
        window.__botones = botones;
      })()`);
      ent.correr("tab('avisos', __botones[3])");
      ok('ADMIN · al cambiar de pestaña queda en la dirección', url.hash === '#avisos', url.hash);
      ent.correr("location.hash = '#avisos'");
      const abrio = ent.correr('tabDeLaUrl_()');
      ok('ADMIN · al recargar vuelve a esa pestaña, pulsando su botón',
         abrio === true && ent.correr('__clics[__clics.length-1]') === 'avisos');
      // Y lo hace ABRIR Admin, que es lo que corre tras la recarga.
      ent.correr("__clics.length = 0; location.hash = '#eol'");
      try { ent.correr('abrirAdmin()'); } catch(e) { /* la red no existe aquí; importa la pestaña */ }
      ok('ADMIN · abrir Admin tras recargar regresa a la pestaña de la dirección',
         ent.correr('__clics.indexOf("eol")') >= 0, ent.correr('JSON.stringify(__clics)'));
      ent.correr("location.hash = '#noexiste'");
      ok('ADMIN · una pestaña que no existe no rompe: se queda en Catálogo', ent.correr('tabDeLaUrl_()') === false);
    }
  }

  /* 2 · Captura: revisando una captura no se recarga. */
  {
    const ent = crearEntorno({ html: leer('captura_series.html'), ruta:'/t/captura_series.html',
      ls:{ odemas_store: JSON.stringify({ store_id:'9999' }), odemas_role:'asesor' } });
    if(ent.err){ fallos.push('captura no carga: ' + ent.err); }
    else {
      ok('CAPTURA · en el paso 1, libre', ent.correr('HES_ocupado()') === false);
      ent.correr('_paso = 2');
      ok('CAPTURA · revisando la captura (paso 2): ocupado', ent.correr('HES_ocupado()') === true);
      ent.correr('_paso = 3');
      ok('CAPTURA · en el seguro (paso 3): ocupado', ent.correr('HES_ocupado()') === true);
    }
  }

  /* 3 · Horarios: el gerente vuelve a la semana que estaba viendo. */
  {
    const EQUIPO = { horaApertura:10, horaCierre:21,
      gerentes:[{ key:'G1', nombre:'ANA GERENTE', cargo:'Gerente de Tienda', emp:'900001', descFijo:5 }],
      asesores:[{ key:'A1', nombre:'CARO ASESORA', cargo:'Asesor', emp:'900003', descFijo:3 }] };
    const ss = ssCompartido();
    const montar = () => {
      const ent = crearEntorno({ html: leer('horarios.html'), ruta:'/tablero-odemas/horarios.html',
        extras:{ supabase: SUPA_NADA, sessionStorage: ss } });
      if(ent.err) throw new Error('horarios no carga: ' + ent.err);
      ent.correr('fijarSesion({ store_id:"9999", nombre:"A" }, { puedeEditar:true })');
      ent.correr('cargarConfig = async (c) => c === "equipo" ? ' + JSON.stringify(EQUIPO) + ' : null');
      return ent;
    };
    const a = montar();
    await a.correr('init()');
    const actual = a.correr('_semana');
    a.correr('navSemana(2)');
    const b = montar();                              // «recarga»
    await b.correr('init()');
    ok('HORARIOS GERENTE · tras recargar sigue en la semana que veía',
       b.correr('_semana') === actual + 2, 'antes ' + (actual + 2) + ', después ' + b.correr('_semana'));

    // El equipo, en cambio, ve siempre la que le toca: aunque haya algo guardado.
    const c = crearEntorno({ html: leer('horarios.html'), ruta:'/tablero-odemas/horarios.html',
      extras:{ supabase: SUPA_NADA, sessionStorage: ss } });
    c.correr('fijarSesion({ store_id:"9999", nombre:"A" }, { empno:"900003", puesto:"Asesor" })');
    c.correr('cargarConfig = async (c) => c === "equipo" ? ' + JSON.stringify(EQUIPO) + ' : null');
    await c.correr('init()');
    ok('HORARIOS EQUIPO · no hereda la semana del gerente', c.correr('_semana') === actual, c.correr('_semana'));
  }

  if(fallos.length){
    console.log('FALLAS en recarga_en_su_sitio.js:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('recarga en su sitio: Admin vuelve a su pestaña, Captura no recarga revisando, y el gerente sigue en su semana');
})().catch(e => { console.log('FALLA recarga_en_su_sitio.js: ' + (e && e.stack || e)); process.exit(1); });
