/* ============================================================
   El catálogo de accesorios se guarda COMPLETO
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe por un fallo que estuvo dos días en el servidor sin que nadie lo
   viera, porque no daba error: `accesorio_catalogo_guardar` se escribió el
   18-ago, el día ANTES de que el catálogo tuviera `articulo` y `sku`, y solo
   guardaba (nombre, precio, orden). Un producto dado de alta con ella quedaba:

     · sin `articulo` → `accAdivinar` se salta las filas sin código, así que ese
       producto NUNCA se propone al leer un ticket. Parecería que el OCR empeoró.
     · con `sku` 43739 → cierto para micas, falso para los Office, que van al
       reporte de comisiones con SU código. La columna E del Excel saldría mal.

   Nunca llegó a usarse porque no había pantalla. Ahora la hay —en Admin →
   Catálogo, con el resto de catálogos— así que esto es lo que impide que vuelva:

     1. El alta manda `p_articulo` y `p_sku`; editar manda el id.
     2. El aviso de códigos parecidos y la adivinanza dicen LO MISMO.
     3. Sin permiso, la lista vacía se explica en vez de quedarse en blanco.

   La 2 se comprueba a caballo entre los dos archivos a propósito: son dos usos
   de la misma regla en pantallas distintas, y desde el 20-ago viven juntos en
   `acc_codigos.js` justo para que no se separen.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const raiz  = path.join(__dirname, '..');
const admin = fs.readFileSync(path.join(raiz, 'admin.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

const STORE = { store_id:'1217', nombre:'Angelopolis', gas_token:'t', vendedores:[] };

/* Lo que devolvería `accesorios_catalogo_admin`: productos reales del catálogo
   sembrado, con la colisión de $149 que ya existe en la tienda. */
const CATALOGO = [
  { id:1, articulo:'43739-MICAHR',    nombre:'MICA HR',         precio_ref:149,  sku:'43739', orden:10,  activo:true, usos:7 },
  { id:2, articulo:'43739-MICAMATTE', nombre:'MICA MATTE',      precio_ref:149,  sku:'43739', orden:20,  activo:true, usos:3 },
  { id:3, articulo:'63602',           nombre:'OFFICE PERSONAL', precio_ref:2249, sku:'63602', orden:300, activo:true, usos:0 }
];

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

/* Admin habla con Supabase por el SDK del CDN, que aquí no existe. Se le pone
   uno falso que apunta lo que se le pide: es lo único que permite comprobar QUÉ
   campos se mandan, que es justo donde estuvo el fallo. */
function arrancar(empno, filas){
  const ent = crearEntorno({
    html: admin,
    ruta: '/t/admin.html',
    ls: { hes_store: JSON.stringify(STORE), hes_role: 'gerente',
          hes_empleado: JSON.stringify({ empno: empno, nombre:'Quien sea',
                                         puesto:'Gerente de Tienda', admin:true }) }
  });
  if(!ent.err){
    /* `acc_codigos.js` entra por <script src>, que el entorno no baja: se
       inyecta a mano, igual que hace el navegador antes del script de la
       página. Si faltara de verdad, `catAccMirarArt` lanzaría ReferenceError
       al teclear — por eso el verificador comprueba aparte que el archivo
       exista y esté en el service worker. */
    ent.correr(fs.readFileSync(path.join(raiz, 'acc_codigos.js'), 'utf8'));
    ent.correr(
      'var __llamadas = [];\n' +
      'var __filas = ' + JSON.stringify(filas === undefined ? CATALOGO : filas) + ';\n' +
      'window.supabase = { createClient: function(){ return { rpc: function(fn, p){\n' +
      '  __llamadas.push({ fn: fn, body: p });\n' +
      '  if(fn === "accesorios_catalogo_admin") return Promise.resolve({ data: __filas, error: null });\n' +
      '  return Promise.resolve({ data: { ok: true, id: 99 }, error: null });\n' +
      '} }; } };');
  }
  return Object.assign(ent, {
    llamadas: () => JSON.parse(ent.correr('JSON.stringify(__llamadas)')),
    guardados: function(){
      return this.llamadas().filter(x => x.fn === 'accesorio_catalogo_guardar');
    },
    limpiar: () => ent.correr('__llamadas.length = 0;')
  });
}

