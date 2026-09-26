/* ============================================================
   El tablero cabe en un teléfono — medido en un navegador de verdad
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
  localStorage.setItem('odemas_store', JSON.stringify({store_id:'9999', nombre:'Tienda Prueba',
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
  const h = document.querySelector('header');
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
  console.log('pantalla 390: el tablero cabe a 390 y 360 px, encabezado en una franja, un icono por tarjeta (y el cebo de 520 px se caza)');
}, e => { console.log('pantalla 390: no pudo correr — ' + e.message); process.exit(1); });
