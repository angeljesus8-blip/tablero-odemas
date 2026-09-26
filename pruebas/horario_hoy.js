/* ============================================================
   Horario: «hoy» es el día del teléfono, también de noche
   ============================================================
   Corre en cada commit desde `verificar.py`. 22-sep-2026.

   La tarjeta de la semana marca el día de hoy. Lo calculaba con
   `toISOString()`, que es UTC: desde las 6 de la tarde en México ya es
   mañana en UTC, y el horario marcaba como «hoy» el día siguiente — justo a
   la hora en que el de cierre mira qué le toca mañana. Pasó meses sin verse
   porque el resaltado era crema; con el rediseño es rojo tenue y saltó.

   Se fija el reloj a un martes a las 6:30 p. m. y a las 11:50 p. m. de la
   Ciudad de México y se exige que la tarjeta marque el martes.
   ============================================================ */
'use strict';
process.env.TZ = 'America/Mexico_City';   // antes de crear cualquier Date
const fs = require('fs'), path = require('path');
const html = fs.readFileSync(path.join(__dirname, '..', 'horarios.html'), 'utf8');
const { crearEntorno } = require('./dom.js');

const EQUIPO = {
  horaApertura: 10, horaCierre: 21,
  gerentes: [
    { key:'G1', nombre:'ANA GERENTE', cargo:'Gerente de Tienda', emp:'900001', descFijo:5 },
    { key:'G2', nombre:'BENI SUBGER', cargo:'Subgerente',        emp:'900002', descFijo:4 }
  ],
  asesores: [
    { key:'A1', nombre:'CARO ASESORA', cargo:'Asesor', emp:'900003', descFijo:3 },
    { key:'A2', nombre:'DANI ASESOR',  cargo:'Asesor', emp:'900004', descFijo:1 }
  ]
};
const SUPABASE_FALSO = { createClient: () => ({
  auth: { getSession: async () => ({ data:{ session:null } }), signOut: async () => ({}) },
  from: () => ({ select(){ return this; }, eq(){ return this; }, maybeSingle: async () => ({ data:null }),
                 upsert: async () => ({ error:null }) }),
  rpc: async () => ({ data:null }) }) };

/* Un Date que, sin argumentos, dice la hora que se le pida. */
function relojEn(iso){
  const fijo = new Date(iso).getTime();
  return class extends Date {
    constructor(...a){ a.length ? super(...a) : super(fijo); }
    static now(){ return fijo; }
  };
}

const fallos = [];
// Martes 22-sep-2026, hora de la Ciudad de México (UTC-6).
for(const [cuando, iso] of [['6:30 p. m.', '2026-09-23T00:30:00Z'],
                            ['11:50 p. m.', '2026-09-23T05:50:00Z'],
                            ['10:00 a. m.', '2026-09-22T16:00:00Z']]){
  const ent = crearEntorno({ html, ruta:'/tablero-odemas/horarios.html',
    extras:{ supabase: SUPABASE_FALSO, Date: relojEn(iso) } });
  if(ent.err){ fallos.push('la página se cae al cargar -> ' + ent.err); break; }
  try{
    ent.correr('aplicarEquipo(' + JSON.stringify(EQUIPO) + ');');
    ent.correr('fijarSesion({ store_id:"1217", nombre:"A" }, { empno:"900003", puesto:"Asesor" });');
    ent.correr('const _d = generarSemana(_semana, null, null); renderTabla(_semana, _domingo, _d, calcularComidas(_d));');
  }catch(e){ fallos.push(cuando + ': no pinta -> ' + (e && e.message)); continue; }
  const movil = ent.htmlDe('vista-movil');
  const hoy = movil.split('<div class="mv-dia').filter(t => /^ mv-hoy/.test(t));
  if(hoy.length !== 1){ fallos.push(`${cuando}: se esperaba UN día marcado como hoy y hay ${hoy.length}`); continue; }
  const dia = (hoy[0].match(/mv-fecha">([^<]*)<b>(\d+)/) || []).slice(1).join(' ');
  if(!/\b22$/.test(dia)) fallos.push(`${cuando} del martes 22: la tarjeta marca como hoy «${dia}»`);
}

if(fallos.length){
  console.log('horario hoy: ' + fallos.length + ' fallo(s)');
  fallos.forEach(f => console.log('   · ' + f));
  process.exit(1);
}
console.log('horario hoy: el día marcado es el del teléfono a las 10 a. m., 6:30 p. m. y 11:50 p. m.');
