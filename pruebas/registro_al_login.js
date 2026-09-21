/* ============================================================
   Registrarse termina en «Iniciar sesión», con el aviso a cuestas
   ============================================================
   20-sep-2026. Al registrar la 1217 en esta copia, la pantalla se quedó en el
   formulario ya usado con una nota verde arriba: parecía que faltaba algo por
   llenar ahí mismo, y el sitio al que hay que volver —iniciar sesión— quedaba
   a dos clics y sin decirlo.

   Lo que esta prueba defiende NO es la navegación, que sola sería un cambio de
   pantalla: es que el aviso VIAJE. Con la confirmación de correo encendida la
   tienda todavía NO existe —se crea en el primer inicio de sesión, y solo desde
   ese navegador—, así que mandar a la gente al login sin ese recado cambiaría
   un mensaje mal puesto por una tienda que nunca se crea.

   Y el caso contrario, que es el que se olvida: un registro que FALLA no puede
   navegar a ningún lado. Si se va al login, el error se queda en la pantalla
   que nadie está mirando y la persona no sabe qué corregir.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const { crearEntorno } = require('./dom.js');

const HTML = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

let fallos = 0;
function ok(que, cond){ if(!cond){ console.log('  FALLA · ' + que); fallos++; } }

/* Un registro con los campos llenos, contra un Supabase de mentira.

   `tiendas` decide el escenario: con `rls` puesto se simula la confirmación de
   correo encendida —`signUp` no deja sesión, así que la política rechaza la
   fila— y sin él, el registro que se completa de una vez. */
function registrar(opciones){
  const o = opciones || {};
  const s = crearEntorno({ html: HTML });
  if(s.err) throw new Error('el script de index.html no arrancó: ' + s.err);

  const llamadas = [];
  s.correr('sb = ' + JSON.stringify(null));     // por si initSB dejó algo
  s.caja.__falso = {
    auth:{ signUp: async (args) => {
      llamadas.push('signUp');
      if(o.correoRepetido) return { data:{}, error:{ message:'User already registered' } };
      return { data:{ user:{ id:'u1', email:args.email } }, error:null };
    } },
    from: (tabla) => ({ insert: async () => {
      llamadas.push('insert:' + tabla);
      if(tabla === 'tiendas' && o.rls)
        return { error:{ code:'42501', message:'new row violates row-level security policy' } };
      return { error:null };
    } })
  };
  s.correr('sb = __falso');

  const poner = (id, v) => { s.el(id).value = v; };
  poner('regEmail', o.email || 't9999@ejemplo.mx');
  poner('regPass',  'secreta1'); poner('regPass2', 'secreta1');
  poner('regId', '1217'); poner('regNombre', 'Angelopolis'); poner('regCiudad', 'Puebla');
  poner('regEmpNombre', 'Ana Ramirez Solis'); poner('regEmpNo', '1000001');

  return s.correr('doRegister()').then(() => ({ s, llamadas }));
}

const enLogin   = s => !s.tiene('scLogin', 'hide') && s.tiene('scRegister', 'hide');
const avisoDice = (s, t) => s.tiene('loginOk', 'show') && s.htmlDe('loginOk').indexOf(t) >= 0;

Promise.resolve()

  /* 1 · Confirmación de correo encendida: la cuenta existe, la tienda no.
        Es el caso real del 20-sep y el único en el que queda trabajo pendiente
        fuera de la app. */
  .then(() => registrar({ rls:true }).then(({ s }) => {
    ok('PENDIENTE · acaba en la pantalla de iniciar sesión', enLogin(s));
    ok('PENDIENTE · el aviso dice que hay que confirmar el correo',
       avisoDice(s, 'Confirma tu correo'));
    ok('PENDIENTE · y que tiene que ser en este navegador',
       avisoDice(s, 'desde este mismo navegador'));
    ok('PENDIENTE · el correo queda escrito, no hay que teclearlo otra vez',
       s.el('loginEmail').value === 't9999@ejemplo.mx');
    ok('PENDIENTE · la contraseña NO se arrastra al otro formulario',
       s.el('loginPass').value === '');
    // Lo que hace que la tienda se pueda crear luego: sin esto el aviso miente.
    ok('PENDIENTE · los datos de la tienda quedan guardados en el navegador',
       (s.lsJson('hes_alta_pendiente') || {}).store_id === '1217');
  }))

  /* 2 · Sin confirmación: tienda creada y gerente dado de alta. */
  .then(() => registrar({}).then(({ s, llamadas }) => {
    ok('COMPLETO · acaba en la pantalla de iniciar sesión', enLogin(s));
    ok('COMPLETO · el aviso dice que la tienda quedó registrada',
       avisoDice(s, 'tienda registrada'));
    ok('COMPLETO · se dio de alta al gerente', llamadas.indexOf('insert:empleados') >= 0);
    ok('COMPLETO · no queda alta pendiente', s.lsJson('hes_alta_pendiente') === null);
  }))

  /* 3 · El registro que falla se queda donde está. Navegar aquí escondería el
        error en una pantalla que la persona no está mirando. */
  .then(() => registrar({ correoRepetido:true }).then(({ s }) => {
    ok('CORREO REPETIDO · NO navega al login', !enLogin(s));
    ok('CORREO REPETIDO · el error se ve donde se tecleó',
       s.tiene('regErr', 'show') && s.el('regErr').textContent.indexOf('ya está registrado') >= 0);
    ok('CORREO REPETIDO · y no deja un aviso verde de éxito', !s.tiene('loginOk', 'show'));
  }))

  /* 4 · El aviso es de quien acaba de registrarse, no del siguiente que pase.
        Se limpia al salir de la pantalla. */
  .then(() => registrar({ rls:true }).then(({ s }) => {
    s.correr('sc("pin")');
    ok('DESPUÉS · el aviso no se queda pegado al volver al login',
       !s.tiene('loginOk', 'show') && s.htmlDe('loginOk') === '');
  }))

  .then(() => {
    if(fallos){ console.log('\n' + fallos + ' fallo(s)'); process.exit(1); }
    console.log('registro: termina en iniciar sesión, y el aviso de qué falta viaja con la persona');
  })
  .catch(e => { console.log('  FALLA · ' + e.message); process.exit(1); });
