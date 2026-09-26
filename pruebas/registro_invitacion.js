/* ============================================================
   Abrir una tienda: código de invitación, y dentro
   ============================================================
   20-sep-2026. El alta dependía de un enlace en el correo. Al registrar la 1217
   se vio que en esta red no llega usable: los correos @radioshack.com.mx pasan
   por el reescritor del filtro corporativo y el enlace murió con
   ERR_CONNECTION_RESET. Y aunque abriera, obliga a volver en el MISMO navegador
   donde se llenó el formulario.

   Ahora se abre tienda con un código que da quien lleva la red, y la tienda la
   crea el servidor de una vez (`alta_tienda`).

   Lo que se defiende aquí, por orden de lo que más caro sale:

     1. Que la tienda SOLO se cree por la RPC. Volver a los INSERT sueltos deja
        tiendas sin gerente dentro y no da ningún error.
     2. Que un código malo NO cree la cuenta. Si se crea, el segundo intento
        choca con «este correo ya está registrado» y la persona queda encerrada
        entre dos errores que se contradicen.
     3. Que el alta que se queda a medias se pueda terminar, y que terminarla
        dos veces no rompa nada.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const { crearEntorno } = require('./dom.js');

const HTML = fs.readFileSync(path.join(__dirname, '..', 'index.html'), 'utf8');

let fallos = 0;
function ok(que, cond){ if(!cond){ console.log('  FALLA · ' + que); fallos++; } }

const CORREO = 't9999@ejemplo.mx';
const CODIGO = 'K7M2QPXR';

function clienteFalso(o, llamadas){
  let haySesion = !o.confirmacionEncendida;
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
        llamadas.signUpArgs = args;
        if(o.correoRepetido) return { data:{}, error:{ message:'User already registered' } };
        // Como Supabase: lo que se manda en `options.data` vuelve en user_metadata.
        return { data:{ user:{ id:'u1', email:args.email,
                               user_metadata: Object.assign({}, (args.options || {}).data) },
                        session: o.confirmacionEncendida ? null : { access_token:'t' } },
                 error:null };
      },
      verifyOtp: async (args) => {
        llamadas.push('verifyOtp');
        haySesion = true;
        return { data:{ user:{ id:'u1', email:args.email }, session:{ access_token:'t' } }, error:null };
      },
      resend: async () => { llamadas.push('resend'); return { error:null }; },
      updateUser: async (args) => {
        llamadas.push('updateUser:' + JSON.stringify(args && args.data));
        return { data:{}, error:null };
      },
      getSession: async () => ({ data:{ session: o.sesionDelEnlace
        ? { access_token:'t', user:o.sesionDelEnlace } : null } }),
      signOut: async () => ({})
    },
    // Si algo vuelve a crear tiendas por aquí, la prueba lo ve.
    from: (tabla) => Object.assign({
      insert: async () => { llamadas.push('insert:' + tabla); return { error:null }; }
    }, cadena),
    rpc: async (fn, args) => {
      llamadas.push('rpc:' + fn);
      if(fn === 'invitacion_valida'){
        if(o.codigoMalo) return { data:{ ok:false, error:o.codigoMalo }, error:null };
        return { data:{ ok:true, store_id:o.codigoDeTienda || null }, error:null };
      }
      if(fn === 'alta_tienda'){
        llamadas.push('alta:' + [args.p_codigo, args.p_store_id, args.p_nombre,
                                 args.p_empno, args.p_emp_nombre].join('|'));
        if(!haySesion)   return { data:{ ok:false, error:'sin_sesion' }, error:null };
        if(o.altaFalla)  return { data:{ ok:false, error:o.altaFalla }, error:null };
        return { data:{ ok:true, store_id:args.p_store_id }, error:null };
      }
      return { data:null, error:null };
    }
  };
}

function arrancar(o){
  const s = crearEntorno({ html: HTML, ls: (o && o.ls) || {} });
  if(s.err) throw new Error('el script de index.html no arrancó: ' + s.err);
  const llamadas = [];
  s.caja.__falso = clienteFalso(o || {}, llamadas);
  s.correr('sb = __falso');
  s.correr('__pantalla = null; sc = (function(orig){ return function(n){ __pantalla = n; return orig(n); }; })(sc);');
  return { s, llamadas, pantalla: () => s.correr('__pantalla') };
}

function registrar(o){
  const { s, llamadas, pantalla } = arrancar(o);
  const poner = (id, v) => { s.el(id).value = v; };
  poner('regEmail', CORREO);
  poner('regPass', 'secreta1'); poner('regPass2', 'secreta1');
  poner('regCodigo', (o && o.codigo !== undefined) ? o.codigo : CODIGO);
  poner('regId', '1217'); poner('regNombre', 'Angelopolis'); poner('regCiudad', 'Puebla');
  poner('regEmpNombre', 'Ana Ramirez Solis'); poner('regEmpNo', '1000001');
  return s.correr('doRegister()').then(() => ({ s, llamadas, pantalla }));
}

const dentro   = s => s.el('mainMenu').style.display === 'block';
const dice     = (s, id, t) => (s.el(id).textContent || '').indexOf(t) >= 0;
const seCreoLa = ll => ll.some(l => l.indexOf('alta:') === 0);

Promise.resolve()

  /* 1 · El alta buena, de punta a punta. */
  .then(() => registrar({}).then(({ s, llamadas }) => {
    ok('ALTA · se comprueba el código antes de crear la cuenta',
       llamadas.indexOf('rpc:invitacion_valida') < llamadas.indexOf('signUp'));
    ok('ALTA · la tienda la crea el servidor, con el código y el gerente',
       llamadas.indexOf('alta:' + CODIGO + '|1217|Angelopolis|1000001|Ana Ramirez Solis') >= 0);
    ok('ALTA · entra directo, sin volver a pedir la contraseña', dentro(s));
    ok('ALTA · queda la sesión de gerente', s.LS['odemas_role'] === 'gerente');
    ok('ALTA · no queda alta pendiente', s.lsJson('hes_alta_pendiente') === null);
  }))

  /* 2 · LA REGLA: la tienda no se crea por ningún otro camino. Si alguien
        vuelve a meter un INSERT directo, esto se enciende. */
  .then(() => registrar({}).then(({ llamadas }) => {
    ok('SOLO LA RPC · nadie inserta en tiendas por su cuenta',
       llamadas.indexOf('insert:tiendas') < 0);
    ok('SOLO LA RPC · ni da de alta al gerente por su cuenta',
       llamadas.indexOf('insert:empleados') < 0);
  }))

  /* 3 · Sin código no se intenta nada: ni servidor, ni cuenta. */
  .then(() => registrar({ codigo:'' }).then(({ s, llamadas }) => {
    ok('SIN CÓDIGO · no se crea ninguna cuenta', llamadas.indexOf('signUp') < 0);
    ok('SIN CÓDIGO · se dice a quién pedírselo',
       dice(s, 'regErr', 'código de invitación') && dice(s, 'regErr', 'lleva la red'));
  }))

  /* 4 · Un código que no sirve se para ANTES del registro. Esto es lo que
        impide dejar cuentas huérfanas que después no dejan volver a intentarlo. */
  .then(() => registrar({ codigoMalo:'usado' }).then(({ s, llamadas }) => {
    ok('CÓDIGO USADO · la cuenta NO se crea', llamadas.indexOf('signUp') < 0);
    ok('CÓDIGO USADO · se dice qué hacer', dice(s, 'regErr', 'Pide otro'));
  }))
  .then(() => registrar({ codigoMalo:'vencido' }).then(({ s, llamadas }) => {
    ok('CÓDIGO VENCIDO · la cuenta NO se crea', llamadas.indexOf('signUp') < 0);
    ok('CÓDIGO VENCIDO · se dice que pida uno nuevo', dice(s, 'regErr', 'venció'));
  }))

  /* 5 · Un código atado a otra tienda no abre esta. Es lo que impide que la
        invitación de la 1218 acabe creando la 1217. */
  .then(() => registrar({ codigoDeTienda:'1218' }).then(({ s, llamadas }) => {
    ok('OTRA TIENDA · no se crea la cuenta', llamadas.indexOf('signUp') < 0);
    ok('OTRA TIENDA · se dice de qué tienda es el código',
       dice(s, 'regErr', '1218') && dice(s, 'regErr', '1217'));
  }))

  /* 6 · El servidor rechaza el alta con la cuenta ya creada: el mensaje tiene
        que decir eso, o la persona vuelve a registrarse y choca con «ese correo
        ya está registrado». */
  .then(() => registrar({ altaFalla:'tienda_existe' }).then(({ s, llamadas }) => {
    ok('ALTA RECHAZADA · no entra', !dentro(s));
    ok('ALTA RECHAZADA · dice el motivo', dice(s, 'regErr', 'ya está registrado'));
    ok('ALTA RECHAZADA · y que la cuenta sí quedó creada',
       dice(s, 'regErr', 'Tu cuenta ya quedó creada'));
    ok('ALTA RECHAZADA · el alta queda guardada para terminarla al entrar',
       (s.lsJson('hes_alta_pendiente') || {}).codigo === CODIGO);
    ok('ALTA RECHAZADA · se intentó una sola vez',
       llamadas.filter(l => l.indexOf('alta:') === 0).length === 1);
  }))

  /* 7 · Con la confirmación de correo encendida en el panel no hay sesión, así
        que no se puede crear nada todavía: se guarda con su código y se pide el
        código del correo. */
  .then(() => registrar({ confirmacionEncendida:true }).then(({ s, llamadas, pantalla }) => {
    ok('SIN SESIÓN · no se intenta el alta', !seCreoLa(llamadas));
    ok('SIN SESIÓN · se guarda el código junto con los datos',
       (s.lsJson('hes_alta_pendiente') || {}).codigo === CODIGO);
    ok('SIN SESIÓN · se pide el código del correo', pantalla() === 'codigo');
  }))

  /* 8 · Y al confirmar, el alta guardada se termina sola: una sola vez, y
        entrando. */
  .then(() => registrar({ confirmacionEncendida:true }).then(({ s, llamadas }) => {
    s.el('codInp').value = '123456';
    return s.correr('doVerificarCodigo()').then(() => {
      ok('AL CONFIRMAR · se crea la tienda guardada',
         llamadas.filter(l => l.indexOf('alta:') === 0).length === 1);
      ok('AL CONFIRMAR · entra', dentro(s));
      ok('AL CONFIRMAR · ya no queda nada pendiente',
         s.lsJson('hes_alta_pendiente') === null);
    });
  }))

  /* 9 · El alta que ya se terminó no vuelve a intentarse en el siguiente
        ingreso: «ese código ya se usó» con un pendiente delante es casi siempre
        un alta que sí llegó. Parar ahí dejaría al dueño fuera de su tienda. */
  .then(() => {
    const pendiente = JSON.stringify({ codigo:CODIGO, store_id:'1217', nombre:'Angelopolis',
      ciudad:'Puebla', empno:'1000001', emp_nombre:'Ana Ramirez Solis', email:CORREO });
    const { s, llamadas } = arrancar({ altaFalla:'usado', ls:{ hes_alta_pendiente:pendiente } });
    s.el('loginEmail').value = CORREO; s.el('loginPass').value = 'secreta1';
    // signInWithPassword no está en el falso: se añade aquí, que es el único
    // sitio donde este camino se usa.
    s.correr('sb.auth.signInWithPassword = async function(){ return { data:{ user:{ id:"u1", email:"' + CORREO + '" } }, error:null }; };');
    return s.correr('doLogin()').then(() => {
      ok('YA ESTABA CREADA · el ingreso no se corta', dentro(s));
      ok('YA ESTABA CREADA · y el pendiente se limpia',
         s.lsJson('hes_alta_pendiente') === null);
      ok('YA ESTABA CREADA · sin quejarse en pantalla', !s.tiene('loginErr', 'show'));
    });
  })

  /* 10 · El alta viaja CON LA CUENTA (26-sep-2026). Al registrar la 1218 el
        enlace se abrió en el celular, ahí no estaba el pendiente del
        navegador, y la app volvió a pedir el código. */
  .then(() => registrar({ confirmacionEncendida:true }).then(({ llamadas }) => {
    const md = (((llamadas.signUpArgs || {}).options || {}).data || {}).alta_pendiente || {};
    ok('EN LA CUENTA · el registro manda el alta con su código', md.codigo === CODIGO);
    ok('EN LA CUENTA · y con los datos de la tienda y del gerente',
       md.store_id === '1217' && md.empno === '1000001' && md.emp_nombre === 'Ana Ramirez Solis');
  }))
  .then(() => {
    const alta = { codigo:CODIGO, store_id:'1217', nombre:'Angelopolis', ciudad:'Puebla',
                   empno:'1000001', emp_nombre:'Ana Ramirez Solis' };
    // Otro navegador: localStorage vacío. El alta solo está en la cuenta.
    const { s, llamadas } = arrancar({});
    s.caja.__md = alta;
    s.el('loginEmail').value = CORREO; s.el('loginPass').value = 'secreta1';
    s.correr('sb.auth.signInWithPassword = async function(){ return { data:{ user:{ id:"u1", email:"' + CORREO + '", user_metadata:{ alta_pendiente: __md } } }, error:null }; };');
    return s.correr('doLogin()').then(() => {
      ok('OTRO NAVEGADOR · la tienda se crea con el alta de la cuenta',
         llamadas.indexOf('alta:' + CODIGO + '|1217|Angelopolis|1000001|Ana Ramirez Solis') >= 0);
      ok('OTRO NAVEGADOR · sin volver a pedir el código', dentro(s));
      ok('OTRO NAVEGADOR · y el alta se borra de la cuenta',
         llamadas.indexOf('updateUser:{"alta_pendiente":null}') >= 0);
    });
  })

  /* 11 · Registro con sesión (confirmación apagada): la tienda se crea y el
        alta no se queda viva en la cuenta para el siguiente ingreso. */
  .then(() => registrar({}).then(({ llamadas }) => {
    ok('SIN RESTOS · al crearse la tienda el alta se borra de la cuenta',
       llamadas.indexOf('updateUser:{"alta_pendiente":null}') >= 0);
  }))

  /* 12 · El alta guardada que falla (código vencido) no deja a nadie atorado
        en el login: manda a terminar la tienda con todo ya escrito. */
  .then(() => {
    const pendiente = JSON.stringify({ codigo:CODIGO, store_id:'1217', nombre:'Angelopolis',
      ciudad:'Puebla', empno:'1000001', emp_nombre:'Ana Ramirez Solis', email:CORREO });
    const { s, pantalla } = arrancar({ altaFalla:'vencido', tienda:null,
                                        ls:{ hes_alta_pendiente:pendiente } });
    s.el('loginEmail').value = CORREO; s.el('loginPass').value = 'secreta1';
    s.correr('sb.auth.signInWithPassword = async function(){ return { data:{ user:{ id:"u1", email:"' + CORREO + '" } }, error:null }; };');
    return s.correr('doLogin()').then(() => {
      ok('ALTA VENCIDA · va a terminar la tienda, no se queda en el login',
         !s.el('scRegister')._clases.has('hide') && s.el('scLogin')._clases.has('hide'));
      ok('ALTA VENCIDA · dice el motivo ahí', dice(s, 'regErr', 'venció'));
      ok('ALTA VENCIDA · con los datos ya escritos',
         s.el('regId').value === '1217' && s.el('regEmpNo').value === '1000001'
         && s.el('regCodigo').value === CODIGO);
    });
  })

  /* 13 · La pantalla no promete un código que no llega: dice los dos caminos,
        y el del enlace tiene salida a iniciar sesión con el correo escrito. */
  .then(() => registrar({ confirmacionEncendida:true }).then(({ s, pantalla }) => {
    const sub = s.el('codSub').innerHTML;
    ok('PANTALLA · habla del enlace, no solo del código',
       sub.indexOf('enlace') >= 0 && sub.indexOf('inicia sesión') >= 0);
    ok('PANTALLA · no promete «Te mandamos un código»', sub.indexOf('Te mandamos un código') < 0);
    s.correr('yaAbriElEnlace_()');
    ok('PANTALLA · «ya abrí el enlace» lleva a iniciar sesión', pantalla() === 'login');
    ok('PANTALLA · con el correo ya escrito', s.el('loginEmail').value === CORREO);
  }))

  /* 14 · Volver del enlace: si trae sesión se entra (y se termina el alta);
        si venció, se dice y se manda a la contraseña. */
  .then(() => {
    const alta = { codigo:CODIGO, store_id:'1217', nombre:'Angelopolis', ciudad:'Puebla',
                   empno:'1000001', emp_nombre:'Ana Ramirez Solis' };
    const { s, llamadas } = arrancar({ sesionDelEnlace:{ id:'u1', email:CORREO,
                                                        user_metadata:{ alta_pendiente:alta } } });
    return s.correr('volverDelCorreo_("#access_token=x&type=signup")').then(() => {
      ok('DEL ENLACE · se crea la tienda', llamadas.some(l => l.indexOf('alta:' + CODIGO) === 0));
      ok('DEL ENLACE · y se entra', dentro(s));
    });
  })
  .then(() => {
    const { s, pantalla } = arrancar({});
    return s.correr('volverDelCorreo_("#error=access_denied&error_code=otp_expired")').then(() => {
      ok('ENLACE VENCIDO · manda a iniciar sesión', pantalla() === 'login');
      ok('ENLACE VENCIDO · y lo dice', s.el('loginOk').innerHTML.indexOf('venció') >= 0);
    });
  })

  .then(() => {
    if(fallos){ console.log('\n' + fallos + ' fallo(s)'); process.exit(1); }
    console.log('alta de tienda: con código de invitación, creada por el servidor de una vez');
  })
  .catch(e => { console.log('  FALLA · ' + e.message); process.exit(1); });
