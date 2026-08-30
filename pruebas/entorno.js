/* ============================================================
   Navegador de mentira + tienda de mentira
   ============================================================
   Lo usan las pruebas que corre `verificar.py` en cada commit.

   Los datos son INVENTADOS a propósito. El repo es público y los reales
   traen nombres y teléfonos de clientes; además, un fixture fijo detecta
   cambios de comportamiento, cosa que unos datos que cambian cada día no
   pueden hacer.

   El fixture cubre los cinco estados de `estadoSku` y los casos que ya
   rompieron algo alguna vez. Si añades un estado, añade aquí su fila.
   ============================================================ */
'use strict';

function domFalso(){
  const els = {};
  function el(id){
    if(!els[id]) els[id] = { id, style:{}, dataset:{}, value:'', textContent:'', innerHTML:'',
      classList:{ add(){}, remove(){}, toggle(){}, contains(){ return false; } },
      querySelectorAll:()=>[], addEventListener(){}, appendChild(){}, closest:()=>null,
      scrollIntoView(){}, focus(){}, insertBefore(){}, remove(){}, onclick:null, children:[] };
    return els[id];
  }
  global.window = global;
  global.addEventListener = ()=>{};
  global.location = { hash:'', pathname:'/t/tablero.html', search:'' };
  global.history = { replaceState:(a,b,u)=>{ global.location.hash = u; } };
  // Node 21+ trae su propio `navigator` de solo lectura, así que no basta con
  // asignarlo: hay que redefinir la propiedad.
  Object.defineProperty(global, 'navigator', { configurable:true, writable:true,
    value:{ serviceWorker:{ addEventListener(){}, ready:{then(){return{catch(){}};}},
                            register(){ return {catch(){}}; } } } });
  global.document = { getElementById:el, querySelectorAll:()=>[], querySelector:()=>null,
    createElement:()=>el('tmp'+Math.random()), head:el('head'), body:el('body'),
    readyState:'complete', addEventListener(){} };
  const guardado = {};
  /* Con PUESTO desde el 9-ago-2026: el tablero decide con él quién ve la
     sección de Resurtir. Se entra como gerente para que las pruebas recorran
     la app completa; el caso del asesor se prueba aparte, bajando
     PUEDE_GESTIONAR a mano (ver casos_tablero.js, bloque 7). */
  global.localStorage = { getItem:k=> k==='hes_empleado'
                                    ? '{"empno":"1","nombre":"Prueba Uno","puesto":"Gerente de Tienda"}'
                                    : (k in guardado ? guardado[k] : null),
                          setItem:(k,v)=>{ guardado[k]=String(v); }, removeItem:k=>{ delete guardado[k]; } };
  global.sessionStorage = { getItem:()=>null, setItem(){}, removeItem(){} };
  global.fetch = ()=>Promise.reject(new Error('sin red en las pruebas'));
  global.alert = ()=>{}; global.confirm = ()=>true;
  global.AbortController = class { constructor(){ this.signal = {}; } abort(){} };
  global.scrollTo = ()=>{}; global.setInterval = ()=>0; global.setTimeout = ()=>0;
  return el;
}

// Un mes por delante, para que las promos del fixture nunca venzan solas
function dentroDe(dias){
  const d = new Date(Date.now() + dias*86400000);
  return d.getFullYear()+'-'+String(d.getMonth()+1).padStart(2,'0')+'-'+String(d.getDate()).padStart(2,'0');
}

