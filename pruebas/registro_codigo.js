/* ============================================================
   Registrar una tienda: del formulario a estar dentro
   ============================================================
   20-sep-2026. El registro terminaba con una nota verde sobre el formulario ya
   usado y un enlace en el correo. Las dos cosas fallaron el mismo día al dar de
   alta la 1217:

     · el enlace llegó reescrito por el filtro corporativo
       (`urlwatch.com/urlwatch?b=<base64>`) y murió con ERR_CONNECTION_RESET;
     · y aunque hubiera abierto, obliga a volver en el MISMO navegador, porque
       hasta ese momento la tienda solo existe en su `localStorage`.

   Con una tienda es un rodeo. Con la red entera registrándose es el primer día
   de cada gerente, y nadie llama para decir que no le llegó: se cae.

   Lo que se prueba aquí es la cadena de punta a punta —registro, código,
   sesión, tienda creada, dentro— y sobre todo los puntos donde antes se perdía
   gente sin que nada diera error.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const { crearEntorno } = require('./dom.js');

const HTML = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

let fallos = 0;
function ok(que, cond){ if(!cond){ console.log('  FALLA · ' + que); fallos++; } }

const CORREO = 't9999@ejemplo.mx';

/* Supabase de mentira, con lo justo que toca este camino.

   `rls` simula la confirmación de correo ENCENDIDA: `signUp` no deja sesión, y
   sin sesión la política de `tiendas` rechaza la fila. Es el escenario real.  */
function clienteFalso(o, llamadas){
  /* Antes de confirmar NO hay sesión, y esa es justo la razón de que la
     política rechace la fila. Si el falso dejara insertar siempre, la prueba
     diría que todo va bien con el agujero delante. */
  let haySesion = !!o.sinConfirmacion;
  const filaTienda = o.tienda === undefined
    ? { store_id:'1217', nombre:'Angelopolis', ciudad:'Puebla',
        gas_token:'tok', hoja_auth:'', vendedores:[] }
    : o.tienda;
  const cadena = {
    select(){ return cadena; },
    eq(){ return cadena; },
    order(){ return Promise.resolve({ data:o.equipo || [], error:null }); },
    maybeSingle(){ return Promise.resolve({ data:filaTienda, error:null }); }
  };
  return {
    auth:{
      signUp: async (args) => {
        llamadas.push('signUp');
        if(o.correoRepetido) return { data:{}, error:{ message:'User already registered' } };
        return { data:{ user:{ id:'u1', email:args.email },
                        session: o.sinConfirmacion ? { access_token:'t' } : null },
                 error:null };
      },
      verifyOtp: async (args) => {
        llamadas.push('verifyOtp:' + args.type + ':' + args.token + ':' + args.email);
        if(o.codigoMalo) return { data:{}, error:{ message:'Token has expired or is invalid' } };
        haySesion = true;
        return { data:{ user:{ id:'u1', email:args.email }, session:{ access_token:'t' } }, error:null };
      },
      resend: async () => {
        llamadas.push('resend');
        return o.limite ? { error:{ message:'For security purposes, you can only request this after 47 seconds' } }
                        : { error:null };
      },
      getSession: async () => ({ data:{ session:null } }),
      signOut: async () => ({})
    },
    from: (tabla) => Object.assign({
      insert: async () => {
        llamadas.push('insert:' + tabla);
        if(tabla === 'tiendas' && o.rls && !haySesion)
          return { error:{ code:'42501', message:'new row violates row-level security policy' } };
        return { error:null };
      }
    }, cadena),
    rpc: async (fn) => { llamadas.push('rpc:' + fn); return { data:null, error:null }; }
  };
}

function arrancar(o){
  const s = crearEntorno({ html: HTML });
  if(s.err) throw new Error('el script de index.html no arrancó: ' + s.err);
  const llamadas = [];
  s.caja.__falso = clienteFalso(o || {}, llamadas);
  s.correr('sb = __falso');
  /* `sc` es el único que cambia de pantalla, así que se le pregunta a él. Mirar
     las clases del HTML no sirve: el DOM de pruebas arranca sin ninguna, y
     «no tiene hide» se leería como «está a la vista» aunque nadie navegara. */
  s.correr('__pantalla = null; sc = (function(orig){ return function(n){ __pantalla = n; return orig(n); }; })(sc);');
  return { s, llamadas, pantalla: () => s.correr('__pantalla') };
}

function registrar(o){
  const { s, llamadas, pantalla } = arrancar(o);
  const poner = (id, v) => { s.el(id).value = v; };
  poner('regEmail', CORREO);
  poner('regPass',  'secreta1'); poner('regPass2', 'secreta1');
  poner('regId', '1217'); poner('regNombre', 'Angelopolis'); poner('regCiudad', 'Puebla');
  poner('regEmpNombre', 'Ana Ramirez Solis'); poner('regEmpNo', '1000001');
  return s.correr('doRegister()').then(() => ({ s, llamadas, pantalla }));
}

const dentro = s => s.el('mainMenu').style.display === 'block';

