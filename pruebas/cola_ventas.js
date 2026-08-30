/* ============================================================
   La venta llega a Supabase aunque el Apps Script no conteste
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Existe por el cambio del 17-ago-2026 (fase 5). Hasta v168 la venta iba al
   Sheet y solo llegaba a Supabase SI el Sheet confirmaba. Como el stock del
   tablero se calcula descontando de la tabla `ventas` DE SUPABASE, un Apps
   Script caído significaba inventario que no descuenta — sin un solo error.

   Las dos comprobaciones de aquí son las que, rotas, no dan ninguna señal:

     1. Una venta capturada sin red acaba en la cola de Supabase.
     2. Lo que quedó en la cola VIEJA se rescata al actualizar.

   La 2 solo puede fallar una vez, el día que cada teléfono pasa a v169, y para
   entonces ya no hay forma de saber qué se perdió: son ventas que existen en la
   hoja y no en Supabase, o sea stock que no baja y comisiones que no se pagan.

   `fetch` rechaza SIEMPRE en este entorno, que es justo el escenario que
   importa: si la venta llega igual a la cola, la inversión está bien hecha.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');
const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');

const { crearEntorno } = require('./dom.js');

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal'];
const STORE  = { store_id:'1217', nombre:'Angelopolis', gas_url:'https://gas.example/exec',
                 gas_token:'t', vendedores:EQUIPO };
const EMP    = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'asesor' };

/* El entorno vive en `dom.js` desde el 17-ago-2026: respeta el orden del
   documento y trae un classList de verdad. Aquí solo se dice con qué sesión
   arranca cada escenario. */
function arrancar(extraLS){
  const ent = crearEntorno({
    html,
    ruta: '/t/captura_series.html',
    ls: Object.assign({ hes_store: JSON.stringify(STORE),
                        hes_empleado: JSON.stringify(EMP) }, extraLS || {})
  });
  return Object.assign(ent, {
    colaSb:  () => ent.lsJson('hes1217_sb_pend') || [],
    colaGas: () => ent.lsJson('hes1217_pending') || []
  });
}

const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra ? ' -> ' + extra : '')); };

/* ── 1 · Capturar sin red deja la venta en la cola de Supabase ──────────── */
{
  const s = arrancar();
  ok('la pantalla arranca', !s.err, s.err);
  if(!s.err){
    s.el('serie').value  = 'SERIE-PRUEBA-1';
    s.el('sku').value    = '900001';
    s.el('precio').value = '4999';
    s.el('desc').value   = 'Equipo de prueba';
    s.caja.setVend(EQUIPO[1]);            // ya eligió su nombre
    s.el('btnAdd').onclick();            // abre el modal del seguro
    s.caja.finalizarVenta(true);          // "con Assurant"

    const cola = s.colaSb();
    ok('la venta entra en la cola de Supabase aunque no haya red',
       cola.length === 1, 'la cola quedó con ' + cola.length);
    if(cola.length){
      ok('y con la serie correcta', cola[0].p_serie === 'SERIE-PRUEBA-1', cola[0].p_serie);
      /* El seguro es lo que decide el Assurant. `false` y `null` NO son lo
         mismo: null es "no se sabe" y hunde el attach si se confunden. */
      ok('y con el seguro tal cual se marcó', cola[0].p_seguro === true, String(cola[0].p_seguro));
      ok('y con el id de captura, que es lo único que permite borrarla luego',
         !!cola[0].p_captura_id, 'llegó vacío');
    }
    /* Y a la hoja NO va nada (fase 6, v170). Se comprueba explícitamente: si
       alguien reintrodujera la doble escritura, volvería a haber dos verdades
       —que es lo que esta migración vino a resolver— y nada daría error. */
    ok('y a la hoja ya no se le manda nada', s.colaGas().length === 0,
       'la cola del Sheet quedó con ' + s.colaGas().length);
  }
}

