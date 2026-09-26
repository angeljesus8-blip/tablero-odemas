/* ============================================================
   Nombres de cliente: se traducen sin perder nada
   ============================================================
   Corre en cada commit desde `verificar.py`. Prueba `nombres.js`.

   El riesgo de traducir no es que quede feo: es que el asesor lea un modelo
   o una memoria que NO es la del producto y se lo cotice al cliente. Así que
   lo que se exige, sobre las 230 descripciones del catálogo que ya vive en
   captura_series.html (público, sin datos de nadie):

     1. Ninguna sale vacía.
     2. Ninguna pierde un número de modelo (80, X6, GT6, 12X, D16…).
     3. Ninguna pierde la memoria: cada número de GB/TB sigue ahí.
     4. El color se traduce si es un código confirmado, y si no se deja.
     5. No queda ninguna abreviatura conocida sin traducir (HW, AUDIF…).

   Y las trampas: el catálogo escribe lo mismo de varias formas —AUDIF/AUDÍF,
   HW/HWEI, «+TECLD»/«+ TECLD»/«+TCL», 6,6"/6.6"—. Cada pareja debe dar el
   MISMO nombre; si no, el buscador y la pantalla dirían dos productos.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path');
const { nombreCliente, nombreLinea, textoBusqueda } = require('../nombres.js');

const fallos = [];
const ok = (t, c, d) => { if(!c) fallos.push(t + (d ? '  -> ' + d : '')); };

const html = fs.readFileSync(path.join(__dirname, '..', 'captura_series.html'), 'utf8');
const m = html.match(/let CATALOGO = (\{.*?\});/);
if(!m){ console.log('nombres: no encontré CATALOGO en captura_series.html'); process.exit(1); }
const descs = [...new Set(Object.values(JSON.parse(m[1])).map(x => x.d))];
ok('el catálogo trae descripciones para probar', descs.length > 100, String(descs.length));

const CODIGOS = ['NG','BN','AZ','VD','GR','RS','RJ','NJ','DO','MO','PR','PT','CF','BGE'];
const ABREV = /\b(HW|HWEI|AUD[IÍ]F|F-BUDS|ULT|TECLD|TCL|FDA|AMLD|CI[579]|CU[579])\b/;
const norm = s => s.toUpperCase().replace(/\s+/g, '');

for(const d of descs){
  const n = nombreCliente(d);
  const todo = [n.modelo, n.ficha, n.color].join(' ');
  ok('no sale vacío: ' + d, n.modelo && n.modelo.length > 2);

  const toks = d.toUpperCase().replace(/(\d),(\d)/g, '$1.$2').split(/[\s+]+/);
  // 2 · números de modelo: tokens con dígito que no son medida, memoria, mm, Mbps, piezas.
  for(const t of toks){
    if(!/\d/.test(t) || /"|\.|GB|TB|MM$|MB$|PZ$|^WI-FI|^\d+\/\d+/.test(t) || /^\d+$/.test(t) && /\b\d+\s*[\/+]\s*\d+\s*(GB|TB)|\b\d+\s*GB\b/.test(d) && new RegExp('\\b' + t + '\\s*(GB|TB|/|\\+)').test(d)) continue;
    const suelto = t.replace(/^(CI|CU)(\d)$/, '$2').replace(/^(SE|RUNNER)(\d)$/, '$2').replace(/PRO$/, '').replace(/I$/, 'i');
    ok('conserva el modelo «' + t + '»: ' + d, norm(n.modelo).includes(norm(suelto)), n.modelo);
  }
  // 3 · memoria
  for(const g of (d.match(/\d+(?=\s*(GB|TB)\b)|\d+(?=\s*[\/+]\s*\d+\s*(GB|TB))/g) || []))
    ok('conserva la memoria ' + g + ': ' + d, new RegExp('\\b' + g + ' (GB|TB)').test(n.ficha), n.ficha);
  // 4 · color
  const ult = toks[toks.length - 1].split('+')[0];
  if(CODIGOS.includes(ult)) ok('traduce el color ' + ult + ': ' + d, !!n.color, todo);
  // 5 · abreviaturas conocidas
  ok('no deja abreviaturas conocidas: ' + d, !ABREV.test(todo), todo);
}

// Trampas: la misma cosa escrita de dos formas da el mismo nombre.
const parejas = [
  ['AUDIF IN EAR HW F-BUDS PRO 5 NG', 'AUDÍF IN EAR HW F-BUDS PRO 5 NG'],
  ['AUDIF OVER EAR HW FREEARC VD',    'AUDIF OVER EAR HWEI FREEARC VD'],
  ['MATEPAD 11.5" 8/256GB +TECLD GR', 'MATEPAD 11.5" 8/256GB + TECLD GR'],
  ['MATEPAD 11.5" 8/256GB +TECLD GR', 'MATEPAD 11.5" 8/256GB +TCL GR'],
  ['HUAWEI PURA 70 6,6" 12/256GB BN', 'HUAWEI PURA 70 6.6" 12/256GB BN'],
  ['MATEBOOK D16 CI5 16GB+1TB GR',    'MATEBOOK D16 CI5 16GB/1TB GR'],
  ['MATEBOOK D16 CI5 16GB+1TB GR',    'MATEBOOK D16 CI5 16GB 1TB GR'],
  ['HUAWEI WATCH FIT 3 1.82" NG',     'HUAWEI WATCH FIT 3 1.82" NEGRO'],
  // El Excel del sistema trae la Í y la É ROTAS (U+FFFD). Así llegan a la base.
  ['AUDÍF OPEN EAR HW FREECLIP 2 AZ', 'AUD�F OPEN EAR HW FREECLIP 2 AZ'],
  ['HUAWEI WATCH GT6 PRO 1.47" CAFÉ', 'HUAWEI WATCH GT6 PRO 1.47" CAF�'],
];
for(const [a, b] of parejas)
  ok('«' + a + '» y «' + b + '» dan lo mismo', nombreLinea(a) === nombreLinea(b), nombreLinea(a) + ' ≠ ' + nombreLinea(b));

// Casos a la vista, para que un cambio de regla se note en el texto exacto.
const exactos = {
  'AUDIF IN EAR HW F-BUDS PRO 4 VD': 'Audífonos Huawei FreeBuds Pro 4 · Verde',
  'HUAWEI PURA 80 6.6" 12/256GB DO': 'Huawei Pura 80 · 12 GB + 256 GB · Dorado',
  'MATEPAD MIN 8.8 12/256GB VD+FDA': 'MatePad Mini 8.8 · 12 GB + 256 GB · con funda · Verde',
  'HUAWEI WATCH WATCH KID RS':       'Huawei Watch Kids · Rosa',
  'MATEBOOK 14 CU7 16GB 1TB VERDE':  'MateBook 14 Core Ultra 7 · 16 GB + 1 TB · Verde',
  'HUAWEI WATCH 5 46MM TI 1.5" PT':  'Huawei Watch 5 46 mm Titanio · Plata',
};
for(const [d, esperado] of Object.entries(exactos))
  ok('«' + d + '» → «' + esperado + '»', nombreLinea(d) === esperado, nombreLinea(d));

// Lo desconocido no se inventa: sale tal cual y queda anotado.
const raro = nombreCliente('AUDÍF IN EAR HW F-BUDS PRO 5 AN');
ok('un color no confirmado (AN) no se inventa', raro.color === '' && /\bAN\b/.test(raro.modelo), raro.modelo);
ok('y queda anotado para agregarlo', raro.sinTraducir.includes('AN'));
// Lo que ya está bien escrito no se toca.
ok('un nombre ya escrito no se traduce', nombreCliente('Bundle Pura 80 + Watch').texto === 'Bundle Pura 80 + Watch');
ok('vacío no revienta', nombreCliente(null).texto === '' && nombreCliente('').texto === '');
// El buscador encuentra por las dos formas y sin acentos.
const b = textoBusqueda('AUDIF IN EAR HW F-BUDS PRO 4 VD');
ok('se busca por «audifonos»', b.includes('audifonos'));
ok('se busca por «freebuds»', b.includes('freebuds'));
ok('se busca por lo del catálogo («f-buds»)', b.includes('f-buds'));
ok('se busca por el color', b.includes('verde'));

/* ── Admin → 📦 Catálogo → «Nombres sin traducir» (22-sep-2026) ──
   Se prueba la función DE admin.html (no una copia), con las reglas de
   nombres.js y el catálogo de Captura. Lo que importa: que junte TODO lo
   que `sinTraducir` anota —una abreviatura que se pierde aquí no se ve en
   ningún otro sitio—, que cuente productos y no apariciones, y que sin
   nombres.js lo diga (null) en vez de enseñar «todo traducido». */
{
  const admin = fs.readFileSync(path.join(__dirname, '..', 'admin.html'), 'utf8');
  const fm = admin.match(/function sinTraducirDe\(descripciones\)\{[\s\S]*?\r?\n\}/);
  ok('admin.html tiene sinTraducirDe', !!fm);
  ok('admin.html carga nombres.js', /<script src="\.\/nombres\.js"><\/script>/.test(admin));
  ok('Admin lee el catálogo de tablero_todo (la lectura pública del tablero)', /sb\.rpc\("tablero_todo"/.test(admin));
  if(fm){
    const vm = require('vm');
    const con = vm.createContext({ nombreCliente });
    vm.runInContext(fm[0], con);
    const lista = vm.runInContext('sinTraducirDe', con)(descs.concat(descs, [null, '']));
    const esperado = {};
    for(const d of descs) for(const t of nombreCliente(d).sinTraducir) esperado[t] = (esperado[t] || 0) + 1;
    const visto = Object.fromEntries(lista.map(x => [x.abrev, x.n]));
    ok('Admin lista todas las abreviaturas sin traducir, contando productos (no repeticiones)',
       JSON.stringify(Object.keys(esperado).sort().map(k => [k, esperado[k]])) ===
       JSON.stringify(Object.keys(visto).sort().map(k => [k, visto[k]])),
       JSON.stringify(visto));
    ok('y de más productos a menos', lista.every((x, i) => !i || lista[i - 1].n >= x.n));
    ok('cada una con un ejemplo real del catálogo', lista.every(x => descs.includes(x.ejemplos[0])));
    const sin = vm.createContext({});
    vm.runInContext(fm[0], sin);
    ok('sin nombres.js dice «no sé» (null), no «todo traducido»',
       vm.runInContext('sinTraducirDe', sin)(descs) === null);
  }
}

if(fallos.length){
  console.log('nombres: ' + fallos.length + ' fallo(s)');
  fallos.slice(0, 15).forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('nombres: ' + descs.length + ' descripciones del catálogo se traducen sin perder modelo, memoria ni color; ' + parejas.length + ' trampas dan lo mismo');
