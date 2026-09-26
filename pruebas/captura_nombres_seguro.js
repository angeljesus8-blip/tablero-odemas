/* ============================================================
   Captura: el nombre se traduce en PANTALLA, y el seguro no se elige solo
   ============================================================
   Corre en cada commit desde `verificar.py`. Nació con la fase 4 del
   rediseño visual (22-sep-2026).

   Dos cosas que, rotas, NO dan ningún error y cuestan dinero:

   1. NOMBRES. «AUDIF IN EAR HW F-BUDS PRO 4 VD» se enseña como «Audífonos
      Huawei FreeBuds Pro 4 · Verde», pero la venta tiene que seguir llevando
      la descripción DEL SISTEMA: con ella se cuadra el reporte regional y se
      empata contra el POS. Un traductor metido un paso más adentro (en
      `aplicarProducto`, en el campo, en `_sbCuerpo`) guardaría el nombre
      bonito y el reporte dejaría de cuadrar sin que nadie lo viera.
      Y sin nombres.js (no llegó, caché vieja) la pantalla no revienta.

   2. SEGURO. En el tablero «1 año» sale MARCADO porque ahí solo se cotiza.
      En Captura el toque ES el registro: lo elegido va al Assurant attach.
      «1 año» va destacado, pero nada lo elige por el asesor. Aquí se revisa
      el marcado (sin `autofocus`, ningún `.focus()` a esos botones, 1 y 2 años
      registran `true`) y que un segundo «Agregar» con el modal abierto no
      pise la venta que espera respuesta. El teclado de verdad (Enter, tocar
      fuera) se prueba en un navegador real: `pantalla_390.js`.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const RAIZ = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(RAIZ, 'captura_series.html'), 'utf8');
const NOMBRES = fs.readFileSync(path.join(RAIZ, 'nombres.js'), 'utf8');
const { crearEntorno } = require('./dom.js');

const STORE = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'t',
                vendedores:['Prueba Uno'] };
const EMP   = { empno:'1', nombre:'Prueba Uno', puesto:'gerente' };
const CRUDA = 'AUDIF IN EAR HW F-BUDS PRO 4 VD';
const BONITA = 'Audífonos Huawei FreeBuds Pro 4 · Verde';
const MALA  = 'AUDIF <img src=x onerror=alert(1)> VD';

const fallos = [];
const esperar = () => new Promise(r => setTimeout(r, 30));

function abrir(conNombres, fetchFalso){
  const ent = crearEntorno({ html, ruta:'/t/captura_series.html', fetch: fetchFalso,
    ls: { odemas_store: JSON.stringify(STORE), odemas_empleado: JSON.stringify(EMP) } });
  if(ent.err) return ent;
  // dom.js no baja los <script src>: nombres.js se mete a mano, como lo haría
  // el navegador ANTES del script principal (va más arriba en el HTML).
  if(conNombres) ent.correr(NOMBRES);
  return ent;
}

/* Una venta completa: el catálogo autollena, se agrega, se contesta el seguro. */
function venderUna(ent, conSeguro){
  ent.correr(`irPaso(2); aplicarProducto({ s:'100245689', d:${JSON.stringify(CRUDA)} });
              $('serie').value = 'ABCDE12345678901';`);
  const enPantalla = ent.el('descCliente').textContent;
  const enCampo = ent.el('desc').value;
  ent.correr(`$('btnAdd').onclick()`);
  ent.correr(`finalizarVenta(${conSeguro})`);
  return { enPantalla, enCampo };
}

