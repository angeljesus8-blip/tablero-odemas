/* ============================================================
   Captura: «cero promos» se cree, pero solo si el token vale
   ============================================================
   Corre en cada commit desde `verificar.py`.

   27-oct-2026. `refreshPromos` exigía al menos una promo para aceptar la
   respuesta. Con cero —Admin · Limpiar todos, o el fin de todas— el teléfono
   seguía cobrando las promos guardadas hasta su fecha de fin, y además caía al
   Apps Script, cuyas hojas sirven datos de agosto.

   Pero el candado de Supabase, con un token que no vale, TAMBIÉN contesta una
   lista vacía. Creerle sin más dejaría sin promos a todo teléfono con sesión
   vieja, y cobraría el precio regular.

   Lo que se exige:
     1. cero promos con el catálogo llegando (token bueno) → sin promos;
     2. cero promos con el catálogo vacío (token malo) → se quedan las guardadas;
     3. sin respuesta → se quedan las guardadas;
     4. nada de esto le pregunta al Apps Script.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const RAIZ = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(RAIZ, 'captura_series.html'), 'utf8');
const { crearEntorno } = require('./dom.js');

const STORE = { store_id:'9999', nombre:'Tienda Demo', gas_token:'t', vendedores:['Prueba Uno'] };
const EMP   = { empno:'1', nombre:'Prueba Uno', puesto:'asesor' };
const GUARDADAS = { '111': { d:'PRUEBA', pr:1000, pp:800, est:'Activo', msi:'', d1:'2026-01-01', d2:'2099-12-31' } };
const fallos = [];
const ok = (t, c, extra) => { if(!c) fallos.push(t + (extra !== undefined ? ' -> ' + JSON.stringify(extra) : '')); };

function abrir(){
  return crearEntorno({ html, ruta:'/t/captura_series.html',
    ls: { odemas_store: JSON.stringify(STORE), odemas_empleado: JSON.stringify(EMP),
          odemas_vend: 'Prueba Uno', odemas_promos: JSON.stringify(GUARDADAS) } });
}

/* `respuestas` = lo que contesta Supabase a cada función; ausente = no contestó. */
async function caso(respuestas){
  const ent = abrir();
  if(ent.err){ fallos.push('la pantalla se cae al cargar -> ' + ent.err); return null; }
  ent.caja.__resp = respuestas;
  ent.correr(`window.__llamadas = [];
    sbRpcCS = async function(fn){ __llamadas.push(fn);
      return Object.prototype.hasOwnProperty.call(__resp, fn) ? __resp[fn] : null; };`);
  ent.correr('PROMOS = JSON.parse(localStorage.getItem("odemas_promos"))');
  await ent.correr('refreshPromos()');
  return { activa: !!ent.correr('promoActiva("111")'), llamadas: ent.correr('__llamadas'), ent };
}

(async () => {
  const catalogo = [{ sku:'111', descripcion:'PRUEBA', upc:'7500000000001', precio:1000, vigente:true, onhand:1 }];

  const a = await caso({ promos_vigentes: [], catalogo_completo: catalogo });
  ok('1 · cero promos y token bueno: ya no hay promo', a && !a.activa);

  const b = await caso({ promos_vigentes: [], catalogo_completo: [] });
  ok('2 · cero promos y token malo: se queda la guardada', b && b.activa);

  const c = await caso({});
  ok('3 · sin respuesta: se queda la guardada', c && c.activa);

  const d = await caso({ promos_vigentes: [{ sku:'222', producto:'OTRA', precio_reg:500, precio_pro:400,
                                             vigente_desde:'2026-01-01', vigente_hasta:'2099-12-31' }] });
  ok('1b · con promos, la lista de la nube reemplaza a la guardada', d && !d.activa);
  ok('1b · y no gasta la llamada al catálogo', d && !d.llamadas.includes('catalogo_completo'), d && d.llamadas);

  ok('4 · Captura no tiene ninguna ruta al Apps Script', !/script\.google\.com|catJsonp\(|CLOUD_URL\s*=/.test(html));

  if(fallos.length){
    console.log('FALLAS en captura_promos_vacias.js:\n  - ' + fallos.join('\n  - '));
    process.exit(1);
  }
  console.log('captura promos: «cero promos» se cree solo con token bueno, y nada cae al Apps Script');
})().catch(e => { console.log('FALLA captura_promos_vacias.js: ' + (e && e.stack || e)); process.exit(1); });