/* ── 1 · El alta guarda el código de artículo y el SKU ──────────────────── */
async function bloque1(){
  const s = arrancar('1000001');
  ok('Admin arranca', !s.err, s.err);
  if(s.err) return;

  await s.caja.cargarCatAcc();
  ok('el catálogo se pinta',
     s.el('catAccLista').innerHTML.indexOf('MICA HR') >= 0,
     s.el('catAccLista').innerHTML.slice(0, 140));

  /* LA LECTURA TAMBIÉN LLEVA CREDENCIAL, y esto se comprueba porque ya falló:
     `sbLeer` manda `p_store` y nada más —el token lo añade `sbEscribir`, no
     él—, así que la primera versión pedía el catálogo sin token. El servidor
     devolvía cero filas, y la pantalla lo achacaba a falta de permiso o de red
     estando las dos en orden. Un fallo de permisos que se disfraza de otra
     cosa cuesta el doble de encontrar. */
  const l = s.llamadas().filter(x => x.fn === 'accesorios_catalogo_admin')[0];
  ok('la lectura del catálogo manda el token', !!l && !!l.body.p_token,
     'llegó: ' + JSON.stringify(l && l.body));
  ok('y dice quién pregunta', !!l && l.body.p_quien === '1000001',
     'llegó: ' + JSON.stringify(l && l.body.p_quien));

  // ── Alta ──
  s.caja.catAccNuevo();
  s.el('catAccNombre').value = 'MEMORIA USB ADATA 256GB';
  s.el('catAccArt').value    = '43739-USB256';
  s.el('catAccPrecio').value = '649';
  s.el('catAccSku').value    = '43739';
  s.el('catAccOrden').value  = '135';
  await s.caja.catAccGuardar();

  const g = s.guardados()[0];
  ok('el alta llega al servidor', !!g, 'no se llamó a accesorio_catalogo_guardar');
  if(g){
    ok('y con el nombre', g.body.p_nombre === 'MEMORIA USB ADATA 256GB', g.body.p_nombre);
    /* ESTAS DOS son el fallo que esta prueba existe para impedir. */
    ok('y CON EL CÓDIGO DE ARTÍCULO, o el producto no se propondría nunca',
       g.body.p_articulo === '43739-USB256', 'llegó: ' + JSON.stringify(g.body.p_articulo));
    ok('y CON EL SKU, que es la columna E del reporte de comisiones',
       g.body.p_sku === '43739', 'llegó: ' + JSON.stringify(g.body.p_sku));
    ok('y con el precio como número, no como texto',
       g.body.p_precio === 649, JSON.stringify(g.body.p_precio));
    ok('y sin id, porque es un alta',
       g.body.p_id === null || g.body.p_id === undefined, 'llegó id ' + g.body.p_id);
    /* El servidor decide con esto si quien lo hace es gerente o subgerente.
       Vacío pasaría como «la sesión del dueño» y saltaría la comprobación. */
    ok('y diciendo quién lo hace, que es lo que el servidor comprueba',
       g.body.p_quien === '1000001', JSON.stringify(g.body.p_quien));
  }

  // ── Editar: manda el id, no crea un duplicado ──
  s.limpiar();
  s.caja.catAccElegir(0);                      // MICA HR
  ok('al elegir un producto se llena su código',
     s.el('catAccArt').value === '43739-MICAHR', s.el('catAccArt').value);
  ok('y se avisa de cuántas ventas llevan ese nombre, antes de renombrarlo',
     s.el('catAccUsos').style.display === 'block' &&
     s.el('catAccUsos').innerHTML.indexOf('7') >= 0, s.el('catAccUsos').innerHTML);

  s.el('catAccPrecio').value = '159';          // subió de precio
  await s.caja.catAccGuardar();
  const e = s.guardados()[0];
  ok('editar manda el id del producto', !!e && e.body.p_id === 1,
     'llegó id ' + (e && e.body.p_id));
  /* Si al editar se perdiera el artículo, el producto seguiría existiendo pero
     dejaría de proponerse: el fallo original, por la puerta de atrás. */
  ok('y conserva el código de artículo al editar',
     !!e && e.body.p_articulo === '43739-MICAHR', e && e.body.p_articulo);

  // ── Dar de baja NO borra: manda activo=false ──
  s.limpiar();
  await s.caja.catAccBaja(0);
  const b = s.llamadas().filter(x => x.fn === 'accesorio_catalogo_baja')[0];
  ok('la baja manda el id y activo=false',
     !!b && b.body.p_id === 1 && b.body.p_activo === false, JSON.stringify(b && b.body));
}

