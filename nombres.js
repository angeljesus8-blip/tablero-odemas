/* ============================================================
   Nombres de producto en lenguaje de cliente
   ============================================================
   22-sep-2026. «AUDIF IN EAR HW F-BUDS PRO 4 VD» → «Audífonos Huawei
   FreeBuds Pro 4» · Verde.

   POR QUÉ LLEGAN ASÍ: el catálogo corporativo topa la descripción en ~30
   caracteres (de 96 SKUs, 93 miden entre 28 y 31), y quien da de alta abrevia
   a mano y sin regla fija — el mismo producto sale «AUDIF» y «AUDÍF», «HW» y
   «HWEI». Llegará así SIEMPRE, y la carga diaria de Admin reescribe la
   descripción de cada SKU (`SET descripcion = excluded.descripcion`), así que
   corregirla en la base se borraría al día siguiente.

   Por eso esto es SOLO DE PANTALLA:
   · La descripción original NO se toca. La usan la venta, el autollenado de
     Captura, el reporte al Excel regional y la etiqueta/POS; en pantalla va
     debajo, chica, para que el asesor la empate con la caja.
   · Son REGLAS, no una lista por SKU: el producto que llegue mañana se
     traduce solo. Una abreviatura que no se conoce sale TAL CUAL (se ve menos
     bonita, pero no se inventa nada) y queda en `sinTraducir` para agregarla.

   Códigos de color confirmados por Ángel el 22-sep-2026. Los que no se
   confirmaron (AN, PK, GRSP, PL, AM, BG, BNA, NGC) se dejan como vienen.

   Función pura, sin DOM: la prueban `pruebas/nombres_cliente.js` y se puede
   usar desde cualquier página.
   ============================================================ */