/* ── 2 · Lo que quedó en la cola vieja se rescata ───────────────────────── */
{
  const viejas = [
    { id:'i1', fecha:'16/8/2026', hora:'12:00', serie:'VIEJA-1', sku:'900001',
      desc:'Pendiente de ayer', precio:'1999', vend:EQUIPO[0], seguro:false },
    { id:'i2', fecha:'16/8/2026', hora:'12:05', serie:'VIEJA-2', sku:'900002',
      desc:'Otra pendiente', precio:'2999', vend:EQUIPO[0], seguro:true }
  ];
  const s = arrancar({ hes1217_pending: JSON.stringify(viejas) });
  ok('la pantalla arranca con la cola vieja', !s.err, s.err);
  if(!s.err){
    const cola = s.colaSb();
    ok('las capturas de la cola vieja se rescatan a Supabase',
       cola.length === 2, 'se rescataron ' + cola.length + ' de 2');
    ok('conservando la serie', cola.length === 2 && cola[0].p_serie === 'VIEJA-1');
    /* Sin esto, esas ventas subirían solo a la hoja: stock que no baja y
       comisiones que no se pagan, sin ningún aviso. */
    ok('y la marca queda puesta para no reencolarlas en cada arranque',
       !!s.LS['hes1217_cola_a_supabase']);
  }
}

/* ── 3 · Y no se rescatan dos veces ─────────────────────────────────────── */
{
  const viejas = [{ id:'i1', fecha:'16/8/2026', hora:'12:00', serie:'VIEJA-1', sku:'900001',
                    desc:'Pendiente', precio:'1999', vend:EQUIPO[0], seguro:false }];
  const s = arrancar({ hes1217_pending: JSON.stringify(viejas),
                       hes1217_cola_a_supabase: '1755400000000' });
  if(!s.err){
    ok('con la marca ya puesta, la cola vieja no se vuelve a encolar',
       s.colaSb().length === 0, 'se encolaron ' + s.colaSb().length);
  }
}

/* ── 4 · La prioridad de precio, en un solo sitio ───────────────────────
   `precioDeCatalogo_` se extrajo el 17-ago-2026 para que la captura y la
   corrección de una venta no tengan dos ideas del precio bueno. Al extraerla se
   tocó `aplicarProducto`, que es el camino de escanear Y el de teclear, y no lo
   cubría ninguna prueba.

   La regla es la de la cadena 3 del MAPA y se repite en el tablero y en el
   Apps Script: EOL al 50% manda sobre promoción, y promoción sobre regular.
   Invertirla cobraría de más a un cliente con el equipo en la mano. */
{
  const s = arrancar();
  if(!s.err){
    const hoy = new Date();
    const iso = hoy.getFullYear() + '-' + String(hoy.getMonth()+1).padStart(2,'0')
              + '-' + String(hoy.getDate()).padStart(2,'0');
    const FICHA = "({ s:'900001', d:'Equipo de prueba', p:10000 })";

    // Sin nada: el regular
    ok('sin promo ni EOL se cobra el precio regular',
       s.correr('precioDeCatalogo_(' + FICHA + ').precio') === '10000');

    // Con promo vigente: la promo
    s.correr("PROMOS['900001'] = { pp:'8500', d1:'" + iso + "', d2:'" + iso + "' };");
    ok('con promoción vigente se cobra la promoción',
       s.correr('precioDeCatalogo_(' + FICHA + ').precio') === '8500',
       s.correr('precioDeCatalogo_(' + FICHA + ').precio'));

    // Con las dos a la vez: manda el EOL, NUNCA la promo
    s.correr("EOL_VENTA['900001'] = 5000;");
    ok('con EOL y promoción a la vez manda el EOL al 50%',
       s.correr('precioDeCatalogo_(' + FICHA + ').precio') === '5000',
       s.correr('precioDeCatalogo_(' + FICHA + ').precio'));
    ok('y se sabe de dónde salió el precio, para poder decirlo en pantalla',
       s.correr('precioDeCatalogo_(' + FICHA + ').motivo') === 'eol',
       s.correr('precioDeCatalogo_(' + FICHA + ').motivo'));
  }
}

