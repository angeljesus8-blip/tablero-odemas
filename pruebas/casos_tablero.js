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


/* ── 11 · La cotización suma lo que el asesor eligió (6-sep-2026) ────────
   Pedido en piso: sumar varios artículos con o sin garantía para decirle el
   total al cliente. No cobra nada — sustituye a la calculadora del celular,
   donde lo que se pierde es un seguro que no se sumó.

   ⚠️ Lo que se prueba es de dónde sale el número. El seguro elegido se lee del
   CHIP ACTIVO del bloque de precio, no de una copia propia: si se guardara
   aparte, tocar «1 año» y que la copia no se enterara sumaría sin garantía sin
   que nada lo dijera. Se comprueba montando los chips a mano y moviendo el
   activo, que es lo que hace `selSeg` en el teléfono. */
{
  COT = [];

  /* El bloque de precio tal como lo deja `segSelector`: tres chips, el primero
     activo. `crearEntorno` no está aquí —esta prueba corre sobre el DOM falso
     de humo_tablero—, así que se arma el mínimo que `cotSeguroElegido` mira. */
  function bloqueChips(id, activo){
    const chips = [0,1,2].map(function(i){
      return { classList: { contains: function(c){ return c === 'active' && i === activo; } } };
    });
    document.__nodos = document.__nodos || {};
    document.__nodos[id] = { querySelectorAll: function(){ return chips; } };
  }
  const getIdOrig = document.getElementById;
  document.getElementById = function(id){
    if(document.__nodos && document.__nodos[id]) return document.__nodos[id];
    return getIdOrig.call(document, id);
  };

  // Un reloj de $3,499 con «1 año» (+$1,549) y un teléfono de $24,999 sin seguro.
  bloqueChips('sg_1', 1);
  cotAgregar('100295900', encodeURIComponent('WATCH FIT 5'), 3499, 5048, 5178, 1549, 1679, 'sg_1');
  bloqueChips('sg_2', 0);
  cotAgregar('100269146', encodeURIComponent('PURA 80 PRO'), 24999, 28468, 29618, 3469, 4619, 'sg_2');

  ok('se suman los dos artículos', COT.length === 2, String(COT.length));
  ok('el reloj entra CON su garantía', COT[0].total === 5048, String(COT[0].total));
  ok('y guarda cuánto costó esa garantía', COT[0].seguro === 1549, String(COT[0].seguro));
  ok('el teléfono entra sin seguro', COT[1].total === 24999 && COT[1].seguro === 0,
     COT[1].total + '/' + COT[1].seguro);
  /* El total es la suma de los totales de cada línea, no el precio base más los
     seguros por otro lado: así, quitar una línea se lleva su seguro con ella. */
  ok('el total es lo que se le dice al cliente', cotTotal() === 30047, String(cotTotal()));

  /* «+1 año» PROTEGE DOS: el contratado se suma a la garantía de fábrica, y así
     es como hay que decírselo al cliente. Si esto se dijera «1 año» a secas, el
     asesor estaría vendiendo de menos lo mismo que cobra. */
  ok('un año contratado se cuenta como dos de protección',
     cotTextoSeguro(COT[0]).indexOf('protege 2') >= 0, cotTextoSeguro(COT[0]));
  ok('y sin seguro no dice nada de garantías', cotTextoSeguro(COT[1]) === '',
     cotTextoSeguro(COT[1]));

  // Quitar una línea se lleva su seguro: es lo mismo que devolver el artículo.
  cotQuitar(0);
  ok('quitar el reloj se lleva también su garantía', cotTotal() === 24999, String(cotTotal()));
  ok('y queda un solo artículo', COT.length === 1, String(COT.length));

  /* Sin precio no hay botón. Un «＋ Sumar» sobre un producto sin precio
     registrado metería un cero en la cuenta del cliente. */
  ok('sin precio no se ofrece sumar', botonCot('999', 'X', 0, 0, 0, 0, 0, 'sg_9') === '');
  ok('con precio sí', botonCot('999', 'X', 1000, 0, 0, 0, 0, 'sg_9').indexOf('cotAgregar') >= 0);

  /* ── El 50% también se suma (6-sep-2026) ────────────────────────────
     Visto en piso al día siguiente de publicar: «los artículos que están al 50%
     de descuento no los puedo sumar». El botón vivía dentro de `segSelector` y
     las tarjetas de EOL no lo usan — no tienen chips de garantía porque al 50%
     el equipo NO es elegible para Assurant.

     Y es justo el producto que más se cotiza junto a otro: el cliente que se
     lleva la pieza de aparador pregunta qué más le sale a cuenta. */
  {
    const eolListo = { estado:'listo', sku:'100259554', producto:'WATCH FIT 4 AL NG',
                       precio:3499, precio50:1750, exhibe:1, stock:0 };
    const htmlEol = cardEol(eolListo);
    ok('la tarjeta del 50% ofrece sumar', htmlEol.indexOf('cotAgregar') >= 0,
       htmlEol.slice(0, 260));
    /* Con SU precio, el rebajado. Sumar el de lista en una pieza al 50% le
       cobraría al cliente el doble de lo que se le está ofreciendo. */
    ok('y con el precio rebajado, no el de lista',
       htmlEol.indexOf('1750') >= 0 && htmlEol.indexOf(',3499,') < 0, 'no lleva el 50%');
    /* Sin garantía: la propia tarjeta avisa de que al 50% no es elegible. Los
       importes de seguro van en cero para que no dependa de que el bloque de
       chips no exista. */
    /* Los importes de seguro van en CERO. Los precios «con seguro» salen iguales
       al base —`botonCot` cae en `p1||p0`— y da igual: sin chips nunca se elige
       otra cosa que el 0. Lo que no puede pasar es que aparezca un importe de
       garantía en un producto que no la admite. */
    ok('sin importes de seguro', /1750,1750,1750,0,0/.test(htmlEol),
       (htmlEol.match(/cotAgregar\([^)]*\)/) || [''])[0]);
    /* Y el renglón dice QUÉ pieza es: en la cuenta que se le lee al cliente, el
       mismo modelo nuevo y el de aparador son dos líneas iguales con distinto
       importe. */
    ok('el nombre dice que es la pieza de exhibición',
       htmlEol.indexOf('exhibici') >= 0, 'no lo dice');

    // Una pendiente de agotar stock todavía NO se vende al 50%: no hay qué sumar.
    const htmlPend = cardEol({ estado:'pendiente', sku:'900009', producto:'X', stock:3, exhibe:1 });
    ok('un EOL que aún no llega al 50% no ofrece sumar',
       htmlPend.indexOf('cotAgregar') < 0);
  }

  document.getElementById = getIdOrig;
  COT = [];
}