(function(raiz){
  'use strict';

  const COLORES = {
    NG:'Negro', NEGRO:'Negro', BN:'Blanco', BLANCO:'Blanco', AZ:'Azul', AZUL:'Azul',
    VD:'Verde', VERDE:'Verde', GR:'Gris', GRIS:'Gris', RS:'Rosa', ROSA:'Rosa',
    RJ:'Rojo', ROJO:'Rojo', NJ:'Naranja', DO:'Dorado', DORADO:'Dorado',
    MO:'Morado', PR:'Púrpura', PT:'Plata', CF:'Café', 'CAFÉ':'Café', CAFE:'Café',
    BGE:'Beige', BEIGE:'Beige',
  };

  // Palabra del catálogo → como se escribe para el cliente.
  const PALABRAS = {
    HW:'Huawei', HWEI:'Huawei', HUAWEI:'Huawei',
    'F-BUDS':'FreeBuds', FREEBUDS:'FreeBuds', FREECLIP:'FreeClip', FREEARC:'FreeArc',
    MATEPAD:'MatePad', MATEBOOK:'MateBook', 'M-PENCIL':'M-Pencil', PENCIL:'Pencil',
    PURA:'Pura', NOVA:'nova', MATE:'Mate', WATCH:'Watch', BAND:'Band', FIT:'Fit',
    ULT:'Ultra', ULTIMATE:'Ultimate', PRO:'Pro', MAX:'Max', KEY:'Key',
    KID:'Kids', KIDS:'Kids', MIN:'Mini', MINI:'Mini', DESIGN:'Design', GOLF:'Golf',
    ROUTER:'Router', MESH:'Mesh', MOUSE:'Mouse', SMARTWATCH:'Smartwatch',
    SENSOR:'Sensor', TI:'Titanio', RUNNER:'Runner', GEN:'gen.', '3RA':'3ra',
    // Siglas que SON el modelo: se quedan como están, pero conocidas.
    SE:'SE', GT:'GT', XT:'XT', X:'X', S:'S',
    CI5:'Core i5', CI7:'Core i7', CI9:'Core i9',
    CU5:'Core Ultra 5', CU7:'Core Ultra 7', CU9:'Core Ultra 9',
  };
  // Lo que en el catálogo solo gasta caracteres y al cliente no le dice nada.
  const FUERA = new Set(['IN','OPEN','OVER','EAR','AMLD','AMOLED','AL','VID','TOG']);
  // «+ algo» al final: lo que trae la caja.
  const EXTRAS = { TECLD:'con teclado', TCL:'con teclado', FDA:'con funda', EXT:'con extensor' };

  const sinAcento = s => s.normalize('NFD').replace(/[̀-ͯ]/g, '');

  /* El Excel del sistema trae los acentos ROTOS (visto el 22-sep-2026 en el
     «Informe Artículos Totales Tienda»): la Í y la É llegan como el carácter
     de reemplazo U+FFFD — «AUD�F», «CAF�», y hasta el encabezado dice
     «DESCRIPCI�N». Viene así desde el archivo, no lo rompe la carga, y así
     llega a la base. Se repara con la palabra que se sabe que es; un � en
     otra palabra se deja, que inventar una letra sería peor. */
  const ROTAS = { 'AUD�F':'AUDÍF', 'CAF�':'CAFÉ' };
  function repararTexto(desc){
    return String(desc == null ? '' : desc).replace(/[A-ZÁÉÍÓÚÑ]*�[A-ZÁÉÍÓÚÑ]*/gi,
      w => ROTAS[w.toUpperCase()] || w);
  }

  function nombreCliente(desc){
    const original = repararTexto(desc).trim();
    if(!original) return { texto:'', color:'', original:'', sinTraducir:[] };
    // Solo se traduce lo que viene del catálogo, que es TODO mayúsculas. Un
    // nombre que alguien ya escribió bien («Bundle Pura 80 + Watch») no se toca.
    if(/[a-zà-ÿ]/.test(original)) return { texto:original, modelo:original, ficha:'', color:'', original, sinTraducir:[] };

    // La memoria se junta ANTES de separar los «+»: si no, «16GB+1TB» se
    // parte en «16GB +1TB» y ya no se reconoce como memoria.
    let s = original.toUpperCase()
      .replace(/(\d),(\d)/g, '$1.$2')              // 6,6" → 6.6"
      .replace(/\b(\d+)\s*GB\s*[\/+]\s*(\d+)\s*(GB|TB)\b/g, '$1GB=$2$3')  // 16GB/1TB, 16GB+1TB
      .replace(/\b(\d+)\s*[\/+]\s*(\d+)\s*(GB|TB)\b/g, '$1GB=$2$3')       // 12/256GB, 8+512 GB
      .replace(/\b(\d+)\s*GB\s+(\d+)\s*(GB|TB)\b/g, '$1GB=$2$3')          // 8GB 256GB
      .replace(/\s*\+\s*/g, ' +');                 // «+ TECLD», «VD+FDA» → « +TECLD», «VD +FDA»
    const esTableta = /\bMATEPAD\b/.test(s);
    const esAudifono = /^AUD[IÍ]F\b/.test(s);

    let toks = s.split(/\s+/).filter(Boolean);
    const extras = [];
    let color = '';
    const sinTraducir = [];

    // El color es la última palabra (a veces con un «+FDA» detrás, ya separado).
    toks = toks.filter(t => {
      if(t[0] === '+' && EXTRAS[t.slice(1)]){ extras.push(EXTRAS[t.slice(1)]); return false; }
      return true;
    });
    if(toks.length > 1 && COLORES[toks[toks.length - 1]]) color = COLORES[toks.pop()];

    // `out` es el modelo (el título de la tarjeta); `ficha`, lo que distingue
    // una versión de otra del mismo modelo: memoria, velocidad, qué trae la
    // caja. «Huawei Pura 80 12 GB + 256 GB» se leía «Pura 80-12»; separado
    // queda «Huawei Pura 80» y abajo «12 GB + 256 GB · Negro».
    const out = [], ficha = [];
    if(esAudifono){ toks.shift(); out.push('Audífonos'); }
    for(let i = 0; i < toks.length; i++){
      let t = toks[i];
      if(FUERA.has(t)) continue;
      if(i > 0 && t === toks[i - 1]) continue;            // «WATCH WATCH KID»
      let m;
      if(PALABRAS[t]){ out.push(PALABRAS[t]); continue; }
      if((m = t.match(/^(\d+)GB=(\d+)(GB|TB)$/))){ ficha.push(`${m[1]} GB + ${m[2]} ${m[3]}`); continue; }
      if((m = t.match(/^(\d+)(GB|TB)$/))){ ficha.push(`${m[1]} ${m[2]}`); continue; }
      if((m = t.match(/^(\d+)MM$/))){ out.push(`${m[1]} mm`); continue; }
      if((m = t.match(/^(\d+)MB$/))){ ficha.push(`${m[1]} Mbps`); continue; }
      if((m = t.match(/^(\d+)PZ$/))){ ficha.push(`${m[1]} piezas`); continue; }
      if((m = t.match(/^WI-FI(\d)$/))){ out.push(`Wi-Fi ${m[1]}`); continue; }
      if((m = t.match(/^(SE)(\d)$/))){ out.push(`SE ${m[2]}`); continue; }
      if((m = t.match(/^(\d+)I$/))){ out.push(`${m[1]}i`); continue; }         // 7I → 7i
      if((m = t.match(/^RUNNER(\d)$/))){ out.push(`Runner ${m[1]}`); continue; }
      if((m = t.match(/^([A-Z]\d+)PRO$/))){ out.push(`${m[1]} Pro`); continue; } // X1PRO
      // Medida de pantalla: en la tableta ES el modelo (MatePad 11.5); en
      // relojes y teléfonos es un dato de ficha que estorba en el nombre.
      // Si el modelo ya dice el número («12X» y luego 12"), la pulgada sobra.
      if((m = t.match(/^(\d+(?:\.\d+)?)"?$/)) && (t.includes('"') || t.includes('.'))){
        const ent = m[1].split('.')[0];
        if(esTableta && !out.some(w => w.startsWith(ent))) out.push(m[1]);
        continue;
      }
      if(/\d/.test(t)){ out.push(t); continue; }          // X6, D16, GT6, AX3S, CD26
      if(t.length <= 3){ out.push(t); sinTraducir.push(t); continue; }  // código que no conocemos
      out.push(t[0] + t.slice(1).toLowerCase());          // palabra suelta: Título
      sinTraducir.push(t);
    }
    // Huawei una sola vez y, en audífonos, detrás del tipo.
    const modelo = out.filter((w, i) => !(w === 'Huawei' && out.indexOf('Huawei') < i))
                      .join(' ').replace(/\s+/g, ' ').trim() || original;
    const fichaTxt = ficha.concat(extras).join(' · ');
    const texto = fichaTxt ? modelo + ' · ' + fichaTxt : modelo;
    return { texto, modelo, ficha: fichaTxt, color, original, sinTraducir };
  }

  // Para buscar: «audifonos» encuentra «Audífonos» y «AUDIF».
  function textoBusqueda(desc){
    const n = nombreCliente(desc);
    return sinAcento((n.original + ' ' + n.texto + ' ' + n.color).toLowerCase());
  }
  // Una línea, para mensajes al cliente (WhatsApp, cotización).
  function nombreLinea(desc){
    const n = nombreCliente(desc);
    return n.color ? n.texto + ' · ' + n.color : n.texto;
  }

  const api = { nombreCliente, textoBusqueda, nombreLinea, sinAcento, repararTexto };
  if(typeof module !== 'undefined' && module.exports) module.exports = api;
  else Object.assign(raiz, api);
})(typeof window !== 'undefined' ? window : globalThis);