const TIENDA = {
  inventario: [
    // hay: piezas en bodega
    { sku:'900001', descripcion:'PRUEBA TEL CON STOCK',      precio:9999,  onhand:3, vendido:0, stock:3, exhibicion:1, exh_vendida:0 },
    // hay, pero sin exhibición
    { sku:'900002', descripcion:'PRUEBA TEL SIN EXHIBIR',    precio:4999,  onhand:2, vendido:1, stock:1, exhibicion:0, exh_vendida:0 },
    // piso: activo, solo la de exhibición -> NO se vende, sí se aparta
    { sku:'900003', descripcion:'PRUEBA SOLO PIEZA DE PISO', precio:2999,  onhand:0, vendido:0, stock:0, exhibicion:1, exh_vendida:0 },
    // 50: EOL con pieza de piso -> se vende al 50%, no se aparta
    { sku:'900004', descripcion:'PRUEBA EOL CON PISO',       precio:1999,  onhand:0, vendido:0, stock:0, exhibicion:1, exh_vendida:0 },
    // no: EOL y agotado -> ni se vende ni se trae
    { sku:'900005', descripcion:'PRUEBA EOL AGOTADO',        precio:1499,  onhand:0, vendido:0, stock:0, exhibicion:0, exh_vendida:0 },
    // traer: cero por todos lados y no es EOL
    { sku:'900006', descripcion:'PRUEBA SE TRAE DE OTRA',    precio:7999,  onhand:0, vendido:0, stock:0, exhibicion:0, exh_vendida:0 },
    // sin precio: el apartado tiene que pedirlo
    { sku:'900007', descripcion:'PRUEBA SIN PRECIO',         precio:null,  onhand:0, vendido:0, stock:0, exhibicion:0, exh_vendida:0 },
  ],
  eol: [ { sku:'900004', precio:1999, precio_efectivo:1999 },
         { sku:'900005', precio:1499, precio_efectivo:1499 } ],
  eol_venta: {},
  // Lista, no diccionario: así la manda `tablero_todo`
  promos: [
    { sku:'900001', producto:'PRUEBA TEL CON STOCK', precio_reg:9999, precio_pro:8499,
      vigente_desde:dentroDe(-5), vigente_hasta:dentroDe(30), estatus:'', msi:null },
    // promo de un SKU que NUNCA ha tenido fila de inventario: tiene que salir
    // en Resurtir marcado "nunca ha llegado" (8-ago-2026)
    { sku:'900099', producto:'PRUEBA PROMO SIN INVENTARIO', precio_reg:5999, precio_pro:4999,
      vigente_desde:dentroDe(-5), vigente_hasta:dentroDe(30), estatus:'', msi:null },
  ],
  bundles: [], avisos: [],
  apartados: [
    { id:1, sku:'900006', tipo:'traspaso', color:'PRUEBA SE TRAE DE OTRA', cliente:'Cliente Uno',
      telefono:'2220000001', piezas:1, con_seguro:true,  estatus:'Apartado', vendedor:'Prueba Uno',
      creado_en:'2026-08-01T10:00:00Z', precio:7999, transaccion:'111', serie:null,
      origen:'Otra Tienda', promesa:dentroDe(-3), dias_tarde:3, cupo:null, apartadas:1 },   // con la fecha pasada
    { id:2, sku:'900006', tipo:'traspaso', color:'PRUEBA SE TRAE DE OTRA', cliente:'Cliente Dos',
      telefono:'2220000002', piezas:1, con_seguro:false, estatus:'Asignado', vendedor:'Prueba Uno',
      creado_en:'2026-08-02T10:00:00Z', precio:7999, transaccion:'222', serie:'SERIE0002',
      origen:'Otra Tienda', promesa:dentroDe(2), dias_tarde:-2, cupo:null, apartadas:1 },
    { id:3, sku:'900001', tipo:'preventa', color:'PRUEBA TEL CON STOCK', cliente:'Cliente Tres',
      telefono:'2220000003', piezas:1, con_seguro:true,  estatus:'Entregado', vendedor:'Prueba Uno',
      creado_en:'2026-07-20T10:00:00Z', precio:9999, transaccion:'333', serie:'SERIE0003',
      origen:null, promesa:null, dias_tarde:null, cupo:null, apartadas:1 },
    { id:4, sku:'900002', tipo:'traspaso', color:'PRUEBA TEL SIN EXHIBIR', cliente:'Cliente Cuatro',
      telefono:'2220000004', piezas:1, con_seguro:false, estatus:'Cancelado', vendedor:'Prueba Uno',
      creado_en:'2026-07-25T10:00:00Z', precio:4999, transaccion:'444', serie:null,
      origen:'Otra Tienda', promesa:null, dias_tarde:null, cupo:null, apartadas:0 },
  ],
  ventas_hoy: [ { vendedor:'Prueba Uno', con_seguro:2, sin_seguro:2 },
                { vendedor:'Prueba Dos', con_seguro:0, sin_seguro:3 } ],
};

module.exports = { domFalso, TIENDA, dentroDe };
