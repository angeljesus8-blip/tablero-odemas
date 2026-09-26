/* ============================================================
   El tablero y Captura caben en un teléfono — medido en un navegador de verdad
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Las demás pruebas usan un DOM de mentira: ejecutan el código pero no pintan
   nada, así que no pueden ver que un encabezado ocupa tres renglones o que
   una tarjeta se sale de la pantalla. Ésta abre el tablero en Edge sin
   ventana, a 390 px (iPhone) y a 360 px (el Android chico de piso), con la
   misma tienda inventada de `entorno.js` —el repo es público—, y MIDE.

   Nació con el rediseño visual del 22-sep-2026. Lo que se mide es lo que
   Ángel señaló como "no se ve profesional", en términos que se pueden contar:

     1. Nada se sale a lo ancho. Un desborde obliga a arrastrar la pantalla de
        lado con un cliente enfrente.
     2. El encabezado cabe en una franja (≤ 76 px). Medía 130: tres renglones
        para decir "Tablero del Equipo · Live 02:25 p.m. · en vivo".
     3. Cada tarjeta del inicio lleva UN icono. Llevaban dos emojis distintos
        (🔥 al lado y 💰 en el título).

   Y se prueba a sí misma en cada corrida: mete un cebo de 520 px y exige que
   el punto 1 lo cace. Una prueba de desborde que no ve un desborde puesto a
   propósito no vigila nada.

   CAPTURA DE SERIES (22-sep-2026, fase 4): lo mismo en sus cinco momentos
   —¿quién eres?, paso 1, paso 2, el modal del seguro y la lista con una
   venta—, y además lo único que solo se puede probar con un teclado y un
   dedo de verdad: que el seguro NO SE ELIGE SOLO. En Captura el toque es el
   registro (va al Assurant attach), así que con el modal abierto:
     4. nada tiene el foco (un Enter elegiría por el asesor);
     5. Enter no registra nada, ni desde el cuerpo ni desde el campo de serie;
     6. tocar fuera del modal no registra nada;
     7. y un toque real sobre «1 año» SÍ registra la venta con seguro — si
        esto fallara, las tres de arriba pasarían por no funcionar nada.

   HORARIOS (22-sep-2026, fase 5): la semana del asesor y la del gerente a
   390 y 360 px, con un equipo inventado. Antes del rediseño la página medía
   413 px de ancho en un celular de 390: la navegación de semana se salía.

   COMISIONES Y ADMIN (22-sep-2026, fase 6): Comisiones con tres personas
   inventadas, y Admin pestaña por pestaña, a 390 y 360 px. Admin se mide
   también a 1280: es donde se pega lo de Sonar con Ctrl+V.

   MENÚ Y LA PÁGINA RETIRADA (22-sep-2026): el menú con sesión (su
   encabezado medía 89 px) y en el teclado de entrada, y actualizar_datos.html,
   que quedó como aviso. (En la 1217 mide además la consulta de los técnicos de
   Mr Fix, que en esta copia no existe.)

   Sin dependencias: Edge viene con Windows y Node 22+ trae WebSocket. Si no
   hay Edge (otra máquina), avisa y no bloquea — igual que `node` en
   verificar.py.

   Uso:  node pruebas/pantalla_390.js            (prueba)
         node pruebas/pantalla_390.js --fotos DIR (además guarda capturas)
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), http = require('http'),
      os = require('os'), { spawn } = require('child_process');
const { TIENDA } = require('./entorno.js');

const RAIZ = path.join(__dirname, '..');
const FOTOS = (i => i > 0 ? process.argv[i + 1] : null)(process.argv.indexOf('--fotos'));
const ANCHOS = [390, 360];
const SECCIONES = ['inicio', 'promo', 'apartados', 'eol', 'resurtir'];
// Los momentos de Captura, con lo que hay que hacer para llegar a cada uno.
const CAPTURA = [
  ['quien',  'showGate()'],
  ['paso1',  'hideGate(); irPaso(1)'],
  ['paso2',  "irPaso(2); aplicarProducto({ s:'100245689', d:'AUDIF IN EAR HW F-BUDS PRO 4 VD' }); $('serie').value = 'ABCDE12345678901'"],
  ['seguro', "$('btnAdd').click()"],
];
// Un equipo inventado para el horario (el repo es público).
const EQUIPO_H = { horaApertura:10, horaCierre:21,
  gerentes:[{ key:'G1', nombre:'ANA GERENTE', cargo:'Gerente de Tienda', emp:'900001', descFijo:5 },
            { key:'G2', nombre:'BENI SUBGER', cargo:'Subgerente', emp:'900002', descFijo:4 }],
  asesores:[{ key:'A1', nombre:'CARO ASESORA', cargo:'Asesor', emp:'900003', descFijo:3 },
            { key:'A2', nombre:'DANI ASESOR', cargo:'Asesor', emp:'900004', descFijo:1 }] };
// Las de ESTA copia: sin Preventa por archivo, Concurso ni Config (esas son de la 1217).
const PESTANAS_ADMIN = ['cat', 'promos', 'eol', 'avisos', 'comis', 'equipo'];
const COMIS_FALSAS = [
  { nombre:'ANA GERENTE', puesto:'Gerente de Tienda', venta:412345.5, alcance:104, pptoPct:98,
    garantiaPct:28, garantiaPzas:14, garantiaElegible:50, garantiaMonto:18990 },
  { nombre:'CARO ASESORA', puesto:'Asesor', venta:233100, alcance:81, pptoPct:77,
    garantiaPct:19, garantiaPzas:6, garantiaElegible:31, garantiaMonto:7120 }];
const ALTO_ENCABEZADO = 76;

const EDGE = [
  process.env['ProgramFiles(x86)'] && path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'),
  process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Microsoft/Edge/Application/msedge.exe'),
  process.env.ProgramFiles && path.join(process.env.ProgramFiles, 'Google/Chrome/Application/chrome.exe'),
].filter(p => p && fs.existsSync(p))[0];

if(!EDGE){
  console.log('pantalla 390: AVISO — no hay Edge ni Chrome en esta máquina; no se midió');
  process.exit(0);
}

const fallos = [];
const falla = m => fallos.push(m);

// ── Servidor de archivos del repo, solo para esta prueba ──
const TIPOS = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8',
  '.css':'text/css; charset=utf-8', '.png':'image/png', '.jpg':'image/jpeg',
  '.json':'application/json', '.woff2':'font/woff2', '.ttf':'font/ttf' };
const servidor = http.createServer((req, res) => {
  const rel = decodeURIComponent(req.url.split('?')[0]).replace(/^\/+/, '') || 'index.html';
  const f = path.join(RAIZ, rel);
  if(!f.startsWith(RAIZ) || !fs.existsSync(f) || fs.statSync(f).isDirectory()){
    res.writeHead(404); return res.end();
  }
  res.writeHead(200, { 'Content-Type': TIPOS[path.extname(f).toLowerCase()] || 'application/octet-stream' });
  fs.createReadStream(f).pipe(res);
});

// ── CDP mínimo ──
function cdp(url){
  const ws = new WebSocket(url);
  let id = 0; const pend = new Map();
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if(m.id && pend.has(m.id)){
      const { ok, ko } = pend.get(m.id); pend.delete(m.id);
      m.error ? ko(new Error(m.error.message)) : ok(m.result);
    }
  };
  const abierto = new Promise((ok, ko) => { ws.onopen = ok; ws.onerror = ko; });
  return {
    abierto, cerrar: () => ws.close(),
    enviar(method, params = {}, sessionId){
      const i = ++id;
      ws.send(JSON.stringify({ id:i, method, params, sessionId }));
      return new Promise((ok, ko) => {
        pend.set(i, { ok, ko });
        setTimeout(() => pend.has(i) && (pend.delete(i), ko(new Error('sin respuesta: ' + method))), 20000);
      });
    },
  };
}
const dormir = ms => new Promise(r => setTimeout(r, ms));

// Lo que corre DENTRO de la página antes de su propio JavaScript: una sesión
// de gerente inventada, sin red (el tablero cae a lo que se le dé a mano) y
// sin service worker (guardaría esta versión en caché de Edge).
const PREPARAR = `
  // Captura arranca en blanco en cada carga: sin las ventas de la corrida anterior.
  localStorage.removeItem('odemas_series_v1'); localStorage.removeItem('odemas_captura_borrador');
  localStorage.setItem('odemas_store', JSON.stringify({store_id:'9999', nombre:'Tienda Prueba',
    vendedores:['Prueba Uno', 'Prueba Dos'],
    ciudad:'Prueba', gas_token:'prueba'}));
  localStorage.setItem('odemas_empleado', JSON.stringify({empno:'1', nombre:'Prueba Uno',
    puesto:'Gerente de Tienda'}));
  window.fetch = () => Promise.reject(new Error('sin red en las pruebas'));
  // Uno de mentira, no undefined: el tablero pregunta 'serviceWorker' in
  // navigator y, con la propiedad presente pero vacía, revienta al usarla.
  try { Object.defineProperty(navigator, 'serviceWorker', { value: {
    addEventListener(){}, register: () => new Promise(() => {}), ready: new Promise(() => {}),
    getRegistrations: async () => [], controller: null } }); } catch(e){}
`;

// Mide lo que se sale a lo ancho. Un elemento dentro de un carrusel
// (overflow-x auto/scroll/hidden) no cuenta: está hecho para desplazarse.
const MEDIR = `(() => {
  const W = document.documentElement.clientWidth;
  const dentroDeCarrusel = el => { for(let p = el.parentElement; p; p = p.parentElement){
    const o = getComputedStyle(p).overflowX; if(o !== 'visible') return true; } return false; };
  const fuera = [];
  for(const el of document.body.querySelectorAll('*')){
    const r = el.getBoundingClientRect();
    if(!r.width || !r.height || getComputedStyle(el).position === 'fixed') continue;
    if(r.right > W + 1 && !dentroDeCarrusel(el)){
      fuera.push((el.id ? '#' + el.id : el.tagName.toLowerCase() + (el.className && typeof el.className === 'string'
        ? '.' + el.className.trim().split(/\\s+/)[0] : '')) + ' (' + Math.round(r.right - W) + ' px)');
    }
  }
  // El encabezado VISIBLE: Captura trae dos (el de «¿quién eres?» y el suyo).
  const h = [...document.querySelectorAll('header')].find(x => x.getBoundingClientRect().height);
  return { ancho: document.documentElement.scrollWidth, W, fuera: fuera.slice(0, 5), nFuera: fuera.length,
           encabezado: h ? Math.round(h.getBoundingClientRect().height) : null };
})()`;

async function main(){
  await new Promise(r => servidor.listen(0, '127.0.0.1', r));
  const puerto = servidor.address().port;
  const perfil = fs.mkdtempSync(path.join(os.tmpdir(), 'hes390-'));
  const edge = spawn(EDGE, ['--headless=new', '--remote-debugging-port=0', '--no-first-run',
    '--no-default-browser-check', '--disable-extensions', '--user-data-dir=' + perfil, 'about:blank'],
    { stdio: 'ignore' });

  let wsUrl = null;
  for(let i = 0; i < 100 && !wsUrl; i++){
    await dormir(100);
    try {
      const [p, ruta] = fs.readFileSync(path.join(perfil, 'DevToolsActivePort'), 'utf8').trim().split('\n');
      wsUrl = 'ws://127.0.0.1:' + p + ruta;
    } catch(e){}
  }
  if(!wsUrl){ edge.kill(); throw new Error('Edge no abrió el puerto de depuración'); }

  const b = cdp(wsUrl); await b.abierto;
  const { targetId } = await b.enviar('Target.createTarget', { url: 'about:blank' });
  const { sessionId: s } = await b.enviar('Target.attachToTarget', { targetId, flatten: true });
  const ev = (expr) => b.enviar('Runtime.evaluate', { expression: expr, returnByValue: true, awaitPromise: true }, s)
    .then(r => { if(r.exceptionDetails) throw new Error(r.exceptionDetails.exception?.description || r.exceptionDetails.text); return r.result.value; });

  await b.enviar('Page.enable', {}, s);
  await b.enviar('Page.addScriptToEvaluateOnNewDocument', { source: PREPARAR }, s);

  try {
    for(const W of ANCHOS){
      await b.enviar('Emulation.setDeviceMetricsOverride',
        { width: W, height: 844, deviceScaleFactor: 2, mobile: true }, s);
      await b.enviar('Page.navigate', { url: `http://127.0.0.1:${puerto}/tablero.html` }, s);
      for(let i = 0; i < 50; i++){
        await dormir(100);
        if(await ev(`document.readyState === 'complete' && typeof aplicarTodo === 'function'`).catch(() => false)) break;
      }
      await ev(`document.fonts.ready.then(() => true)`);
      await ev(`aplicarTodo(Object.assign(_deSupabase(${JSON.stringify(TIENDA)}), { __sb:true })); true`);

      for(const sec of SECCIONES){
        await ev(`filtroActivo = ${JSON.stringify(sec)}; busqueda = ''; render(); scrollTo(0,0); true`);
        await dormir(150);
        const m = await ev(MEDIR);
        const donde = `${sec} a ${W}px`;
        if(m.ancho > m.W + 1) falla(`${donde}: la página mide ${m.ancho} px de ancho en una pantalla de ${m.W}`);
        if(m.nFuera) falla(`${donde}: ${m.nFuera} elemento(s) se salen de la pantalla — ${m.fuera.join(', ')}`);
        if(m.encabezado > ALTO_ENCABEZADO)
          falla(`${donde}: el encabezado mide ${m.encabezado} px (tope ${ALTO_ENCABEZADO}); se parte en renglones`);

        if(sec === 'inicio'){
          const dobles = await ev(`[...document.querySelectorAll('.ir-card .ir-txt b')]
            .map(e => e.textContent.trim()).filter(t => /\\p{Extended_Pictographic}/u.test(t))`);
          if(dobles.length) falla(`inicio a ${W}px: tarjetas con un segundo icono en el título — ${dobles.join(' · ')}`);
        }
        if(FOTOS){
          fs.mkdirSync(FOTOS, { recursive: true });
          const alto = await ev(`Math.min(document.documentElement.scrollHeight, 2400)`);
          await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: alto, deviceScaleFactor: 2, mobile: true }, s);
          const { data } = await b.enviar('Page.captureScreenshot', { format: 'png' }, s);
          fs.writeFileSync(path.join(FOTOS, `tablero_${sec}_${W}.png`), Buffer.from(data, 'base64'));
          await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: 844, deviceScaleFactor: 2, mobile: true }, s);
        }
      }

      // El cebo: si esto no se caza, la prueba de desborde está ciega.
      const cebo = await ev(`(() => { const d = document.createElement('div'); d.style.cssText = 'width:520px;height:10px';
        document.getElementById('app').appendChild(d); const m = ${MEDIR}; d.remove(); return m.nFuera; })()`);
      if(!cebo) falla(`a ${W}px: se metió un bloque de 520 px y la prueba no lo vio — está ciega`);
    }

    // ── Captura de Series ──
    const foto = async (nombre, W) => {
      if(!FOTOS) return;
      fs.mkdirSync(FOTOS, { recursive: true });
      const { data } = await b.enviar('Page.captureScreenshot', { format: 'png' }, s);
      fs.writeFileSync(path.join(FOTOS, `captura_${nombre}_${W}.png`), Buffer.from(data, 'base64'));
    };
    const tecla = async (key, code, texto) => {
      for(const type of ['keyDown', 'keyUp'])
        await b.enviar('Input.dispatchKeyEvent', { type, key, code, windowsVirtualKeyCode: 13,
          text: type === 'keyDown' ? texto : undefined }, s);
      await dormir(150);
    };
    const toque = async (x, y) => {
      for(const type of ['mousePressed', 'mouseReleased'])
        await b.enviar('Input.dispatchMouseEvent', { type, x, y, button: 'left', clickCount: 1 }, s);
      await dormir(200);
    };
    for(const W of ANCHOS){
      await b.enviar('Emulation.setDeviceMetricsOverride',
        { width: W, height: 844, deviceScaleFactor: 2, mobile: true }, s);
      await b.enviar('Page.navigate', { url: `http://127.0.0.1:${puerto}/captura_series.html` }, s);
      for(let i = 0; i < 50; i++){
        await dormir(100);
        if(await ev(`document.readyState === 'complete' && typeof irPaso === 'function'`).catch(() => false)) break;
      }
      await ev(`document.fonts.ready.then(() => true)`);

      for(const [momento, llegar] of CAPTURA){
        await ev(`${llegar}; scrollTo(0,0); true`);
        await dormir(250);
        const m = await ev(MEDIR);
        const donde = `captura ${momento} a ${W}px`;
        if(m.ancho > m.W + 1) falla(`${donde}: la página mide ${m.ancho} px de ancho en una pantalla de ${m.W}`);
        if(m.nFuera) falla(`${donde}: ${m.nFuera} elemento(s) se salen de la pantalla — ${m.fuera.join(', ')}`);
        if(m.encabezado == null) falla(`${donde}: no hay encabezado visible`);
        else if(m.encabezado > ALTO_ENCABEZADO)
          falla(`${donde}: el encabezado mide ${m.encabezado} px (tope ${ALTO_ENCABEZADO}); se parte en renglones`);
        await foto(momento, W);
      }

      // El seguro, con el modal abierto (el último momento de CAPTURA).
      const estado = () => ev(`({ abierto: $('modalSeguro').classList.contains('show'), n: items.length,
        foco: document.activeElement ? (document.activeElement.id || document.activeElement.tagName) : '',
        pend: _pendingVenta && _pendingVenta.serie })`);
      let e0 = await estado();
      if(!e0.abierto) falla(`captura a ${W}px: «Agregar» no abrió el modal del seguro`);
      else {
        if(e0.foco !== 'BODY')
          falla(`captura a ${W}px: al abrir el seguro el foco queda en «${e0.foco}» — un Enter elegiría por el asesor`);
        await tecla('Enter', 'Enter', '\r');
        let e = await estado();
        if(!e.abierto || e.n !== e0.n) falla(`captura a ${W}px: Enter con el modal abierto registró la venta (el seguro se eligió solo)`);
        // Desde el campo de serie, que es donde estaba el Enter que abrió el modal.
        await ev(`$('serie').focus(); true`);
        await tecla('Enter', 'Enter', '\r');
        e = await estado();
        if(!e.abierto || e.n !== e0.n || e.pend !== e0.pend)
          falla(`captura a ${W}px: Enter en el campo de serie con el modal abierto registró o pisó la venta`);
        await ev(`document.activeElement && document.activeElement.blur(); true`);
        await toque(6, 6);   // fuera de la caja del modal, sobre el velo
        e = await estado();
        if(!e.abierto || e.n !== e0.n) falla(`captura a ${W}px: tocar fuera del modal registró la venta`);
        // Y el toque de verdad sobre «1 año» sí registra, con seguro.
        const r = await ev(`(() => { const r = $('segSi1').getBoundingClientRect();
          return { x: r.left + r.width / 2, y: r.top + r.height / 2 }; })()`);
        await toque(r.x, r.y);
        e = await estado();
        const ult = await ev(`items[0] ? { seguro: items[0].seguro, desc: items[0].desc } : null`);
        if(e.abierto || e.n !== e0.n + 1 || !ult || ult.seguro !== true)
          falla(`captura a ${W}px: un toque real sobre «1 año» no registró la venta con seguro`);
        else if(ult.desc !== 'AUDIF IN EAR HW F-BUDS PRO 4 VD')
          falla(`captura a ${W}px: la venta se guardó con «${ult.desc}» y no con la descripción del sistema`);
      }

      // La lista con la venta recién hecha.
      await ev(`scrollTo(0,0); true`); await dormir(250);
      const m = await ev(MEDIR);
      if(m.nFuera) falla(`captura lista a ${W}px: ${m.nFuera} elemento(s) se salen — ${m.fuera.join(', ')}`);
      await foto('lista', W);

      const cebo = await ev(`(() => { const d = document.createElement('div'); d.style.cssText = 'width:520px;height:10px';
        document.querySelector('main').appendChild(d); const m = ${MEDIR}; d.remove(); return m.nFuera; })()`);
      if(!cebo) falla(`captura a ${W}px: se metió un bloque de 520 px y la prueba no lo vio — está ciega`);
    }

    // ── Horarios ──
    for(const W of ANCHOS){
      for(const [quien, emp] of [['asesor', { empno:'900003', puesto:'Asesor' }],
                                 ['gerente', { empno:'900001', puesto:'Gerente de Tienda' }]]){
        await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: 844, deviceScaleFactor: 2, mobile: true }, s);
        await b.enviar('Page.navigate', { url: `http://127.0.0.1:${puerto}/horarios.html` }, s);
        for(let i = 0; i < 60; i++){
          await dormir(100);
          if(await ev(`document.readyState === 'complete' && typeof generarSemana === 'function'`).catch(() => false)) break;
        }
        await ev(`document.fonts.ready.then(() => true)`);
        // Se pinta con la cadena real (la de horario_solo_mio.js) y se quitan
        // la carga y el login, que sin red se quedarían encima.
        await ev(`(() => { aplicarEquipo(${JSON.stringify(EQUIPO_H)});
          fijarSesion({ store_id:'9999', nombre:'Tienda Prueba' }, ${JSON.stringify(emp)});
          const _d = generarSemana(_semana, null, null); renderTabla(_semana, _domingo, _d, calcularComidas(_d));
          ['cargando', 'overlay-login'].forEach(i => { const e = document.getElementById(i); if(e){ e.classList.remove('activo'); e.style.display = 'none'; } });
          if(/Gerente/.test(${JSON.stringify(emp.puesto)})) document.getElementById('barra-usuario').classList.add('activo');
          mostrarVolverAlMenu(); scrollTo(0,0); return true; })()`);
        await dormir(250);
        const m = await ev(MEDIR);
        const donde = `horario ${quien} a ${W}px`;
        if(m.ancho > m.W + 1) falla(`${donde}: la página mide ${m.ancho} px de ancho en una pantalla de ${m.W}`);
        if(m.nFuera) falla(`${donde}: ${m.nFuera} elemento(s) se salen de la pantalla — ${m.fuera.join(', ')}`);
        if(m.encabezado == null) falla(`${donde}: no hay encabezado visible`);
        else if(m.encabezado > ALTO_ENCABEZADO)
          falla(`${donde}: el encabezado mide ${m.encabezado} px (tope ${ALTO_ENCABEZADO}); se parte en renglones`);
        if(FOTOS){
          fs.mkdirSync(FOTOS, { recursive: true });
          const alto = await ev(`Math.min(document.documentElement.scrollHeight, 3000)`);
          await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: alto, deviceScaleFactor: 2, mobile: true }, s);
          const { data } = await b.enviar('Page.captureScreenshot', { format: 'png' }, s);
          fs.writeFileSync(path.join(FOTOS, `horario_${quien}_${W}.png`), Buffer.from(data, 'base64'));
        }
      }
      const cebo = await ev(`(() => { const d = document.createElement('div'); d.style.cssText = 'width:520px;height:10px';
        document.body.appendChild(d); const m = ${MEDIR}; d.remove(); return m.nFuera; })()`);
      if(!cebo) falla(`horario a ${W}px: se metió un bloque de 520 px y la prueba no lo vio — está ciega`);
    }

    // ── Comisiones y Admin ──
    const medir = async (donde, archivoFoto, W, alto) => {
      const m = await ev(MEDIR);
      if(m.ancho > m.W + 1) falla(`${donde}: la página mide ${m.ancho} px de ancho en una pantalla de ${m.W}`);
      if(m.nFuera) falla(`${donde}: ${m.nFuera} elemento(s) se salen de la pantalla — ${m.fuera.join(', ')}`);
      if(m.encabezado == null) falla(`${donde}: no hay encabezado visible`);
      else if(m.encabezado > ALTO_ENCABEZADO)
        falla(`${donde}: el encabezado mide ${m.encabezado} px (tope ${ALTO_ENCABEZADO}); se parte en renglones`);
      if(FOTOS){
        fs.mkdirSync(FOTOS, { recursive: true });
        const h = await ev(`Math.min(document.documentElement.scrollHeight, 2600)`);
        await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: h, deviceScaleFactor: W > 700 ? 1 : 2, mobile: W < 700 }, s);
        const { data } = await b.enviar('Page.captureScreenshot', { format: 'png' }, s);
        fs.writeFileSync(path.join(FOTOS, archivoFoto), Buffer.from(data, 'base64'));
        await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: alto, deviceScaleFactor: W > 700 ? 1 : 2, mobile: W < 700 }, s);
      }
    };
    const abrir = async (pagina, W, alto, listo) => {
      await b.enviar('Emulation.setDeviceMetricsOverride', { width: W, height: alto, deviceScaleFactor: W > 700 ? 1 : 2, mobile: W < 700 }, s);
      await b.enviar('Page.navigate', { url: `http://127.0.0.1:${puerto}/${pagina}` }, s);
      for(let i = 0; i < 60; i++){
        await dormir(100);
        if(await ev(`document.readyState === 'complete' && typeof ${listo} === 'function'`).catch(() => false)) break;
      }
      await ev(`document.fonts.ready.then(() => true)`);
    };
    for(const W of ANCHOS){
      await abrir('comisiones.html', W, 844, 'cardEmpleado');
      // Las tarjetas con la función real; la lectura de la base no corre sin red.
      await ev(`(() => { document.getElementById('app').innerHTML = ${JSON.stringify(COMIS_FALSAS)}.map(cardEmpleado).join(''); scrollTo(0,0); return true; })()`);
      await dormir(200);
      await medir(`comisiones a ${W}px`, `comisiones_${W}.png`, W, 844);
    }
    for(const W of ANCHOS.concat([1280])){
      const alto = W > 700 ? 900 : 844;
      await abrir('admin.html', W, alto, 'abrirAdmin');
      await ev(`(() => { abrirAdmin(); return true; })()`);
      for(const t of PESTANAS_ADMIN){
        await ev(`(() => { const bt = [...document.querySelectorAll('.tab-bar button')]
          .find(x => (x.getAttribute('onclick') || '').indexOf("tab('${t}'") >= 0);
          tab('${t}', bt); scrollTo(0,0); return true; })()`);
        await dormir(200);
        await medir(`admin ${t} a ${W}px`, `admin_${t}_${W}.png`, W, alto);
      }
      if(W < 700){
        const cebo = await ev(`(() => { const d = document.createElement('div'); d.style.cssText = 'width:520px;height:10px';
          document.querySelector('.pane.on').appendChild(d); const m = ${MEDIR}; d.remove(); return m.nFuera; })()`);
        if(!cebo) falla(`admin a ${W}px: se metió un bloque de 520 px y la prueba no lo vio — está ciega`);
      }
    }

    // ── Menú, técnico y la página retirada ──
    for(const W of ANCHOS){
      await abrir('index.html', W, 844, 'applyStoreConfig');
      await ev(`(() => { applyStoreConfig({ store_id:'9999', nombre:'Tienda Prueba con nombre largo', ciudad:'Prueba' }, 'gerente');
        sc('menu'); scrollTo(0,0); return true; })()`);
      await dormir(200);
      await medir(`menú a ${W}px`, `menu_${W}.png`, W, 844);
      const halos = await ev(`new Set([...document.querySelectorAll('.tile .ic')].map(e => getComputedStyle(e).backgroundColor)).size`);
      if(halos > 1) falla(`menú a ${W}px: los iconos llevan ${halos} fondos distintos; es uno solo (--mosaico)`);
      // El teclado de entrada no tiene encabezado: solo se mide el ancho.
      await ev(`(() => { sc('pin'); return true; })()`); await dormir(150);
      const mp = await ev(MEDIR);
      if(mp.ancho > mp.W + 1 || mp.nFuera) falla(`entrada del menú a ${W}px: algo se sale de la pantalla — ${mp.fuera.join(', ')}`);
      for(const [pagina, listo, foto] of [['actualizar_datos.html', 'Object', 'actualizar_retirada']]){
        await abrir(pagina, W, 844, listo);
        await medir(`${foto} a ${W}px`, `${foto}_${W}.png`, W, 844);
      }
      const hayVolver = await ev(`!!document.querySelector('.barra-volver')`);
      if(!hayVolver) falla(`actualizar_datos a ${W}px: la página retirada perdió el «‹» al menú`);
    }
  } finally {
    b.cerrar(); edge.kill(); servidor.close();
    await dormir(300);
    try { fs.rmSync(perfil, { recursive: true, force: true }); } catch(e){}
  }
}

main().then(() => {
  if(fallos.length){
    console.log('pantalla 390: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('pantalla 390: el tablero, Captura, Horarios, Comisiones, Admin, el menú y la página retirada caben a 390 y 360 px, encabezado en una franja, un icono por tarjeta, el seguro no se elige solo con Enter ni tocando fuera (y el cebo de 520 px se caza)');
}, e => { console.log('pantalla 390: no pudo correr — ' + e.message); process.exit(1); });
