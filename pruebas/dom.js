/* ============================================================
   El navegador de mentira, en UN solo sitio
   ============================================================
   17-ago-2026.

   Cada prueba tenía su propio DOM falso, y todos mentían de la misma manera.
   Tres fallos del mismo día pasaron por debajo:

     · `$('edSku').addEventListener(...)` sobre un <div> que se pinta MÁS ABAJO
       que el <script>. En el navegador eso es null y tumbaba la captura entera
       al arrancar. El DOM viejo devolvía un elemento para CUALQUIER id.

     · un botón que se enseñaba y al pulsarlo decía "no tienes permiso": dos
       sitios con la misma condición y solo se cambió uno. Con `classList.add(){}`
       vacío no hay forma de comprobar si un panel se abrió, así que la prueba
       solo podía mirar valores de retorno — y la función estaba bien.

   Las dos cosas que este DOM hace y el viejo no:

     1. RESPETA EL ORDEN DEL DOCUMENTO. Durante la carga, un id que aparece por
        debajo del script principal devuelve null, igual que el navegador. Al
        terminar de cargar existen todos.

     2. `classList` de verdad, con un Set. Permite comprobar COMPORTAMIENTO —si
        una pantalla se abrió, si una clase se aplicó— y no solo qué devuelve
        una función.

   No basta con comprobar que el id exista en el HTML: `edSku` existía. Lo que
   hay que comparar son POSICIONES.
   ============================================================ */
'use strict';
const vm = require('vm');

/* Los <script> ejecutables del archivo: sin `src` y sin `type=module`. El de
   módulo queda fuera a propósito — su `await` de nivel superior no se puede
   mezclar con estos. */
function scriptsDe(html){
  const bloques = html.match(/<script[^>]*>[\s\S]*?<\/script>/g) || [];
  return bloques
    .filter(b => !/\ssrc=/.test(b.slice(0, b.indexOf('>'))))
    .filter(b => !/type="module"/.test(b.slice(0, b.indexOf('>'))))
    .map(b => b.slice(b.indexOf('>') + 1, b.lastIndexOf('</script>')))
    .join('\n;\n');
}

function posiciones(html){
  const posId = new Map();
  for(const m of html.matchAll(/\bid="([^"]+)"/g)){
    if(!posId.has(m[1])) posId.set(m[1], m.index);
  }
  // El bloque de <script> más largo es el principal; los paneles van tras él.
  let posScript = 0, largo = -1;
  for(const m of html.matchAll(/<script(?![^>]*\ssrc=)(?![^>]*type="module")[^>]*>/g)){
    const fin = html.indexOf('</script>', m.index);
    if(fin - m.index > largo){ largo = fin - m.index; posScript = m.index; }
  }
  return { posId, posScript };
}

/* Crea el entorno y ejecuta el JS del archivo dentro.

   opciones:
     html    – el archivo entero (para el orden de los ids)
     ls      – lo que hay en localStorage al arrancar
     fetch   – por defecto rechaza SIEMPRE: es el escenario que más importa,
               porque la app tiene que seguir dejando trabajar sin nube
     ruta    – location.pathname, para las apps que miran de dónde vienen  */