/* ── 2 · El aviso de Admin y la adivinanza de Captura dicen lo mismo ────── */
function bloque2(){
  const { accChoca } = require(path.join(raiz, 'acc_codigos.js'));

  const cat = [
    { id:1, articulo:'43739-MICAHR',     nombre:'MICA HR',      precio_ref:149, sku:'43739', activo:true },
    { id:2, articulo:'43739-MICAHRPLUS', nombre:'MICA HR PLUS', precio_ref:199, sku:'43739', activo:true }
  ];

  ok('un código que empieza igual que otro se detecta',
     (accChoca('43739-MICAHRPLUS', [cat[0]], null) || {}).nombre === 'MICA HR',
     'no lo detectó');
  ok('uno distinto no da falsa alarma',
     accChoca('43739-USB256', cat, null) === null, 'avisó de más');
  /* Un producto no se acusa a sí mismo al editarlo: sin esto, abrir MICA HR
     para cambiarle el precio avisaría de que choca con MICA HR, y un aviso que
     sale siempre se acaba ignorando —incluso cuando dice algo cierto. */
  ok('y un producto no choca consigo mismo al editarlo',
     accChoca('43739-MICAHR', [cat[0]], 1) === null, 'se acusó a sí mismo');
  /* Pero sí con OTRO parecido, aunque sea el que se está editando el que ya
     existía: el empate rompe la propuesta en los dos sentidos. */
  ok('y sí avisa del otro parecido al editar',
     (accChoca('43739-MICAHR', cat, 1) || {}).nombre === 'MICA HR PLUS',
     'no avisó del parecido');

  /* La comprobación de verdad, y la razón de que la regla viva en un solo
     archivo: con esos dos códigos en el catálogo, Captura DEJA de proponer al
     leer un ticket de MICA HR —empatan en seis letras—. Eso es exactamente de
     lo que avisa Admin. Si esto empezara a proponer algo, el aviso estaría
     advirtiendo de un problema que ya no existe; si dejara de avisar teniendo
     el empate, sería peor. */
  const captura = fs.readFileSync(path.join(raiz, 'captura_series.html'), 'utf8');
  const ent = crearEntorno({
    html: captura,
    ruta: '/t/captura_series.html',
    ls: { hes_store: JSON.stringify(STORE),
          hes_empleado: JSON.stringify({ empno:'1000001', nombre:'Quien sea',
                                         puesto:'Gerente de Tienda' }) }
  });
  if(ent.err){ fallos.push('Captura no arranca (bloque 2): ' + ent.err); return; }

  /* `acc_codigos.js` es un <script src>, que el entorno no baja: se inyecta a
     mano, igual que hace el navegador antes del script de la página. */
  ent.correr(fs.readFileSync(path.join(raiz, 'acc_codigos.js'), 'utf8'));
  ent.correr('_accCat = ' + JSON.stringify(cat) + ';');

  ok('con el empate, Captura no propone nada',
     ent.caja.accAdivinar('SERVICIO: 43739-MICAHR') === null,
     'propuso: ' + ent.caja.accAdivinar('SERVICIO: 43739-MICAHR'));
  /* Y sin empate sí propone: si no, la comprobación de arriba pasaría también
     con una adivinanza rota que no propone nunca. */
  ent.correr('_accCat = ' + JSON.stringify([cat[0]]) + ';');
  ok('y sin empate sí propone',
     ent.caja.accAdivinar('SERVICIO: 43739-MICAHR') === 'MICA HR',
     'propuso: ' + ent.caja.accAdivinar('SERVICIO: 43739-MICAHR'));
}

