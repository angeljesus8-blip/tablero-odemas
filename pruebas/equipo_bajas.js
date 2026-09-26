/* ============================================================
   Admin → Equipo: quien se da de baja sale de la lista, y si regresa
   se le da de alta otra vez
   ============================================================
   26-sep-2026. Corre en cada commit desde `verificar.py`.

   Pedido de Ángel: «si lo das de baja, que desaparezca; si vuelve a entrar al
   equipo, se vuelve a dar de alta». La ficha NO se borra —el número es único
   en la tienda y un toque equivocado sería irreversible—, así que lo que se
   prueba es que la pantalla se comporte como si sí:

     1. la lista enseña solo a los activos, y dice cuántos se dieron de baja;
     2. dar de alta el número de alguien dado de baja REACTIVA su ficha (un
        update sobre su id), no intenta insertar otra —la base la rechazaría
        con «ese número ya está registrado»—;
     3. los permisos de quien regresa empiezan de cero, y si su correo cambió
        se suelta la cuenta vieja;
     4. un número ACTIVO repetido se sigue rechazando, y uno nuevo se inserta.

   Del archivo solo interesan `pintarEquipo` y `altaEmpleado`: se extraen y se
   corren con un DOM y una base de mentira, como `humo_menu.js`.
   ============================================================ */
'use strict';
const fs = require('fs'), path = require('path'), vm = require('vm');

const html = fs.readFileSync(path.join(__dirname, '..', 'admin.html'), 'utf8');
const trozo = nombre => {
  const m = html.match(new RegExp('(?:async )?function ' + nombre + '\\([\\s\\S]*?\\n\\}'));
  return m ? m[0] : null;
};
const piezas = ['escHtml', 'pintarEquipo', 'altaEmpleado'].map(trozo);
if (piezas.some(p => !p)) {
  console.log('equipo bajas: no encontré escHtml, pintarEquipo o altaEmpleado en admin.html — ¿se renombraron?');
  process.exit(1);
}

function montar(equipo, campos) {
  const els = {};
  const el = id => (els[id] = els[id] || { id, innerHTML: '', value: '', checked: false,
                                           style: {}, textContent: '' });
  Object.entries(campos || {}).forEach(([k, v]) => {
    if (typeof v === 'boolean') el(k).checked = v; else el(k).value = v;
  });
  const llamadas = [];
  const resultados = [];
  // Una consulta de supabase-js de mentira: guarda qué se pidió y devuelve la fila.
  const sb = {
    from(tabla) {
      const q = { tabla, op: null, fila: null, eq: null };
      llamadas.push(q);
      const cadena = {
        insert(f) { q.op = 'insert'; q.fila = f; return cadena; },
        update(f) { q.op = 'update'; q.fila = f; return cadena; },
        eq(c, v)  { q.eq = [c, v]; return cadena; },
        select()  { return cadena; },
        single()  {
          const prev = q.op === 'update' ? equipo.find(x => x.id === q.eq[1]) : {};
          return Promise.resolve({ data: Object.assign({ id: q.op === 'insert' ? 999 : q.eq[1] }, prev, q.fila),
                                   error: null });
        }
      };
      return cadena;
    }
  };
  const caja = {
    console, sb,
    _cfg: { store_id: '9999' },
    _equipo: equipo.map(e => Object.assign({}, e)),
    document: { getElementById: el },
    showResult: (id, ok, msg) => resultados.push({ ok, msg }),
    pintarDivergencias: () => {}
  };
  vm.createContext(caja);
  vm.runInContext(piezas.join('\n') + '\n;globalThis.__alta = altaEmpleado; globalThis.__pintar = pintarEquipo;',
                  caja, { filename: 'admin-equipo.js' });
  return { caja, el, llamadas, resultados };
}

const EQUIPO = [
  { id: 1, empno: '100001', nombre: 'ELENA NAVARRO', puesto: 'Gerente de Tienda', activo: true,  admin: true,  ventas_dia: true,  email: 'elena@ejemplo.com', user_id: 'u1' },
  { id: 2, empno: '100002', nombre: 'LUIS ORTEGA',   puesto: 'Asesor de Tienda',  activo: true,  admin: false, ventas_dia: false, email: null, user_id: null },
  { id: 3, empno: '100003', nombre: 'ANA RAMIREZ',   puesto: 'Asesor de Tienda',  activo: false, admin: true,  ventas_dia: true,  email: 'ana@ejemplo.com', user_id: 'u3' }
];

