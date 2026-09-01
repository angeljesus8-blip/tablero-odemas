/* ============================================================
   HES Red — un PIN por persona: su número de empleado
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   QUÉ CAMBIA
   Hoy todos entran con el mismo PIN (el número de tienda, que está
   impreso en el QR). Con esto cada quien entra con SU número de
   empleado, así que:
     · si alguien deja la tienda, se desactiva solo su acceso;
     · la app sabe QUIÉN entró (sirve para autollenar el vendedor en
       Captura de Series y para firmar los apartados de preventa).

   Nota: los números de empleado de una misma tienda suelen ser casi
   consecutivos, así que quien conozca uno puede probar los vecinos. Es
   mucho mejor que el PIN impreso en el cartel, pero no es un secreto
   fuerte.
   ============================================================ */

-- ── 1. Tabla de empleados por tienda ────────────────────────────────
create table if not exists public.empleados (
  id         bigserial primary key,
  store_id   text not null,
  empno      text not null,
  nombre     text not null,
  puesto     text,
  activo     boolean not null default true,
  created_at timestamptz default now(),
  unique (store_id, empno)
);

comment on table public.empleados is
  'Personas que entran a HES Red. El empno es su PIN. Solo el gerente dueño de la tienda la administra.';

alter table public.empleados enable row level security;

-- Solo el gerente dueño de esa tienda puede ver y administrar a su gente.
-- (El login de los asesores NO pasa por aquí: usa la función de abajo.)
drop policy if exists "el dueno administra a su gente" on public.empleados;
create policy "el dueno administra a su gente"
  on public.empleados for all
  to authenticated
  using      (exists (select 1 from public.tiendas t where t.store_id = empleados.store_id and t.user_id = auth.uid()))
  with check (exists (select 1 from public.tiendas t where t.store_id = empleados.store_id and t.user_id = auth.uid()));

-- ── 2. Login por número de empleado ─────────────────────────────────
-- Devuelve la config de la tienda MÁS quién es la persona. Nunca el admin_pin.
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.login_empleado(text);

create or replace function public.login_empleado(p_pin text)
returns table (
  store_id   text,
  nombre     text,
  ciudad     text,
  vendedores jsonb,
  emp_no     text,
  emp_nombre text,
  emp_puesto text
)
language sql
security definer
set search_path = public
as $$
  select t.store_id, t.nombre, t.ciudad, to_jsonb(t.vendedores),
         e.empno, e.nombre, e.puesto
  from public.empleados e
  join public.tiendas t on t.store_id = e.store_id
  where e.activo = true
    and coalesce(t.activo, true) = true
    and length(coalesce(p_pin,'')) >= 4
    and e.empno = p_pin
  limit 1;
$$;

grant execute on function public.login_empleado(text) to anon, authenticated;

-- ── 3. El equipo ────────────────────────────────────────────────────
/* AQUÍ NO VAN NOMBRES. Este repo es público, y una lista de empleados con
   nombre completo y número lo es de las dos formas que importan: identifica
   a personas, y el número ES la llave con la que entran a la app.

   El alta se hace en **Admin → 👥 Equipo**, que escribe en esta misma tabla
   y no exige tocar SQL. Es el camino normal: no hace falta ningún empleado
   registrado para abrir Admin la primera vez —el gerente entra con su sesión
   de Supabase, la del correo con el que registró la tienda—.

   Si aun así prefieres darlos de alta de golpe (un equipo grande, una
   migración), esta es la forma. Escríbela en `_privado/equipo.sql`, que el
   .gitignore deja fuera, y pégala después de este archivo — igual que el
   mapeo de nombres del reporte, en supabase_accesorios_reporte.sql:

     insert into public.empleados (store_id, empno, nombre, puesto) values
       ('<tienda>', '<empno>', 'NOMBRE APELLIDOS', 'Gerente de Tienda'),
       ('<tienda>', '<empno>', 'NOMBRE APELLIDOS', 'Asesor de Tienda')
     on conflict (store_id, empno) do nothing;

   El `puesto` se escribe tal cual: de él salen el permiso de corregir ventas
   (`puede_gestionar_`) y lo que la app enseña a cada quien.

   Ojo con los números: no todos tienen la misma longitud. En la tienda donde
   nació esto había uno de 5 dígitos entre cuatro de 6, y el teclado de la app
   —que entra solo al llegar a 6— tuvo que aprender a esperar. Copia el número
   del reporte de comisiones, sin rellenarlo con ceros.

   Y a quien ya no trabaje en la tienda, NO lo registres: aunque siga saliendo
   en el reporte regional, aquí un número registrado es una puerta abierta. */

-- ── 4. Comprobación ─────────────────────────────────────────────────
-- Sustituye <empno> por el número de alguien ya dado de alta en Admin.
-- Debe devolver su nombre, su puesto y su tienda:
--   select emp_no, emp_nombre, emp_puesto, store_id
--     from public.login_empleado('<empno>');

-- Y un número que no existe no debe devolver nada:
select count(*) as debe_ser_cero from public.login_empleado('123456');

-- Quién está registrado (todas las tiendas de esta base):
select store_id, empno, nombre, puesto, activo
  from public.empleados order by store_id, nombre;

/* ============================================================
   CUANDO CONFIRMES QUE TODOS ENTRAN CON SU NÚMERO, se cierra la
   puerta compartida (el PIN de tienda) con esto:

   -- update public.tiendas set asesor_pin = null where store_id = '<tienda>';
   -- drop function if exists public.login_asesor(text);

   Mientras no lo hagas, el PIN de tienda sigue funcionando como
   respaldo, para que nadie se quede fuera a media jornada.
   ============================================================ */
