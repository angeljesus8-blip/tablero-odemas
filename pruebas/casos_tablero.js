/* ============================================================
   Qué se comprueba del tablero, en castellano
   ============================================================
   Este archivo NO se ejecuta solo: lo corre `humo_tablero.js` dentro del
   mismo contexto que el JavaScript del tablero, que es la única forma de
   ver sus funciones sin tocar el archivo de producción.

   Cada comprobación es una invariante que, rota, significa que alguien en
   la tienda ve un número falso o un botón que no debería existir.
   Al añadir una, deja escrito POR QUÉ importa.
   ============================================================ */

aplicarTodo(Object.assign(_deSupabase(JSON.parse(JSON.stringify(TIENDA))), { __sb:true }));
const app = document.getElementById('app');

// ── 1 · Las seis pantallas se pintan ────────────────────────
for(const f of ['inicio','promo','apartados','eol','resurtir','inv']){
  let err = null;
  try { filtroActivo = f; busqueda = ''; render(); } catch(e){ err = e.message; }
  ok('la sección "'+f+'" se pinta', !err && app.innerHTML.length > 40, err || 'salió vacía');
}

// ── 2 · Y el buscador, incluso sin resultados ───────────────
for(const q of ['prueba','900003','cliente','zzzz']){
  let err = null;
  try { filtroActivo = 'promo'; busqueda = q; render(); } catch(e){ err = e.message; }
  ok('buscar "'+q+'" no revienta', !err, err);
}
busqueda = '';

// ── 3 · Los cinco estados de existencia ─────────────────────
const esperado = { '900001':'hay', '900002':'hay', '900003':'piso',
                   '900004':'50', '900005':'no', '900006':'traer', '900007':'traer' };
for(const sku of Object.keys(esperado)){
  const k = estadoSku(sku).k;
  ok('SKU '+sku+' es "'+esperado[sku]+'"', k === esperado[sku], 'dice "'+k+'"');
}

/* Solo se vende lo que hay en bodega, o la de piso si está descontinuada.
   La exhibición de un producto ACTIVO no se vende — ver MAPA, cadena 5. */
ok('vendible = stock, o piso solo si es EOL',
   tieneExistencia_('900001') && tieneExistencia_('900004') &&
   !tieneExistencia_('900003') && !tieneExistencia_('900006'));