/* ── 3 · Los avisos de la ficha, sobre datos reales ─────────────────────── */
async function bloque3(){
  const s = arrancar('1000001');
  if(s.err){ fallos.push('Admin no arranca (bloque 3): ' + s.err); return; }
  await s.caja.cargarCatAcc();
  s.caja.catAccNuevo();

  s.el('catAccArt').value = '43739-USB256';
  s.caja.catAccMirarArt();
  ok('un código distinto no dispara el aviso',
     s.el('catAccAvisoArt').style.display === 'none',
     'avisó de más: ' + s.el('catAccAvisoArt').innerHTML);

  s.el('catAccArt').value = '43739-MICAHRPLUS';
  s.caja.catAccMirarArt();
  ok('un código parecido a otro SÍ avisa, y dice a cuál',
     s.el('catAccAvisoArt').style.display === 'block' &&
     s.el('catAccAvisoArt').innerHTML.indexOf('MICA HR') >= 0,
     s.el('catAccAvisoArt').innerHTML || '(no avisó)');

  /* MICA HR y MICA MATTE cuestan las dos $149: por eso ninguna se marca sola al
     leer el ticket. Son los 19 tickets que en julio hubo que abrir uno a uno. */
  s.el('catAccPrecio').value = '149';
  s.caja.catAccMirarPrecio();
  ok('un precio que ya tiene otro producto avisa',
     s.el('catAccAvisoPrecio').style.display === 'block', 'no avisó del precio repetido');

  s.el('catAccPrecio').value = '777';
  s.caja.catAccMirarPrecio();
  ok('y un precio libre no', s.el('catAccAvisoPrecio').style.display === 'none',
     'avisó de más');
}

/* ── 4 · Sin permiso, la lista vacía se explica ─────────────────────────── */
async function bloque4(){
  /* El servidor devuelve cero filas tanto si no hay permiso como si no hay red,
     a propósito. Pero el catálogo NUNCA está vacío de verdad —los 23 están
     sembrados—, así que dejar la lista en blanco haría creer que se borró. */
  const s = arrancar('1000003', []);           // un asesor: sin permiso
  if(s.err){ fallos.push('Admin no arranca (bloque 4): ' + s.err); return; }
  await s.caja.cargarCatAcc();
  const html = s.el('catAccLista').innerHTML;
  ok('una lista vacía dice por qué, en vez de quedarse en blanco',
     html.indexOf('permiso') >= 0 || html.indexOf('conexión') >= 0,
     'quedó: ' + html.slice(0, 120));
  ok('y no se ofrece la ficha como si se pudiera guardar',
     s.el('catAccFicha').style.display === 'none', 'la ficha quedó abierta');
}

Promise.resolve()
  .then(bloque1).then(bloque2).then(bloque3).then(bloque4)
  .then(function(){
    if(fallos.length){
      console.log('FALLOS en el catálogo de accesorios:');
      fallos.forEach(f => console.log('  · ' + f));
      process.exit(1);
    }
    console.log('catálogo de accesorios: bien');
  }, function(err){
    console.log('FALLO en el catálogo de accesorios: ' + ((err && err.stack) || err));
    process.exit(1);
  });