/* ── 12 · Los MSI de la cotización salen del TOTAL (10-sep-2026) ─────────
   Pedido en piso: «en la cotización no aparecen los msi».

   ⚠️ Aquí es donde más valen, y por eso esconderlos costaba ventas: los plazos
   se alcanzan por importe, y el importe de la cuenta entera es mayor que el de
   cualquier artículo suelto. Un reloj de $5,048 llega a 6 MSI; con un teléfono
   al lado la cuenta pasa de $20,000 y alcanza 18. El asesor tenía el argumento
   delante y la pantalla no se lo decía.

   ⚠️ Los umbrales viven en `msiPlazos` y NADA MÁS AHÍ. Estaban copiados en dos
   sitios —el badge de la tarjeta y el WhatsApp del producto— y esto habría sido
   el tercero. Con tres copias, mover el mínimo de 6 MSI se hace en dos y el que
   falta no da error: solo deja de ofrecer meses que el cliente sí tiene. */
{
  COT = [];

  /* ── Los umbrales, una sola vez ─────────────────────────────────────── */
  ok('menos de $1,500 no alcanza ningún plazo', msiPlazos(1499).length === 0,
     JSON.stringify(msiPlazos(1499)));
  ok('desde $1,500 hay 6 MSI', JSON.stringify(msiPlazos(1500)) === '[6]',
     JSON.stringify(msiPlazos(1500)));
  ok('desde $10,000 hay 6 y 12', JSON.stringify(msiPlazos(10000)) === '[6,12]',
     JSON.stringify(msiPlazos(10000)));
  ok('desde $20,000 hay 6, 12 y 18', JSON.stringify(msiPlazos(20000)) === '[6,12,18]',
     JSON.stringify(msiPlazos(20000)));

  /* ── El badge de la tarjeta no cambió al unificar ────────────────────
     `msiInfo` se reescribió sobre `msiPlazos`, así que lo que hay que probar
     es que sigue enseñando lo mismo: los DOS plazos más largos, el mayor
     primero, y el banco solo en los 18 —que es la única condición que
     restringe—. */
  const b6 = msiInfo(5048), b12 = msiInfo(12000), b18 = msiInfo(30047);
  ok('con $5,048 el badge ofrece solo 6 MSI',
     b6.indexOf('6 MSI') >= 0 && b6.indexOf('12 MSI') < 0, b6);
  ok('con $12,000 ofrece 12 y 6, el mayor primero',
     b12.indexOf('12 MSI') >= 0 && b12.indexOf('6 MSI') >= 0
       && b12.indexOf('12 MSI') < b12.indexOf('6 MSI'), b12);
  ok('con $30,047 ofrece 18 y 12, y NO baja a 6',
     b18.indexOf('18 MSI') >= 0 && b18.indexOf('12 MSI') >= 0
       && b18.indexOf('>6 MSI') < 0, b18);
  ok('el banco se nombra solo en los 18',
     b18.indexOf(MSI_18_BANCOS) >= 0 && b12.indexOf(MSI_18_BANCOS) < 0,
     b12 + ' || ' + b18);
  ok('sin importe no hay badge', msiInfo(0) === '', msiInfo(0));

  /* ── El panel: el plazo sale de la suma, no de cada artículo ─────────── */
  COT = [
    { sku:'100295900', producto:'WATCH FIT 5',  total:5048,  seguro:1549, anios:1 },
    { sku:'100269146', producto:'PURA 80 PRO', total:24999, seguro:0,    anios:0 }
  ];
  cotPintar();
  const panel = document.getElementById('cotMsi').innerHTML;
  ok('el panel dice 18 MSI aunque ningún artículo llegue solo',
     panel.indexOf('18 MSI') >= 0, panel);
  ok('y el reloj por su cuenta no llegaría', msiPlazos(5048).indexOf(18) < 0);

  /* ⚠️ Se repinta al quitar, no solo al abrir. Quitar el teléfono baja la
     cuenta a $5,048: unos 18 MSI que se quedaran de la cuenta anterior serían
     meses ofrecidos al cliente que ya no tiene. */
  cotQuitar(1);
  const tras = document.getElementById('cotMsi').innerHTML;
  ok('al quitar un artículo los MSI bajan con el total',
     tras.indexOf('18 MSI') < 0 && tras.indexOf('6 MSI') >= 0, tras);

  // Y vaciándola no queda ningún plazo colgado.
  cotQuitar(0);
  ok('la cotización vacía no ofrece plazos',
     document.getElementById('cotMsi').innerHTML === '',
     document.getElementById('cotMsi').innerHTML);

  /* ── El mensaje que se le manda al cliente ───────────────────────────── */
  COT = [
    { sku:'100295900', producto:'WATCH FIT 5',  total:5048,  seguro:1549, anios:1 },
    { sku:'100269146', producto:'PURA 80 PRO', total:24999, seguro:0,    anios:0 }
  ];
  let enviado = '';
  const openOrig = window.open;
  window.open = function(url){ enviado = decodeURIComponent(String(url)); };
  cotCompartir();
  window.open = openOrig;
  ok('el mensaje lleva los plazos', enviado.indexOf('MSI') >= 0, enviado.slice(0, 160));
  ok('los lleva TODOS, que en un mensaje sí caben',
     enviado.indexOf('6 MSI') >= 0 && enviado.indexOf('12 MSI') >= 0
       && enviado.indexOf('18 MSI') >= 0, enviado.slice(-160));
  /* El asterisco sin su nota es una restricción que el cliente no puede leer. */
  ok('y si hay 18, dice de qué bancos',
     enviado.indexOf(MSI_18_BANCOS) >= 0, enviado.slice(-160));
  ok('el total sigue siendo el de la cuenta',
     enviado.indexOf(money(30047)) >= 0, enviado.slice(-160));

  COT = [];
}