/* ── 5 · La pieza de exhibición viaja hasta la nube ─────────────────────
   El interruptor decide DOS cosas: qué precio se cobra y de qué contador se
   descuenta la pieza. Si `exhibicion` se cayera en cualquier escalón —del
   formulario al item, del item a la cola, de la cola al cuerpo de la RPC— la
   venta se guardaría como de bodega: descontaría una caja que sigue en el
   almacén y dejaría el aparador ocupado por una pieza que ya salió.

   Es la cadena 1 del MAPA otra vez: lo que no se nombra en cada escalón se
   pierde en silencio. Por eso se comprueba el extremo final, el cuerpo que
   sale hacia Supabase, y no los intermedios. */
{
  const s = arrancar();
  if(!s.err){
    s.el('serie').value  = 'SERIE-EXHIB-1';
    s.el('sku').value    = '900001';
    s.el('precio').value = '2500';
    s.el('desc').value   = 'EOL de piso';
    s.caja.setVend(EQUIPO[1]);
    s.el('exhChk').checked = true;   // «es la de exhibición»
    s.el('btnAdd').onclick();
    s.caja.finalizarVenta(false);

    const cola = s.colaSb();
    ok('la marca de exhibición llega al cuerpo que va a Supabase',
       cola.length === 1 && cola[0].p_de_exhibicion === true,
       cola.length ? String(cola[0].p_de_exhibicion) : 'la cola quedó vacía');
  }
}

/* ── 6 · Y una venta normal NO se marca ─────────────────────────────────
   La otra mitad, y no es simétrica de la de arriba: si esto fallara, TODAS las
   ventas descontarían del aparador en vez de la bodega. El stock de almacén
   dejaría de bajar nunca y el tablero prometería cajas que no existen. */
{
  const s = arrancar();
  if(!s.err){
    s.el('serie').value  = 'SERIE-NORMAL-1';
    s.el('sku').value    = '900001';
    s.el('precio').value = '5000';
    s.caja.setVend(EQUIPO[1]);
    s.el('btnAdd').onclick();
    s.caja.finalizarVenta(true);

    const cola = s.colaSb();
    ok('una venta normal se manda explícitamente como NO de exhibición',
       cola.length === 1 && cola[0].p_de_exhibicion === false,
       cola.length ? String(cola[0].p_de_exhibicion) : 'la cola quedó vacía');
  }
}

/* Los bloques que siguen tocan handlers `async` (el onclick de «Ventas del
   día» hace `await flushSupabase()` antes de abrir el panel), así que hay que
   esperarlos de verdad. Comprobar justo después de pulsar daba un falso rojo:
   el panel todavía no se había abierto. */