Promise.resolve()

  /* 1 · El caso real: cuenta creada, tienda todavía no. Antes acababa en una
        nota verde; ahora pide el código, que es lo único que falta. */
  .then(() => registrar({ rls:true }).then(({ s, pantalla }) => {
    ok('PIDE CÓDIGO · lleva a la pantalla del código',
       pantalla() === 'codigo' && !s.tiene('scCodigo', 'hide'));
    ok('PIDE CÓDIGO · se queda claro a qué correo se mandó',
       s.htmlDe('codSub').indexOf(CORREO) >= 0);
    ok('PIDE CÓDIGO · no deja el formulario de registro encima',
       s.tiene('scRegister', 'hide'));
    // Sin esto el aviso mentiría: la tienda se crea al confirmar, no antes.
    ok('PIDE CÓDIGO · los datos de la tienda quedan guardados',
       (s.lsJson('hes_alta_pendiente') || {}).store_id === '1217');
  }))

  /* 2 · El código correcto tiene que dejar a la persona DENTRO, no devolverla
        al formulario de siempre. Es el «y listo» que faltaba. */
  .then(() => registrar({ rls:false }).then(({ s, llamadas }) => {
    s.el('codInp').value = '123456';
    return s.correr('doVerificarCodigo()').then(() => {
      ok('CÓDIGO BUENO · se valida el del alta, no otro tipo',
         llamadas.some(l => l.indexOf('verifyOtp:signup:123456:' + CORREO) === 0));
      ok('CÓDIGO BUENO · entra al menú', dentro(s));
      ok('CÓDIGO BUENO · queda la sesión de gerente guardada',
         s.LS['odemas_role'] === 'gerente' &&
         (s.lsJson('odemas_store') || {}).store_id === '1217');
    });
  }))

  /* 3 · Y si la tienda se quedó pendiente, el código es el momento en que se
        crea: es la razón de que este camino exista. */
  .then(() => registrar({ rls:true }).then(({ s, llamadas }) => {
    s.el('codInp').value = '654321';
    return s.correr('doVerificarCodigo()').then(() => {
      ok('PENDIENTE · al confirmar se crea la tienda',
         llamadas.filter(l => l === 'insert:tiendas').length >= 2);
      ok('PENDIENTE · y se da de alta al gerente',
         llamadas.indexOf('insert:empleados') >= 0);
      ok('PENDIENTE · ya no queda nada pendiente en el navegador',
         s.lsJson('hes_alta_pendiente') === null);
      ok('PENDIENTE · y entra', dentro(s));
    });
  }))

  /* 4 · Un código que no vale se dice en la pantalla del código, y NO se entra.
        Antes de esto, un error aquí era una pantalla en blanco. */
  .then(() => registrar({ rls:true, codigoMalo:true }).then(({ s }) => {
    s.el('codInp').value = '000000';
    return s.correr('doVerificarCodigo()').then(() => {
      ok('CÓDIGO MALO · no entra', !dentro(s));
      ok('CÓDIGO MALO · lo dice donde se tecleó, y en cristiano',
         s.tiene('codErr', 'show') &&
         s.el('codErr').textContent.indexOf('no es válido o ya venció') >= 0);
    });
  }))

  /* 5 · Medio código no se manda al servidor: gastaría un intento y devolvería
        «inválido», que manda a pedir otro código sin necesidad. */
  .then(() => registrar({ rls:true }).then(({ s, llamadas }) => {
    const antes = llamadas.length;
    s.el('codInp').value = '123';
    return s.correr('doVerificarCodigo()').then(() => {
      ok('CÓDIGO CORTO · ni se intenta', llamadas.length === antes);
      ok('CÓDIGO CORTO · se dice cuántos dígitos son',
         s.el('codErr').textContent.indexOf('6 dígitos') >= 0);
    });
  }))

  /* 6 · Reenviar, con el límite del correo de fábrica dicho como lo que es.
        Sin esto se aprieta diez veces creyendo que no funciona. */
  .then(() => registrar({ rls:true, limite:true }).then(({ s, llamadas }) => {
    return s.correr('doReenviarCodigo()').then(() => {
      ok('REENVÍO · se pide otro código', llamadas.indexOf('resend') >= 0);
      ok('REENVÍO · el límite se explica, no se suelta el error crudo',
         s.el('codErr').textContent.indexOf('muchos códigos seguidos') >= 0);
    });
  }))

  /* 7 · Con la confirmación de correo apagada, `signUp` ya trae sesión: pedir
        un código dejaría esperando un correo que nadie mandó. */
  .then(() => registrar({ sinConfirmacion:true }).then(({ s, pantalla }) => {
    ok('SIN CONFIRMACIÓN · no pide código', pantalla() !== 'codigo');
    ok('SIN CONFIRMACIÓN · entra directo', dentro(s));
  }))

  /* 8 · El registro que falla no navega a ningún lado: el error tiene que
        quedarse donde la persona está mirando. */
  .then(() => registrar({ correoRepetido:true }).then(({ s, pantalla }) => {
    ok('CORREO REPETIDO · no se mueve de pantalla', pantalla() === null);
    ok('CORREO REPETIDO · el error se ve donde se tecleó',
       s.tiene('regErr', 'show') &&
       s.el('regErr').textContent.indexOf('ya está registrado') >= 0);
  }))

  .then(() => {
    if(fallos){ console.log('\n' + fallos + ' fallo(s)'); process.exit(1); }
    console.log('registro: del formulario al menú con un código de 6 dígitos, sin depender del enlace');
  })
  .catch(e => { console.log('  FALLA · ' + e.message); process.exit(1); });