function crearEntorno(opciones){
  const o    = opciones || {};
  const html = o.html || '';
  const LS   = Object.assign({}, o.ls || {});
  const { posId, posScript } = posiciones(html);
  const els  = {};
  let cargando = true;

  function el(id){
    if(cargando && posId.has(id) && posId.get(id) > posScript) return null;
    if(!els[id]){
      const clases = new Set();
      els[id] = {
        id, style:{}, dataset:{}, value:'', textContent:'', innerHTML:'',
        children:[], onclick:null, onchange:null, checked:false, disabled:false,
        /* Un <select> de verdad tiene `selectedOptions`, y el codigo lo usa para
           sacar el SKU del producto elegido (`selectedOptions[0].dataset.sku`).
           Sin esto, cualquier prueba que guarde un accesorio revienta con
           «Cannot read properties of undefined (reading '0')» y parece un fallo
           de la pantalla cuando lo es del andamiaje. Se sirve una opcion vacia:
           la que importa —que el SKU se lea del producto y no se suponga— la
           comprueba `catalogo_accesorios.js` contra el HTML de la lista. */
        options:[], selectedOptions:[{ value:'', dataset:{}, textContent:'' }],
        classList:{
          add:    c => clases.add(c),
          remove: c => clases.delete(c),
          contains: c => clases.has(c),
          toggle: (c, on) => {
            if(on === undefined){ clases.has(c) ? clases.delete(c) : clases.add(c); }
            else { on ? clases.add(c) : clases.delete(c); }
          }
        },
        // Para leerlas desde la prueba sin depender de classList
        _clases: clases,
        querySelectorAll:()=>[], querySelector:()=>null,
        addEventListener(){}, removeEventListener(){}, appendChild(){},
        insertBefore(){}, closest:()=>null, focus(){}, blur(){}, remove(){},
        scrollIntoView(){}, click(){ if(typeof this.onclick === 'function') return this.onclick(); }
      };
    }
    return els[id];
  }

  const caja = {
    console,
    location:{ href:'', search:'', hash:'', pathname: o.ruta || '/t/index.html',
               replace(){}, reload(){}, assign(){} },
    history:{ replaceState(){}, pushState(){}, back(){} },
    navigator:{ serviceWorker:{ addEventListener(){}, controller:null,
                  ready:{ then(){ return { catch(){} }; } },
                  register(){ return { catch(){}, then(){ return { catch(){} }; } }; } },
                clipboard:{ writeText(){ return Promise.resolve(); } },
                userAgent:'prueba' },
    document:{ getElementById: el, querySelectorAll:()=>[], querySelector:()=>null,
      createElement:()=>el('t' + Math.random()), head: el('head'), body: el('body'),
      readyState:'complete', addEventListener(){}, hidden:false,
      documentElement: el('html') },
    localStorage:{ getItem: k => (k in LS ? LS[k] : null),
      setItem:(k,v)=>{ LS[k] = String(v); }, removeItem: k => { delete LS[k]; },
      clear(){ for(const k of Object.keys(LS)) delete LS[k]; } },
    sessionStorage:{ getItem:()=>null, setItem(){}, removeItem(){} },
    fetch: o.fetch || (() => Promise.reject(new Error('sin red'))),
    alert:()=>{}, confirm:()=> o.confirm !== false, prompt:()=>null,
    setInterval:()=>0, clearInterval:()=>{},
    // Los timers corren al momento: las pruebas no esperan relojes.
    setTimeout:(f)=>{ if(typeof f === 'function') f(); return 0; }, clearTimeout:()=>{},
    requestAnimationFrame:(f)=>{ if(typeof f === 'function') f(); return 0; },
    scrollTo:()=>{}, addEventListener:()=>{}, removeEventListener:()=>{},
    AbortController: class { constructor(){ this.signal = {}; } abort(){} },
    Blob: class {}, URL:{ createObjectURL:()=>'', revokeObjectURL:()=>{} },
    XMLHttpRequest: class { open(){} send(){} setRequestHeader(){} },
    Image: class {}, FileReader: class {},
    URLSearchParams, TextEncoder, TextDecoder, Date, JSON, Math, RegExp,
    Promise, Array, Object, String, Number, Boolean, Error, Set, Map,
    isNaN, parseFloat, parseInt, encodeURIComponent, decodeURIComponent,
    btoa: s => Buffer.from(s, 'binary').toString('base64'),
    atob: s => Buffer.from(s, 'base64').toString('binary')
  };
  caja.window = caja;
  caja.globalThis = caja;
  vm.createContext(caja);

  let err = null;
  try{ vm.runInContext(scriptsDe(html), caja, { filename:'app.js' }); }
  catch(e){ err = e.message; }
  cargando = false;   // documento completo: a partir de aquí existe todo

  /* Ejecuta código en el MISMO ámbito léxico del script. Hace falta porque las
     `let`/`const` de nivel superior no aparecen en el objeto global —solo `var`
     y las funciones—, así que `caja.PROMOS` es undefined pero
     `correr('PROMOS')` sí las ve. */
  const correr = (codigo) => vm.runInContext(codigo, caja, { filename:'prueba.js' });

  return {
    err, LS, els, caja, correr, el,
    // Atajos para lo que se mira en casi todas las pruebas
    tiene:  (id, clase) => el(id).classList.contains(clase),
    htmlDe: (id) => el(id).innerHTML || '',
    lsJson: (k) => { try{ return JSON.parse(LS[k] || 'null'); }catch(e){ return null; } }
  };
}

module.exports = { crearEntorno, scriptsDe, posiciones };