(async function(){

/* ── 7 · Quien puede corregir, puede llegar a la lista ──────────────────
   El ✏️ vive DENTRO del panel «Ventas del día», que hasta v175 solo abría la
   persona designada en `hoja_auth`. O sea que el subgerente tenía permiso de
   corregir —el servidor se lo concede— y ninguna forma de llegar al botón.
   Una puerta daba el permiso y la otra lo bloqueaba, sin decir nada.

   Se prueban las dos direcciones: sin ellas, "arreglarlo" abriendo el panel a
   todos pasaría igual de desapercibido. */
{
  const sub = { empno:'1000002', nombre:EQUIPO[1], puesto:'Subgerente de Tienda' };
  const s = arrancar({ hes_empleado: JSON.stringify(sub) });
  if(!s.err){
    ok('el subgerente sí puede abrir Ventas del día',
       s.el('btnCsv').style.display !== 'none',
       'quedó display=' + s.el('btnCsv').style.display);

    /* Y AL PULSARLO tiene que abrirse. Ver el botón y poder usarlo son dos
       preguntas distintas, y el 17-ago-2026 se cambió solo la primera: el
       gerente veía «Ventas del día» y al tocarlo le decía que no tenía permiso.

       SE PULSA EL BOTÓN DE VERDAD, no se llama a `puedeVerVentas_()`. Esa
       comprobación habría dado verde con el fallo puesto, porque la función
       estaba bien — lo que no la usaba era el handler. */
    await s.el('btnCsv').onclick();
    ok('y al pulsarlo se abre la lista, no un aviso de permiso',
       s.el('vdPanel').classList.contains('show'));
  }
}
{
  // Asesor que NO es el de `hoja_auth`: sigue sin ver la lista, como siempre.
  const ases = { empno:'1000003', nombre:EQUIPO[0], puesto:'Asesor de Tienda' };
  const s = arrancar({ hes_empleado: JSON.stringify(ases) });
  if(!s.err){
    ok('y un asesor cualquiera sigue sin verla',
       s.el('btnCsv').style.display === 'none',
       'quedó display=' + s.el('btnCsv').style.display);
  }
}

/* ── 8 · Las entregas se distinguen en «Ventas del día» ─────────────────
   Una entrega de preventa o traspaso NO es una venta de hoy: el cliente pagó
   semanas antes, no cuenta para el Assurant, no descuenta stock y no se puede
   corregir con el ✏️. Sin distintivo, quien cuadra la caja contra el POS busca
   renglones que no va a encontrar.

   Se comprueba también lo que NO debe pasar: que la venta normal siga siendo
   la única con ✏️. Las entregas no tienen `captura_id` —las crea
   `apartado_entregar`, no la app— y por eso el botón no les sale; si algún día
   lo tuvieran, el servidor las rechaza igual, pero el asesor se llevaría el
   viaje en balde. */
{
  const sub = { empno:'1000002', nombre:EQUIPO[1], puesto:'Subgerente de Tienda' };
  const s = arrancar({ hes_empleado: JSON.stringify(sub) });
  if(!s.err){
    s.correr(`
      _vdVentas = [
        { serie:'S-NORMAL', sku:'900001', desc:'Venta normal', precio:'1000',
          vend:'X', hora:'10:00', captura_id:'i1', foto:false, entrega:'', clase:'venta' },
        { serie:'S-PREVENTA', sku:'900002', desc:'Entrega de preventa', precio:'2000',
          vend:'Y', hora:'11:00', captura_id:'', foto:false, entrega:'preventa',
          cobrado:'2026-07-20', clase:'entrega' },
        { serie:'S-TRASPASO', sku:'900003', desc:'Entrega de traspaso', precio:'3000',
          vend:'Z', hora:'12:00', captura_id:'', foto:false, entrega:'traspaso',
          clase:'entrega' },
        { serie:'', sku:'900004', desc:'Apartado cobrado hoy', precio:'4000',
          vend:'W', hora:'13:00', captura_id:'', foto:false, entrega:'preventa',
          cobrado:'2026-08-17', clase:'cobro' }
      ];
      _vdFecha = new Date();
      pintarVentasDia();
    `);
    const lista = s.el('vdLista').innerHTML || '';

    ok('la entrega de preventa se marca', lista.indexOf('preventa') >= 0);
    ok('y la de traspaso también, con su propia etiqueta',
       lista.indexOf('traspaso') >= 0);
    ok('las tres filas de apartado llevan distintivo, la venta normal no',
       (lista.match(/vd-ent/g) || []).length === 3,
       'salieron ' + (lista.match(/vd-ent/g) || []).length);

    /* El cobro es lo contrario de la entrega: el dinero entró HOY y el Assurant
       ya lo cuenta. Si no sale en la lista, el porcentaje del día sube y las
       filas no lo explican — el descuadre que esto cierra. */
    ok('el apartado cobrado hoy se marca como tal',
       lista.indexOf('apartado cobrado hoy') >= 0);
    ok('y como todavía no tiene equipo, se dice en vez de dejar el hueco',
       lista.indexOf('sin equipo todavía') >= 0);
    ok('solo la venta normal ofrece el ✏️ de corregir',
       (lista.match(/abrirEditarVenta/g) || []).length === 1,
       'salieron ' + (lista.match(/abrirEditarVenta/g) || []).length);

    /* La fecha del cobro es lo que dice EN QUÉ CORTE está el ticket. Sin ella,
       la etiqueta avisa de que la venta es rara pero no dónde buscarla. */
    ok('y la entrega dice cuándo se cobró',
       lista.indexOf('cobrado 20 jul') >= 0, lista.slice(0, 400));

    const pie = s.el('vdAyuda').innerHTML || '';
    ok('y el pie dice cuántas no están en el corte de hoy',
       pie.indexOf('2 son entregas') >= 0, pie);
    ok('y cuántos apartados se cobraron hoy, que sí cuentan',
       pie.indexOf('1 apartado cobrado hoy') >= 0, pie);

    /* El contador de arriba separa lo que SALIÓ de la tienda de lo que se
       COBRÓ. Sumarlos daría un número que no es ni una cosa ni la otra. */
    ok('el contador no cuenta un cobro como equipo entregado',
       (s.el('vdN').textContent || '').indexOf('3 equipos') === 0,
       s.el('vdN').textContent);
    ok('y dice aparte cuántos cobros hubo',
       (s.el('vdN').textContent || '').indexOf('1 cobro') > 0,
       s.el('vdN').textContent);
  }
}

/* ── 9 · Agrupar por venta NO cambia lo que se cuenta ───────────────────
   20-ago-2026. El asesor cierra la venta a mano y los articulos capturados
   antes quedan juntos. Es SOLO presentacion.

   Lo que se comprueba es lo que se rompe sin ruido: que cada articulo siga
   siendo una fila con SU seguro. Si alguien «simplificara» mandando una fila
   por venta, el Assurant —que cuenta por articulo— se movería solo, y la regla
   de combos de la tienda («2 articulos = 1 con seguro») dejaría de tener
   sentido. Nadie ataría ese cambio de KPI a esto meses despues. */
{
  const s = arrancar();
  if(!s.err){
    s.caja.setVend(EQUIPO[1]);

    const capturar = (serie, sku, precio, seguro) => {
      s.el('serie').value  = serie;
      s.el('sku').value    = sku;
      s.el('precio').value = precio;
      s.el('desc').value   = 'Equipo ' + sku;
      s.el('btnAdd').onclick();
      s.caja.finalizarVenta(seguro);
    };

    // Un cliente que se lleva dos equipos: uno con seguro y otro sin él.
    capturar('S-GRUPO-1', '900001', '9999', true);
    capturar('S-GRUPO-2', '900002', '4999', false);

    const cola = s.colaSb();
    ok('los dos articulos se guardan por separado', cola.length === 2,
       'la cola quedo con ' + cola.length);
    ok('y comparten el mismo grupo',
       cola.length === 2 && !!cola[0].p_grupo && cola[0].p_grupo === cola[1].p_grupo,
       cola.length === 2 ? (cola[0].p_grupo + ' vs ' + cola[1].p_grupo) : '');
    /* LA MITAD QUE IMPORTA: cada uno conserva SU seguro. Agrupar no puede
       convertir dos articulos en «una venta con seguro». */
    ok('cada articulo conserva su propio seguro',
       cola.length === 2 && cola[0].p_seguro === true && cola[1].p_seguro === false,
       cola.length === 2 ? (cola[0].p_seguro + ' / ' + cola[1].p_seguro) : '');
    ok('y su propio SKU, para que el stock descuente los dos',
       cola.length === 2 && cola[0].p_sku === '900001' && cola[1].p_sku === '900002');

    // Al cerrar la venta, el siguiente articulo empieza otra.
    s.caja.cerrarVentaGrupo();
    capturar('S-GRUPO-3', '900001', '9999', true);
    const c2 = s.colaSb();
    ok('tras cerrar, el siguiente articulo abre una venta nueva',
       c2.length === 3 && c2[2].p_grupo !== c2[0].p_grupo,
       c2.length === 3 ? (c2[2].p_grupo + ' vs ' + c2[0].p_grupo) : 'cola de ' + c2.length);
  }
}

/* ── 10 · La venta abierta no se hereda entre vendedores ────────────────
   Olvidarse de cerrar es el unico fallo de este diseno y no da error: pega la
   compra del siguiente cliente a la anterior. El olvido mas probable es el
   cambio de asesor en el mostrador, asi que ahi se cierra sola. */
{
  const s = arrancar();
  if(!s.err){
    s.caja.setVend(EQUIPO[1]);
    s.el('serie').value = 'S-VEND-1'; s.el('sku').value = '900001';
    s.el('precio').value = '999';
    s.el('btnAdd').onclick(); s.caja.finalizarVenta(true);
    const g1 = s.colaSb()[0].p_grupo;

    s.caja.setVend(EQUIPO[0]);            // entra otro asesor
    s.el('serie').value = 'S-VEND-2'; s.el('sku').value = '900001';
    s.el('precio').value = '999';
    s.el('btnAdd').onclick(); s.caja.finalizarVenta(true);
    const g2 = s.colaSb()[1].p_grupo;

    ok('al cambiar de vendedor, la venta abierta no se hereda', g1 !== g2,
       g1 + ' vs ' + g2);
  }
}

if(fallos.length){
  console.log('cola de ventas: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('cola de ventas: la venta llega a Supabase sin red, y la cola vieja se rescata');

})();
