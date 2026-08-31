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

   Nota: los números de empleado son casi consecutivos (747851, 747854),
   así que quien conozca uno puede probar los vecinos. Es mucho mejor
   que el PIN impreso en el cartel, pero no es un secreto fuerte.
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

-- ── 3. El equipo de la 1217 ─────────────────────────────────────────
-- Números del reporte "Comisiones HES" de Sonar; el de Laura lo dio Ángel
-- (ojo: el de Laura es de 5 dígitos, no de 6 como el resto).
insert into public.empleados (store_id, empno, nombre, puesto) values
  ('1217', '749608', 'Ángel de Jesús Perea Arias',    'Gerente de Tienda'),
  ('1217', '973345', 'Miguel Ángel García Gutiérrez', 'Subgerente de Tienda'),
  ('1217', '747854', 'Arnulfo González Arrieta',      'Asesor de Tienda'),
  ('1217', '747851', 'Arturo Aguilar Rosete',         'Asesor de Tienda'),
  ('1217', '11857',  'Laura Bonilla Galán',           'Asesor de Tienda')
on conflict (store_id, empno) do nothing;

-- Cinthya Nelly Saldaña Hernández (970431) YA NO trabaja en la tienda
-- (confirmado por Ángel el 30-jul-2026), aunque siga apareciendo en el
-- reporte de comisiones de Sonar. No se registra.

-- ── 4. Comprobación ─────────────────────────────────────────────────
-- Cada uno debe poder entrar con su número:
select emp_no, emp_nombre, emp_puesto, store_id from public.login_empleado('747851');
select emp_no, emp_nombre from public.login_empleado('11857');   -- Laura, 5 dígitos

-- Y un número que no existe no debe devolver nada:
select count(*) as debe_ser_cero from public.login_empleado('123456');

-- Quién está registrado:
select empno, nombre, puesto, activo from public.empleados where store_id='1217' order by nombre;

/* ============================================================
   CUANDO CONFIRMES QUE TODOS ENTRAN CON SU NÚMERO, se cierra la
   puerta compartida (el PIN de tienda) con esto:

   -- update public.tiendas set asesor_pin = null where store_id = '1217';
   -- drop function if exists public.login_asesor(text);

   Mientras no lo hagas, el PIN 1217 sigue funcionando como respaldo,
   para que nadie se quede fuera a media jornada.
   ============================================================ */