const fallos = [];
const ok = (titulo, cond, extra) => { if (!cond) fallos.push(titulo + (extra ? ' -> ' + extra : '')); };

(async () => {
  // 1 · La lista: solo activos, y dice cuántos se fueron.
  {
    const m = montar(EQUIPO);
    m.caja.__pintar();
    const h = m.el('equipoLista').innerHTML;
    ok('1 los activos salen en la lista', h.includes('ELENA NAVARRO') && h.includes('LUIS ORTEGA'));
    ok('1 quien se dio de baja NO sale', !h.includes('ANA RAMIREZ'));
    ok('1 ya no hay botón «Reactivar»', !/Reactivar/.test(h));
    ok('1 dice cuántos están de baja', /1 dada\(s\) de baja/.test(h), h.slice(-200));
  }

  // 2 y 3 · Regresa la que se fue, con otro correo: se reactiva su ficha.
  {
    const m = montar(EQUIPO, { nuevoEmpNo: '100003', nuevoEmpNombre: 'ANA RAMIREZ',
                               nuevoEmpPuesto: 'Asesor de Tienda', nuevoEmpAdmin: false,
                               nuevoEmpEmail: 'ana.nueva@ejemplo.com' });
    await m.caja.__alta();
    const q = m.llamadas[0] || {};
    ok('2 no inserta una ficha nueva (la base la rechazaría)', q.op === 'update', q.op);
    ok('2 reactiva SU ficha, por id', q.eq && q.eq[0] === 'id' && q.eq[1] === 3, JSON.stringify(q.eq));
    ok('2 queda activa', q.fila && q.fila.activo === true);
    ok('3 Admin como se marcó en el alta, no el de antes', q.fila && q.fila.admin === false);
    ok('3 «Ventas del día» empieza apagado', q.fila && q.fila.ventas_dia === false);
    ok('3 con correo nuevo se suelta la cuenta vieja', q.fila && q.fila.user_id === null);
    ok('2 el alta se da por buena', m.resultados[0] && m.resultados[0].ok === true, JSON.stringify(m.resultados));
    m.caja.__pintar();
    const h = m.el('equipoLista').innerHTML;
    ok('2 vuelve a salir en la lista, una sola vez', (h.match(/ANA RAMIREZ/g) || []).length === 1);
  }

  // 3 · Regresa con el MISMO correo: su cuenta sigue atada.
  {
    const m = montar(EQUIPO, { nuevoEmpNo: '100003', nuevoEmpNombre: 'ANA RAMIREZ',
                               nuevoEmpPuesto: 'Asesor de Tienda', nuevoEmpEmail: 'ana@ejemplo.com' });
    await m.caja.__alta();
    const q = m.llamadas[0] || {};
    ok('3 con el mismo correo no se toca la cuenta', q.fila && !('user_id' in q.fila), JSON.stringify(q.fila));
  }

  // 4 · Número activo repetido: se rechaza, sin tocar la base.
  {
    const m = montar(EQUIPO, { nuevoEmpNo: '100002', nuevoEmpNombre: 'OTRA PERSONA' });
    await m.caja.__alta();
    ok('4 un número activo repetido se rechaza', m.resultados[0] && m.resultados[0].ok === false
       && /Ya hay alguien/.test(m.resultados[0].msg), JSON.stringify(m.resultados));
    ok('4 y no se escribe nada', m.llamadas.length === 0);
  }

  // 4 · Número nuevo: se inserta en esta tienda.
  {
    const m = montar(EQUIPO, { nuevoEmpNo: '100009', nuevoEmpNombre: 'PERSONA NUEVA',
                               nuevoEmpPuesto: 'Asesor de Tienda' });
    await m.caja.__alta();
    const q = m.llamadas[0] || {};
    ok('4 un número nuevo se inserta', q.op === 'insert', q.op);
    ok('4 en la tienda de la sesión, con su número', q.fila && q.fila.store_id === '9999' && q.fila.empno === '100009');
  }

  if (fallos.length) {
    console.log('equipo bajas: ' + fallos.length + ' fallo(s)');
    fallos.forEach(f => console.log('   · ' + f));
    process.exit(1);
  }
  console.log('equipo bajas: quien se da de baja sale de la lista, y al volver a darlo de alta se reactiva su ficha');
})();
