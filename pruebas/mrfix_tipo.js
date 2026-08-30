/* ============================================================
   Mr Fix: cada concepto a su tabla, y un ticket es UNA captura
   ============================================================
   Corre en cada commit desde `verificar.py`.

   Un ticket de Mr Fix puede llevar una mica Y un cambio de pantalla. La foto,
   el número y la fecha son del PAPEL; el producto y el importe son de cada
   línea. Por eso el panel captura un ticket con N conceptos dentro, y no un
   concepto por captura: así ese ticket se fotografía una vez y no dos.

   Lo que esta prueba vigila es lo que hay al final de esa decisión:

     · cada concepto se guarda con SU función, y por tanto en SU tabla;
     · un ticket mixto manda las dos llamadas con el MISMO `captura_id`, para
       que las dos queden ligadas a la única foto que se sube.

   Y no es cosmético. `accesorios_reporte` arma el pegado del Excel regional
   leyendo `accesorios_ventas`; una reparación guardada con `accesorio_guardar`
   entra ahí como venta de accesorio, mueve las comisiones de todo el equipo y
   el importe de una hoja que comparten diez tiendas. No da error en ningún
   sitio: se vería, si acaso, al cuadrar la región semanas después.

   Por eso mira LAS LLAMADAS que salen a la red, no la pantalla. Es el único
   punto donde la decisión ya no se puede deshacer.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const RUTA = path.join(__dirname, '..', 'captura_series.html');
const html = fs.readFileSync(RUTA, 'utf8');

const { crearEntorno } = require('./dom.js');

const EQUIPO = ['Jorge Medina Rejon', 'Luis de Jesus Ortega Vidal'];
const STORE  = { store_id:'1217', nombre:'Angelopolis', gas_url:'', gas_token:'tok12345',
                 vendedores:EQUIPO };
const EMP    = { empno:'2', nombre:'Luis de Jesus Ortega Vidal', puesto:'gerente' };

const esperar = () => new Promise(r => setTimeout(r, 30));

/* Captura un ticket con los conceptos pedidos y devuelve las llamadas RPC que
   salieron, con su cuerpo. `conceptos` es una lista de 'acc' | 'rep'. */
async function capturar(conceptos){
  const llamadas = [];
  const fetchFalso = (url, opciones) => {
    const fn = String(url).split('/rpc/')[1] || String(url);
    let body = {};
    try{ body = JSON.parse((opciones && opciones.body) || '{}'); }catch(e){}
    llamadas.push({ fn, body });
    let cuerpo = [];
    if(fn === 'accesorios_catalogo_lista'){
      cuerpo = [{ id:1, nombre:'MICA HR', articulo:'43739-MICAHR', precio:149, sku:'43739', orden:10 }];
    }else if(fn === 'accesorio_guardar' || fn === 'reparacion_guardar'){
      cuerpo = { ok:true, id:1, importe:149 };
    }else if(fn === 'venta_foto_guardar'){
      cuerpo = { ok:true };
    }
    return Promise.resolve({
      ok:true, status:200,
      json: () => Promise.resolve(cuerpo),
      text: () => Promise.resolve(JSON.stringify(cuerpo))
    });
  };

  const ent = crearEntorno({
    html, ruta:'/t/captura_series.html', fetch: fetchFalso,
    ls: { hes_store: JSON.stringify(STORE), hes_empleado: JSON.stringify(EMP) }
  });
  if(ent.err) return { error: ent.err };

  try{
    /* `abrirAcc` es async: pide el catalogo con await. Sin esperarla, el
       selector de producto sigue vacio y la linea se cae en la validacion, no
       en la rama que esta prueba quiere mirar. */
    ent.correr('abrirAcc();');
    await esperar();

    // Lo del TICKET, una sola vez
    ent.el('accTicket').value = '33999';
    ent.el('accFecha').value  = '2026-08-24';

    // Y cada concepto, agregado a la lista
    for(const t of conceptos){
      ent.correr('accTipo(' + JSON.stringify(t) + ');');
      ent.el('accPrecio').value = (t === 'rep') ? '850' : '149';
      /* El producto se deja puesto TAMBIEN al agregar una reparacion, aunque
         ahi ni se pregunte. Es el estado real del panel despues de meter un
         accesorio, y es lo que hace fuerte esta prueba: si el tipo se ignorara,
         con el producto vacio la linea se caeria en la validacion y el fallo se
         leeria como «falta el producto». Con el producto puesto, una reparacion
         mal enrutada llega hasta `accesorio_guardar` — el fallo de verdad, el
         que acaba en el Excel. */
      ent.el('accProd').value = 'MICA HR';
      ent.correr('accAgregarLinea();');
    }

    ent.correr('guardarAcc();');
    await esperar();
  }catch(e){ return { error: (e && e.message) || String(e) }; }

  const guardados = llamadas.filter(c => c.fn === 'accesorio_guardar' || c.fn === 'reparacion_guardar');
  return {
    llamadas, guardados,
    fns: guardados.map(c => c.fn),
    ids: guardados.map(c => c.body.p_captura_id),
    fotos: llamadas.filter(c => c.fn === 'venta_foto_guardar').length,
    queja: (ent.el('accError').style.display !== 'none')
             ? (ent.el('accError').textContent || '') : '',
    verProducto: ent.el('accSoloAcc').style.display !== 'none',
    verPiezas:   ent.el('accSoloPiezas').style.display !== 'none'
  };
}