/* ── 15 · «1 año» sale marcado de entrada (22-sep-2026) ──────────────────
   Decisión de Ángel para subir el Assurant attach: la tarjeta abre cotizando
   con un año de seguro. Lo que se protege aquí es lo que falla callando:

   · que el número grande, los meses y el «Sumar» digan LO MISMO que el chip
     marcado. `cotSeguroElegido` lee el chip activo; si el precio de arriba
     fuera sin seguro y el chip dijera «1 año», se sumaría una cosa y se
     cantaría otra.
   · que el precio con seguro diga que lo incluye — si no, el asesor lo canta
     como precio del equipo — y en años de protección (1 contratado = 2).
   · que el tachado y el −% de la promo NO acompañen a un precio con seguro:
     $3,998 junto a un $3,999 tachado insinúa una rebaja que no existe.
   · y la única excepción: lo que no tiene rango de seguro abre en «Sin
     seguro». El M-Pencil NO lo es (Ángel, 22-sep: «va con seguro»; la regla de
     no ponerle seguro es de los combos) — se prueba para que nadie la reponga
     creyendo que falta. */
{
  const chipsDe = h => (h.match(/class="seg-chip( active)?"/g) || []);
  const activo  = h => chipsDe(h).findIndex(c => / active"/.test(c));

  // Un producto de $2,999 en promo, regular $3,999. El seguro va por el precio
  // REGULAR (así lo cobra Assurant): se pregunta a la misma tabla del tablero.
  const seg = seguroPara(3999, '900001').p1;
  const h = segSelector('900001', 3999, 2999, '', 3999, 25, 'PRUEBA TEL');
  ok('el chip marcado de entrada es «1 año»', activo(h) === 1, 'activo=' + activo(h));
  ok('el precio grande ya trae el seguro', h.indexOf('>' + money(2999 + seg) + '<') >= 0, h.slice(0, 300));
  ok('y dice que lo incluye, en años de protección',
     h.indexOf('con seguro · protege 2 años') >= 0);
  ok('los meses salen del precio con seguro', h.indexOf(money(Math.ceil((2999 + seg) / 6))) >= 0);
  ok('el tachado de la promo nace oculto', /class="precio-reg" style="display:none"/.test(h));
  ok('y el −% también', /class="ah" style="display:none"/.test(h));

  const lapiz = segSelector('900050', 1999, 1999, '', null, 0, 'm-pencil de prueba');
  ok('el M-Pencil vendido solo abre con «1 año», como todo', activo(lapiz) === 1, 'activo=' + activo(lapiz));
  ok('y con sus tres chips', chipsDe(lapiz).length === 3);

  const barato = segSelector('900051', 99, 99, '', null, 0, 'CABLE');
  ok('sin rango de seguro abre en «Sin seguro»', activo(barato) === 0 && chipsDe(barato).length === 1,
     chipsDe(barato).length + ' chips, activo=' + activo(barato));

  // El render entero: toda tarjeta con precio sale con UN solo chip marcado.
  filtroActivo = 'promo'; busqueda = ''; render();
  const bloques = app.innerHTML.split('class="seg-sel"').slice(1);
  ok('cada tarjeta de precio tiene exactamente un chip marcado',
     bloques.length > 0 && bloques.every(b => (b.split('class="seg-chips"')[1] || '')
       .split('</div>')[0].split(' active"').length === 2), bloques.length + ' bloques');
  filtroActivo = 'inicio'; render();
}

/* ── 16 · El nombre en lenguaje de cliente, conectado (22-sep-2026) ──────
   Las reglas las prueba nombres_cliente.js. Aquí, que el tablero las USE en
   los tres sitios que importan —lo que se pinta, lo que se busca y lo que se
   le manda al cliente— sin perder la descripción del sistema, que es la que
   trae la etiqueta de la caja. */
{
  const D1 = 'AUDIF IN EAR HW F-BUDS PRO 4 VD';
  const h = nomProd(D1);
  ok('la tarjeta dice el modelo para el cliente', h.indexOf('>Audífonos Huawei FreeBuds Pro 4<') >= 0, h);
  ok('el color va abajo, traducido', h.indexOf('>Verde<') >= 0, h);
  ok('y la descripción del sistema sigue ahí, para empatar la caja', h.indexOf('>' + D1 + '<') >= 0, h);
  ok('al cliente le llega el nombre que entiende', nomLinea(D1) === 'Audífonos Huawei FreeBuds Pro 4 · Verde', nomLinea(D1));

  // El buscador: por las dos formas y sin acentos.
  const bOrig = busqueda;
  for(const q of ['audifonos', 'audífonos', 'freebuds', 'f-buds', 'verde', '900001']){
    busqueda = q;
    ok('buscar «' + q + '» lo encuentra', coincide(D1, '900001'));
  }
  busqueda = 'freeclip'; ok('y no encuentra otro producto', !coincide(D1, '900001'));
  busqueda = bOrig;

  // Sin nombres.js (no llegó el <script>): se pinta lo crudo, no se rompe.
  const guard = global.nombreCliente; delete global.nombreCliente; _nomMemo.clear();
  let crudo = '', err = null;
  try { crudo = nomProd(D1); } catch(e){ err = e.message; }
  ok('sin nombres.js la tarjeta no revienta', !err, err);
  ok('y pinta la descripción tal cual', crudo.indexOf('>' + D1 + '<') >= 0, crudo);
  global.nombreCliente = guard; _nomMemo.clear();

  // Las tarjetas de verdad lo usan.
  filtroActivo = 'promo'; busqueda = ''; render();
  ok('las tarjetas de precio pintan el nombre con nomProd', app.innerHTML.indexOf('class="nom-modelo"') >= 0);
  filtroActivo = 'inicio'; render();
}
