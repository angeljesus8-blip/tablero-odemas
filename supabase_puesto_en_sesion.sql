/* ============================================================
   HES Red — que el PUESTO llegue también por el login de correo
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   POR QUÉ
   Desde el 9-ago-2026 el tablero decide con el PUESTO quién ve la
   sección 🔄 Resurtir: gerente y subgerente sí, asesores no.

   El puesto ya viaja por una de las dos puertas de entrada:

     · número de empleado → login_empleado() devuelve emp_puesto  ✅
     · correo y contraseña → vincular_mi_cuenta() NO lo devuelve   ❌

   O sea que el subgerente ve una cosa entrando con su número y otra
   entrando con su correo, siendo la misma persona con el mismo
   puesto. Eso es exactamente el fallo de la cadena 1 del MAPA: el
   cliente puede nombrar el campo todo lo que quiera, si el servidor
   no lo entrega llega vacío y nadie se entera.

   MIENTRAS ESTO NO SE APLIQUE no se rompe nada: el tablero se apoya
   en el rol de la sesión, así que el subgerente sigue viendo Resurtir por
   su correo. Lo que esto arregla es que deje de depender de que
   además tenga el permiso de Admin marcado.

   Es ADITIVO: se añade un campo al JSON que ya devolvía. Lo que hoy
   lee esa respuesta (index.html: ok, store_id, nombre, admin, empno)
   sigue encontrando lo mismo en el mismo sitio.
   ============================================================ */

create or replace function public.vincular_mi_cuenta()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email  text;
  v_store  text;
  v_nombre text;
  v_admin  boolean;
  v_empno  text;
  v_puesto text;
begin
  select lower(u.email) into v_email from auth.users u where u.id = auth.uid();
  if v_email is null then
    return json_build_object('ok', false, 'error', 'sin sesion');
  end if;

  update public.empleados e
     set user_id = auth.uid()
   where lower(e.email) = v_email
     and e.activo = true
     and (e.user_id is null or e.user_id = auth.uid())
  returning e.store_id, e.nombre, e.admin, e.empno, e.puesto
       into v_store, v_nombre, v_admin, v_empno, v_puesto;

  if v_store is null then
    return json_build_object('ok', false, 'error', 'sin ficha');
  end if;

  return json_build_object('ok', true, 'store_id', v_store, 'nombre', v_nombre,
                           'admin', v_admin, 'empno', v_empno,
                           'puesto', v_puesto);
end $$;

grant execute on function public.vincular_mi_cuenta() to authenticated;

-- ── Comprobación ────────────────────────────────────────────────────
-- 1) Que nadie del equipo se haya quedado sin puesto. Si aparece algún
--    NULL o vacío, esa persona NO vería Resurtir aunque sea subgerente:
--    se arregla desde Admin → 👥 Equipo, o con el update de abajo.
select store_id, empno,
       coalesce(nullif(trim(puesto),''), '⚠ SIN PUESTO') as puesto,
       admin, activo
  from public.empleados
 order by store_id, activo desc, empno;

-- 2) Que el login por número siga trayéndolo (esta puerta ya funcionaba).
--    Con el número del subgerente tiene que decir 'Subgerente de Tienda':
--    select emp_nombre, emp_puesto from public.login_empleado('<empno>');

-- 3) `vincular_mi_cuenta` NO se puede probar desde el SQL Editor: necesita
--    una sesión de usuario (auth.uid()), y aquí no hay ninguna. Se comprueba
--    en la app: el subgerente entra con su CORREO y tiene que ver 🔄 Resurtir.

-- Si a alguien le falta el puesto, se pone así (ejemplo):
-- update public.empleados set puesto = 'Subgerente de Tienda'
--  where store_id = '<tienda>' and empno = '<empno>';

/* ============================================================
   Los puestos que la app reconoce como "lleva la tienda" son los
   que empiezan por Gerente o Subgerente. La lista completa que usa
   Admin al dar de alta es:

     Gerente de Tienda · Subgerente de Tienda · Asesor de Tienda
     Encargado de Tienda · Auxiliar de Tienda

   Encargado y Auxiliar NO ven Resurtir. Si algún día tienen que
   verlo, se agregan a PUESTOS_GESTION en tablero.html.
   ============================================================ */