(async () => {
  const fallos = [];

  // 1 · Cada tipo, solo, va a su funcion y NO a la del otro
  for(const [tipo, debe, prohibida] of [
        ['acc', 'accesorio_guardar',  'reparacion_guardar'],
        ['rep', 'reparacion_guardar', 'accesorio_guardar']]){
    const r = await capturar([tipo]);
    if(r.error){ fallos.push(tipo + ': la pantalla se cae -> ' + r.error); continue; }
    if(r.fns.indexOf(debe) < 0){
      fallos.push(tipo + ': no llamo a `' + debe + '`' +
                  (r.queja ? ' — la pantalla dice: "' + r.queja + '"' : '') +
                  '. Salieron: ' + (r.fns.join(', ') || 'ninguna'));
    }
    if(r.fns.indexOf(prohibida) >= 0){
      fallos.push(tipo + ': llamo a `' + prohibida + '`, QUE ES LA TABLA DE LA OTRA COSA' +
                  (tipo === 'rep' ? ' — esa reparacion acabaria en el Excel de comisiones' : ''));
    }
  }

  /* 2 · EL CASO QUE MOTIVO TODO ESTO: una mica y un cambio de pantalla en el
     mismo ticket. Tiene que salir UNA captura, con las dos llamadas y una sola
     foto, y las dos ligadas al mismo captura_id. */
  const mix = await capturar(['acc', 'rep']);
  if(mix.error){
    fallos.push('mixto: la pantalla se cae -> ' + mix.error);
  }else{
    if(mix.fns.indexOf('accesorio_guardar') < 0 || mix.fns.indexOf('reparacion_guardar') < 0){
      fallos.push('mixto: un ticket con accesorio Y reparacion tiene que llamar a las dos. ' +
                  'Salieron: ' + (mix.fns.join(', ') || 'ninguna') +
                  (mix.queja ? ' — la pantalla dice: "' + mix.queja + '"' : ''));
    }
    const ids = mix.ids.filter(Boolean);
    if(ids.length && new Set(ids).size !== 1){
      fallos.push('mixto: cada concepto va con un captura_id distinto (' + ids.join(', ') +
                  '). La foto es UNA y se liga por ese id: con ids distintos, solo uno ' +
                  'de los dos la tendria.');
    }
    if(mix.fotos > 1){
      fallos.push('mixto: subio la foto ' + mix.fotos + ' veces. El papel es uno; ' +
                  '`venta_fotos` tiene PK (store_id, captura_id) y la segunda ni entraria.');
    }
  }

  // 3 · El panel no pide lo que una reparacion no tiene
  const soloRep = await capturar(['rep']);
  if(!soloRep.error){
    if(soloRep.verProducto) fallos.push('reparacion: pide producto, que no tiene');
    if(soloRep.verPiezas)   fallos.push('reparacion: pide piezas, que no tiene');
  }

  // 4 · Un ticket vacio no se guarda, y se dice por que
  const vacio = await capturar([]);
  if(!vacio.error){
    if(vacio.fns.length){
      fallos.push('vacio: guardo ' + vacio.fns.length + ' concepto(s) sin que se agregara ninguno');
    }
    if(!vacio.queja){
      fallos.push('vacio: no guarda nada y tampoco dice por que — el asesor se queda mirando');
    }
  }

  if(fallos.length){
    console.log('mrfix: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('mrfix: cada concepto a su tabla, y un ticket mixto es una captura con una foto');
})();
