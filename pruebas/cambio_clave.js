/* ============================================================
   Cambiar la contraseña desde el globo de la cuenta (15-oct-2026)
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Nació con la 1610: el gerente perdió la contraseña del correo de la
   tienda, la app no tiene «olvidé mi contraseña» y el correo de Supabase no
   llega a @odemas.com.mx. Ángel pone una provisional por SQL y aquí se
   cambia por la propia.

   Se fija:
     · el botón sale SOLO con sesión de correo (quien entra con su número
       queda como «gerente» igual, y no tiene contraseña que cambiar)
     · corta o distinta en los dos campos -> no llega al servidor
     · la buena llega a updateUser y se dice «Listo»
     · lo que contesta Supabase en inglés se dice en español
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');
const NOMBRES = ['mostrarCambioClave_', 'abrirCambioClave_', 'avisoClave_', 'guardarClave_'];
const trozos = NOMBRES.map(n => {
  const m = html.match(new RegExp('(async )?function ' + n + '\\([\\s\\S]*?\\n\\}'));
  if (!m) {
    console.log('cambio de clave: no encontré ' + n + '() en index.html — ¿se renombró?');
    process.exit(1);
  }
  return m[0];
});

function nodo() {
  const clases = new Set();
  return { value:'', textContent:'', disabled:false, style:{ display:'none' }, focus(){},
           classList:{ toggle(c, on){ on ? clases.add(c) : clases.delete(c); }, contains:c => clases.has(c) } };
}

function montar(sesion, respuesta) {
  const nodos = {};
  const llamadas = [];
  const caja = {
    console,
    document:{ getElementById:id => (nodos[id] = nodos[id] || nodo()) },
    sb:{ auth:{
      getSession: async () => ({ data:{ session: sesion ? { user:{} } : null } }),
      updateUser: async (o) => { llamadas.push(o); return { error: respuesta || null }; },
    } },
  };
  vm.createContext(caja);
  vm.runInContext(trozos.join('\n'), caja, { filename:'index-trozo.js' });
  return { caja, nodos, llamadas, el:id => caja.document.getElementById(id) };
}

let fallos = 0;
function ok(cond, que) { if (!cond) { fallos++; console.log('cambio de clave: FALLA — ' + que); } }

(async () => {
  // 1 · ¿Quién ve el botón?
  let a = montar(false);
  await a.caja.mostrarCambioClave_();
  ok(a.el('btnClave').style.display === 'none', 'entró con su número (sin sesión) y le sale el botón');
  a = montar(true);
  await a.caja.mostrarCambioClave_();
  ok(a.el('btnClave').style.display === '', 'entró con correo y no le sale el botón');

  // 2 · Lo que no debe llegar al servidor
  const CORTA = [['abc', 'abc', 'Mínimo 8'], ['abcdefgh1', 'abcdefgh2', 'no son iguales']];
  for (const [n, o, msg] of CORTA) {
    a = montar(true);
    a.caja.abrirCambioClave_();
    a.el('claveNueva').value = n; a.el('claveOtra').value = o;
    await a.caja.guardarClave_();
    ok(a.llamadas.length === 0, '«' + n + '/' + o + '» llegó al servidor');
    ok(a.el('claveMsg').textContent.includes(msg), '«' + n + '/' + o + '» no dice «' + msg + '»');
  }

  // 3 · La buena
  a = montar(true);
  a.caja.abrirCambioClave_();
  a.el('claveNueva').value = 'PlazaCentral2026'; a.el('claveOtra').value = 'PlazaCentral2026';
  await a.caja.guardarClave_();
  ok(a.llamadas.length === 1 && a.llamadas[0].password === 'PlazaCentral2026', 'la contraseña buena no llegó a updateUser');
  ok(a.el('claveMsg').textContent.startsWith('Listo'), 'no dijo «Listo» al guardar');
  ok(a.el('claveNueva').value === '' && a.el('claveOtra').value === '', 'la contraseña se quedó escrita en pantalla');

  // 4 · Lo que contesta Supabase, en español
  const ERRORES = [
    ['New password should be different from the old password.', 'misma que ya tienes'],
    ['Password should be at least 8 characters.',                'muy débil'],
    ['Password update requires reauthentication.',               'vuelve a entrar'],
    ['Failed to fetch',                                          'Sin señal'],
  ];
  for (const [m, debe] of ERRORES) {
    a = montar(true, { message:m });
    a.caja.abrirCambioClave_();
    a.el('claveNueva').value = 'PlazaCentral2026'; a.el('claveOtra').value = 'PlazaCentral2026';
    await a.caja.guardarClave_();
    ok(a.el('claveMsg').textContent.includes(debe), '«' + m + '» no se tradujo («' + a.el('claveMsg').textContent + '»)');
    ok(!a.el('claveMsg').textContent.startsWith('Listo'), '«' + m + '» se dio por bueno');
  }

  // 5 · La sesión se cerró entre abrir el globo y guardar
  a = montar(false);
  a.caja.abrirCambioClave_();
  a.el('claveNueva').value = 'PlazaCentral2026'; a.el('claveOtra').value = 'PlazaCentral2026';
  await a.caja.guardarClave_();
  ok(a.llamadas.length === 0 && a.el('claveMsg').textContent.includes('sesión se cerró'), 'sin sesión intentó guardar o no lo dijo');

  if (fallos) { console.log(fallos + ' fallo(s)'); process.exit(1); }
  console.log('cambio de clave: solo con sesión de correo, lo corto no sale, la buena se guarda y los errores se dicen en español (13 casos)');
})();