(async () => {
  /* ── 1 · Con nombres.js: se traduce lo que se VE, no lo que se GUARDA ── */
  {
    const ent = abrir(true);
    if(ent.err){ fallos.push('nombres: la pantalla se cae al cargar -> ' + ent.err); }
    else {
      const r = venderUna(ent, true);
      if(r.enPantalla !== BONITA)
        fallos.push(`nombres: debajo de la descripción se esperaba «${BONITA}» y sale «${r.enPantalla}»`);
      if(r.enCampo !== CRUDA)
        fallos.push(`nombres: el campo Descripción cambió a «${r.enCampo}» — es lo que se guarda y debe ser el del sistema`);

      const item = ent.correr('items[0]');
      if(!item || item.desc !== CRUDA)
        fallos.push('nombres: la captura guardada en el teléfono no lleva la descripción del sistema (' + (item && item.desc) + ')');
      const cuerpo = ent.correr('sbPend[sbPend.length - 1]');
      if(!cuerpo || cuerpo.p_desc !== CRUDA)
        fallos.push('nombres: lo que sube a Supabase (p_desc) no es la descripción del sistema (' + (cuerpo && cuerpo.p_desc) + ')');

      const lista = ent.htmlDe('lista');
      if(lista.indexOf(BONITA) < 0) fallos.push('nombres: la lista del día no enseña el nombre para el cliente');

      // Al cerrar la venta el nombre del paso 2 se va con los campos: si se
      // quedara, el siguiente cliente vería el producto del anterior.
      if(ent.el('descCliente').textContent)
        fallos.push('nombres: tras agregar, el nombre del producto anterior sigue debajo del campo vacío');

      // Lo que se teclea a mano también se traduce (el evento «input»).
      ent.el('desc').value = 'HUAWEI PURA 80 PRO 12/512GB RJ';
      ent.correr('pintarNombreCS()');
      if(ent.el('descCliente').textContent.indexOf('Huawei Pura 80 Pro') < 0)
        fallos.push('nombres: una descripción escrita a mano no se traduce debajo');
      if(html.indexOf("$('desc').addEventListener('input', pintarNombreCS)") < 0)
        fallos.push('nombres: pintarNombreCS ya no está colgado del «input» del campo Descripción');

      // Una descripción con HTML se escapa: va a innerHTML.
      ent.correr(`items.unshift({ id:'x1', serie:'ZZZ', sku:'1', precio:'1', desc:${JSON.stringify(MALA)},
                   vend:'Prueba Uno', fecha:new Date().toLocaleDateString('es-MX'), hora:'', seguro:false }); render();`);
      if(/<img/i.test(ent.htmlDe('lista')))
        fallos.push('nombres: una descripción con «<img …>» entra a la lista del día sin escapar');
    }
  }

  /* ── 2 · Sin nombres.js: se ve como antes, no revienta ── */
  {
    const ent = abrir(false);
    if(ent.err){ fallos.push('sin nombres.js: la pantalla se cae al cargar -> ' + ent.err); }
    else {
      let r;
      try { r = venderUna(ent, false); }
      catch(e){ fallos.push('sin nombres.js: la venta revienta -> ' + (e && e.message)); }
      if(r){
        if(r.enPantalla) fallos.push('sin nombres.js: debajo del campo sale «' + r.enPantalla + '» — debería quedar vacío');
        if(ent.htmlDe('lista').indexOf(CRUDA) < 0) fallos.push('sin nombres.js: la lista del día no enseña ni la descripción cruda');
        const cuerpo = ent.correr('sbPend[sbPend.length - 1]');
        if(!cuerpo || cuerpo.p_desc !== CRUDA) fallos.push('sin nombres.js: la venta no llega con su descripción');
      }
    }
  }

  /* ── 3 · Ventas del día: nombre traducido, y la del sistema chica y escapada ── */
  {
    const filas = [
      { serie:'S-1', sku:'100245689', descripcion:CRUDA, precio:2999, vendedor:'Luis', con_seguro:true,
        vendida_en:'2026-09-22T11:00:00', captura_id:'c1', tiene_foto:false, entrega:null,
        cobrado_en:null, clase:'venta', venta_num:1 },
      { serie:'S-2', sku:'1', descripcion:MALA, precio:1, vendedor:'Luis', con_seguro:false,
        vendida_en:'2026-09-22T12:00:00', captura_id:'c2', tiene_foto:false, entrega:null,
        cobrado_en:null, clase:'venta', venta_num:2 },
    ];
    const fetchFalso = (url) => {
      const fn = String(url).split('/rpc/')[1] || String(url);
      const cuerpo = (fn === 'ventas_detalle') ? filas : [];
      return Promise.resolve({ ok:true, status:200, json: () => Promise.resolve(cuerpo),
                               text: () => Promise.resolve(JSON.stringify(cuerpo)) });
    };
    const ent = abrir(true, fetchFalso);
    if(ent.err){ fallos.push('ventas del día: la pantalla se cae -> ' + ent.err); }
    else {
      ent.correr('cargarVentasDia(new Date());'); await esperar();
      const l = ent.htmlDe('vdLista');
      if(l.indexOf(BONITA) < 0) fallos.push('ventas del día: no enseña el nombre para el cliente');
      if(l.indexOf(CRUDA) < 0) fallos.push('ventas del día: ya no enseña la descripción del sistema (con ella se coteja el POS)');
      if(/<img/i.test(l)) fallos.push('ventas del día: una descripción con «<img …>» entra sin escapar');
    }
  }

  /* ── 4 · Seguro: «1 año» destacado, nada elegido por el asesor ── */
  {
    const i0 = html.indexOf('<div id="modalSeguro"');
    const modal = i0 < 0 ? '' : html.slice(i0, html.indexOf('</div>\n</div>', i0));
    if(!modal) fallos.push('seguro: no encuentro el modal del seguro (#modalSeguro)');
    else {
      if(/<[a-z][^>]*\sautofocus/i.test(modal)) fallos.push('seguro: un botón del modal lleva autofocus — Enter elegiría el seguro por el asesor');
      if(/\schecked|aria-pressed="true"|class="[^"]*\b(on|sel|activo)\b/.test(modal))
        fallos.push('seguro: el modal trae una opción ya elegida — en Captura se destaca, no se marca');
      const btn = id => (modal.match(new RegExp('<button[^>]*id="' + id + '"[^>]*>')) || [''])[0];
      if(!/finalizarVenta\(true\)/.test(btn('segSi1'))) fallos.push('seguro: «1 año» no registra la venta CON seguro');
      if(!/finalizarVenta\(true\)/.test(btn('segSi2'))) fallos.push('seguro: «2 años» no registra la venta CON seguro');
      if(!/finalizarVenta\(false\)/.test(btn('segNo'))) fallos.push('seguro: «Sin seguro» no registra la venta sin seguro');
      if(!/class="btn-con-seg"/.test(btn('segSi1')) || modal.indexOf('seg-reco') < 0)
        fallos.push('seguro: «1 año» perdió el destacado (el sólido y «Recomendado»)');
    }
    // Nadie le da el foco por código.
    if(/\$\('seg(Si1|Si2|No)'\)\.focus|getElementById\('seg(Si1|Si2|No)'\)\.focus|\.btn-con-seg[^\n]*\.focus\(/.test(html))
      fallos.push('seguro: el código le da el foco a un botón del seguro — Enter elegiría por el asesor');

    // Un segundo «Agregar» con el modal abierto no pisa la venta pendiente.
    const ent = abrir(true);
    if(!ent.err){
      ent.correr(`irPaso(2); $('serie').value = 'SERIE-UNO'; $('btnAdd').onclick();`);
      const id1 = ent.correr('_pendingVenta && _pendingVenta.id');
      ent.correr(`$('serie').value = 'SERIE-DOS'; $('btnAdd').onclick();`);
      const p = ent.correr('_pendingVenta');
      if(!p || p.id !== id1 || p.serie !== 'SERIE-UNO')
        fallos.push('seguro: un segundo «Agregar» con el modal abierto reemplazó la venta que esperaba respuesta');
      if(ent.correr('items.length') !== 0)
        fallos.push('seguro: abrir el modal ya registró una venta sin que nadie contestara');
    }
  }

  if(fallos.length){
    console.log('captura nombres/seguro: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('captura nombres/seguro: el nombre se traduce solo en pantalla (la venta lleva la del sistema), '
            + 'sin nombres.js no revienta, y el seguro no se elige solo');
})();