// ── 4 · El botón de apartar, solo donde toca ────────────────
filtroActivo = 'promo'; render();
const conBoton = [...new Set([...app.innerHTML.matchAll(/abrirApartado\('(\d+)'/g)].map(m => m[1]))];
ok('no se aparta lo que sí se puede vender',
   !conBoton.some(s => tieneExistencia_(s) && !APARTAR_EXCEPCION.has(s)),
   conBoton.filter(s => tieneExistencia_(s) && !APARTAR_EXCEPCION.has(s)).join(', '));
ok('no se aparta un descontinuado agotado',
   !conBoton.some(s => estadoSku(s).k === 'no'),
   conBoton.filter(s => estadoSku(s).k === 'no').join(', '));

// ── 5 · Los contadores no se contradicen ────────────────────
ok('Resurtir = sin nada + con pieza de piso',
   cuenta('resurtir') === AGOTADOS.length + RESURTIR.length,
   cuenta('resurtir') + ' vs ' + (AGOTADOS.length + RESURTIR.length));

/* Una promo sin fila de inventario tiene que entrar igual a la lista de
   pedidos: si no, se anuncia en el folleto y nadie la pide nunca. */
ok('la promo sin inventario entra a Resurtir',
   AGOTADOS.some(x => x.sku === '900099' && x.nuncaLlego));

/* El total del Assurant y la suma de las filas del equipo salen de la misma
   fuente desde v151. Si se separan, el gerente ve dos números distintos del
   mismo KPI y no sabe cuál reportar. */
const att = attTotal();
ok('Assurant: el total es la suma de las filas',
   filasLeaderboard().reduce((a, f) => a + f.total, 0) === att.c + att.s,
   filasLeaderboard().reduce((a, f) => a + f.total, 0) + ' vs ' + (att.c + att.s));

// Lo que cuenta la tarjeta de Apartados es trabajo pendiente, no historial
ok('Apartados cuenta solo los que faltan por entregar', cuenta('apartados') === 2,
   'dice ' + cuenta('apartados') + ', deberían ser 2 (ni el entregado ni el cancelado)');

// ── 6 · La sección y la búsqueda viajan en la URL ───────────
irA('resurtir');
ok('irA escribe la sección en la URL', location.hash === '#resurtir', location.hash);
busqueda = 'mate 11'; _urlAlDia();
ok('la búsqueda también va en la URL', /resurtir/.test(location.hash) && /mate/.test(location.hash),
   location.hash);

/* ── 7 · Resurtir es de gerente y subgerente (9-ago-2026) ────
   Pedirle mercancía al CD es trabajo de quien lleva la tienda. Lo que NO puede
   pasar es que al asesor se le esconda el producto: con el cliente enfrente
   necesita saber que existe y que se trae de otra tienda. Por eso aquí se
   comprueban las dos mitades, y la segunda es la que de verdad importa. */

// Los puestos, uno por uno. Salen de la lista cerrada de Admin → Equipo.
ok('el gerente y el subgerente gestionan',
   esPuestoDeGestion_('Gerente de Tienda') && esPuestoDeGestion_('Subgerente de Tienda'));
ok('el asesor no', !esPuestoDeGestion_('Asesor de Tienda'));
ok('el encargado y el auxiliar tampoco',
   !esPuestoDeGestion_('Encargado de Tienda') && !esPuestoDeGestion_('Auxiliar de Tienda'));
// Sonar escribe el mismo puesto de otra forma: "SUBGERENTE TIENDA RS"
ok('el puesto como lo escribe Sonar también cuenta', esPuestoDeGestion_('SUBGERENTE TIENDA RS'));
// Un acento de más al teclearlo a mano no debe costarle el acceso a nadie
ok('un acento mal puesto no lo tumba', esPuestoDeGestion_('Gérente de Tienda'));
ok('sin puesto no se adivina nada',
   !esPuestoDeGestion_('') && !esPuestoDeGestion_(null) && !esPuestoDeGestion_(undefined));

const _eraGestion = PUEDE_GESTIONAR;
PUEDE_GESTIONAR = false;                      // a partir de aquí, un asesor

busqueda = ''; filtroActivo = 'inicio'; render();
ok('al asesor no le sale la tarjeta de Resurtir en Inicio',
   app.innerHTML.indexOf("irA('resurtir')") < 0);

/* Entrar por la URL tampoco: el hash se teclea, se comparte y lo restaura
   continuidad.js al volver de WhatsApp. */
filtroActivo = 'resurtir'; render();
ok('al asesor un #resurtir lo deja en Inicio', filtroActivo === 'inicio', filtroActivo);
ok('y la URL no se queda apuntando a una sección que no verá',
   location.hash.indexOf('resurtir') < 0, location.hash);

/* El botón ✕ EOL marca un producto como descontinuado para toda la tienda:
   no es una acción de asesor ni aunque llegara a ver la fila. */
const _fila = RESURTIR[0] || AGOTADOS[0];
ok('el asesor no ve el botón ✕ EOL', rowResurtir(_fila).indexOf('marcarNoResurtir') < 0);

/* LA MITAD QUE IMPORTA: el buscador. El producto tiene que seguir saliendo,
   solo que bajo el encabezado del asesor —"se traen de otra tienda"— y no bajo
   la lista de pedidos del gerente. Si esto se rompe, el asesor le dice a un
   cliente "no lo tenemos" de un producto que sí se puede conseguir. */
filtroActivo = 'inicio'; busqueda = '900003'; render();
const _vistaAsesor = app.innerHTML;
ok('el asesor no ve el bloque "Hay que resurtir"',
   _vistaAsesor.indexOf('Hay que resurtir') < 0);
ok('pero el producto sigue apareciendo', _vistaAsesor.indexOf('900003') >= 0);
ok('y sale como algo que se puede conseguir',
   _vistaAsesor.indexOf('Se traen de otra tienda') >= 0);
/* Y no acaba en el cajón de los descontinuados. `mostrados` se arma con los
   SKU de los bloques pintados: si el de Resurtir era el único que lo reclamaba,
   al quitarlo el producto caería en "Ya no se maneja en la tienda" — o sea,
   pasaría de "se consigue" a "no lo pidas", que es peor que ocultarlo. */
ok('y no cae en "ya no se maneja en la tienda"',
   _vistaAsesor.indexOf('Ya no se maneja') < 0);

PUEDE_GESTIONAR = _eraGestion;                // vuelve el gerente
busqueda = ''; filtroActivo = 'inicio'; render();
ok('el gerente sí ve la tarjeta de Resurtir',
   app.innerHTML.indexOf("irA('resurtir')") >= 0);
ok('y el gerente sí ve el botón ✕ EOL',
   rowResurtir(_fila).indexOf('marcarNoResurtir') >= 0);


/* ── 8 · El Assurant del día solo se acepta de Supabase (17-ago-2026) ────

   El `modo=todo` del Apps Script trae su propio `ventas_hoy`, sacado de la
   hoja. Mientras la doble escritura viva, los dos dicen lo mismo; en cuanto se
   apague, la hoja se queda congelada y esa mitad de la respuesta seguiría
   llegando —además ~7 s DESPUÉS, o sea pisando la buena.

   Y no daría ningún error: daría un porcentaje. Un attach del 40 % de anteayer
   se ve exactamente igual de creíble que el de hoy, y es el número que se
   reporta con meta del 25 %.

   Se comprueban las DOS mitades a propósito. La segunda es la guardia; la
   primera es que la guardia no se haya pasado de frenada y deje el leaderboard
   vacío para siempre, que sería cambiar un fallo callado por otro. */
aplicarTodo(Object.assign(_deSupabase(JSON.parse(JSON.stringify(TIENDA))), { __sb:true }));
const _attSb = JSON.stringify(VENTAS_NUBE);
ok('las ventas de Supabase sí se aplican',
   !!(VENTAS_NUBE && VENTAS_NUBE['Prueba Uno'] && VENTAS_NUBE['Prueba Uno'].c === 2),
   'llegó ' + _attSb);
ok('y la carga queda marcada como buena', CARGAS.ventas === 'ok', 'quedó ' + CARGAS.ventas);

/* La guardia, rota a propósito: la misma forma que devuelve el GAS, con otro
   número y sin la marca `__sb`. Antes del 17-ago esto entraba sin más. */
aplicarTodo({ ventas_hoy: { vend: { 'Prueba Uno': { c:99, s:0 } } } });
ok('las ventas del Apps Script NO pisan las de Supabase',
   JSON.stringify(VENTAS_NUBE) === _attSb,
   'las pisó: ' + JSON.stringify(VENTAS_NUBE));
ok('y la carga se marca fallida, para que el banner lo diga',
   CARGAS.ventas === 'error', 'quedó ' + CARGAS.ventas);
ok('y el banner la nombra de forma reconocible en piso',
   CARGA_NOMBRE.ventas.indexOf('Assurant') >= 0);

// Se deja el tablero con los datos buenos, por si mañana alguien añade un caso 9.
aplicarTodo(Object.assign(_deSupabase(JSON.parse(JSON.stringify(TIENDA))), { __sb:true }));


/* ── 9 · La pieza de exhibición vendida desaparece del aparador ──────────
   Con los números REALES del caso que lo destapó (17-ago-2026, v175):
   HUAWEI WATCH FIT 4 — 5 piezas cerradas, 1 en exhibición, y esa se vendió
   marcada como pieza de piso.

   El servidor mandaba `exh_vendida = 1` y el tablero seguía pintando «1 en
   exhibición», porque aquí se volvía a restar el excedente sobre el almacén
   —`ev - onhand`— que desde v174 el servidor YA trae descontado. Con 5 en
   bodega, `max(0, 1-5)` es 0 y la resta se anulaba entera.

   Lo que estaba en juego no es el texto: `estadoSku` decide con `exhibe` si
   ofrece la última pieza al 50 %. Un aparador que no baja manda al asesor a
   buscar una caja que ya se llevó otro cliente. */
{
  const T = JSON.parse(JSON.stringify(TIENDA));
  // 900004 es el EOL con pieza de piso: el mismo caso del WATCH FIT 4. Tiene que
  // ser EOL, porque solo esos venden su exhibición (cadena 5 del MAPA).
  const fila = (T.inventario || []).find(function(x){ return x.sku === '900004'; });
  fila.onhand = 5; fila.vendido = 0; fila.exhibicion = 1; fila.exh_vendida = 1;
  aplicarTodo(Object.assign(_deSupabase(T), { __sb:true }));

  const inv = invBySku[fila.sku] || {};
  ok('las piezas cerradas no se tocan al vender la de exhibición',
     inv.stock === 5, 'stock ' + inv.stock);
  ok('y el aparador queda en cero, no en uno',
     inv.exhibe === 0, 'exhibe ' + inv.exhibe);

  /* La otra mitad: sin ventas de exhibición, el aparador sigue contando. Si
     alguien "arreglara" esto restando de más, el tablero escondería piezas de
     piso que sí están y nadie las ofrecería nunca. */
  fila.exh_vendida = 0;
  aplicarTodo(Object.assign(_deSupabase(T), { __sb:true }));
  ok('y sin ventas de exhibición el aparador sigue contando su pieza',
     (invBySku[fila.sku] || {}).exhibe === 1,
     'exhibe ' + (invBySku[fila.sku] || {}).exhibe);
}

// Y se deja otra vez con los datos buenos.
aplicarTodo(Object.assign(_deSupabase(JSON.parse(JSON.stringify(TIENDA))), { __sb:true }));


/* ── 10 · Un apartado dice CUÁNDO se cobró, no solo cuándo se entregó ────
   17-ago-2026. La tarjeta enseñaba «Entregado el …» y nada más. Falta la otra
   fecha, y es la que explica todo lo demás: el cliente pagó semanas antes, así
   que su ticket está en el corte de ESE día —a veces de otro mes— y por eso la
   entrega no cuenta para el Assurant ni descuenta stock.

   Con las dos fechas juntas, la distancia entre ellas se lee de un vistazo. */
{
  const T = JSON.parse(JSON.stringify(TIENDA));
  const ap = (T.apartados || []).find(function(a){ return a.estatus === 'Entregado'; });
  ap.creado_en    = '2026-07-20T10:00:00Z';   // cobrado en julio
  ap.entregado_en = '2026-08-17T17:00:00Z';   // entregado en agosto
  aplicarTodo(Object.assign(_deSupabase(T), { __sb:true }));

  const tarjeta = cardApartado(APARTADOS.find(function(a){ return a.estatus === 'Entregado'; }));
  ok('la tarjeta dice cuándo se cobró', tarjeta.indexOf('Cobrado el 20 jul') >= 0, tarjeta.slice(0,300));
  ok('y sigue diciendo cuándo se entregó', tarjeta.indexOf('Entregado el 17 ago') >= 0);

  /* La fecha se parte del texto, NO con `new Date(...)`: la cadena viene sin
     zona horaria y el navegador la tomaría como UTC. En México eso adelanta el
     día, así que un apartado cobrado a las 8 pm saldría con la fecha siguiente
     — el mismo error que ya obligó a calcular todas las fechas en hora de
     México dentro de la base. */
  ok('y una hora de la noche no se va al día siguiente',
     fechaCortaAp_('2026-07-20 20:30') === '20 jul',
     fechaCortaAp_('2026-07-20 20:30'));
}

aplicarTodo(Object.assign(_deSupabase(JSON.parse(JSON.stringify(TIENDA))), { __sb:true }));
