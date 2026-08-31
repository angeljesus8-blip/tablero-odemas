/* ============================================================
   HES Red — quién puede entrar a Admin
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   QUÉ CAMBIA
   Hoy Admin se abre con el PIN 1217, que está impreso en el QR: quien
   tenga el link puede editar promos, precios, EOL y comisiones.
   Con esto Admin se habilita según QUIÉN entró:
     · Ángel, con su correo y contraseña (como hasta ahora), o con su
       número de empleado;
     · Miguel, con su número de empleado (es subgerente y también
       necesita subir archivos);
     · el resto del equipo, no.
   El teclado del PIN desaparece de Admin.

   El permiso se marca aquí, no en el teléfono: la app pregunta al
   servidor cada vez que se abre Admin, así que no sirve de nada
   manipular lo que está guardado en el navegador.
   ============================================================ */

-- ── 1. Marca de quién administra ────────────────────────────────────
alter table public.empleados add column if not exists admin boolean not null default false;

comment on column public.empleados.admin is
  'true = esta persona puede abrir Admin (subir catálogo, promos, EOL, comisiones).';

update public.empleados set admin = true
where store_id = '1217' and empno in ('749608', '973345');   -- Ángel (gerente) y Miguel (subgerente)

-- ── 2. El login ahora dice si la persona administra ─────────────────
-- Se recrea porque cambia lo que devuelve (Postgres no deja cambiarlo al vuelo).
drop function if exists public.login_empleado(text);

create or replace function public.login_empleado(p_pin text)
returns table (
  store_id   text,
  nombre     text,
  ciudad     text,
  vendedores jsonb,
  emp_no     text,
  emp_nombre text,
  emp_puesto text,
  emp_admin  boolean
)
language sql
security definer
set search_path = public
as $$
  select t.store_id, t.nombre, t.ciudad, to_jsonb(t.vendedores),
         e.empno, e.nombre, e.puesto, e.admin
  from public.empleados e
  join public.tiendas t on t.store_id = e.store_id
  where e.activo = true
    and coalesce(t.activo, true) = true
    and length(coalesce(p_pin,'')) >= 4
    and e.empno = p_pin
  limit 1;
$$;

grant execute on function public.login_empleado(text) to anon, authenticated;

-- ── 3. Comprobación al abrir Admin ──────────────────────────────────
-- La app llama a esto cada vez que se abre Admin, en vez de creerle al
-- navegador. Sin el número de alguien autorizado, no hay entrada.
create or replace function public.puede_admin(p_store_id text, p_empno text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.empleados e
    where e.store_id = p_store_id
      and e.empno    = p_empno
      and e.activo   = true
      and e.admin    = true
  );
$$;

grant execute on function public.puede_admin(text, text) to anon, authenticated;

-- ── 4. Verificación ─────────────────────────────────────────────────
-- Ángel y Miguel deben dar true; Arturo, Arnulfo y Laura, false:
select public.puede_admin('1217','749608') as angel_gerente,
       public.puede_admin('1217','973345') as miguel_subgerente,
       public.puede_admin('1217','747851') as arturo,
       public.puede_admin('1217','11857')  as laura,
       public.puede_admin('1217','999999') as inventado;

-- El login debe traer ya la marca de admin:
select emp_no, emp_nombre, emp_admin from public.login_empleado('973345');
select emp_no, emp_nombre, emp_admin from public.login_empleado('11857');

-- Quién administra:
select empno, nombre, puesto, admin from public.empleados where store_id='1217' order by admin desc, nombre;

/* ============================================================
   PARA QUITAR O DAR ADMIN A ALGUIEN después:
   -- update public.empleados set admin = true  where store_id='1217' and empno='SU_NUMERO';
   -- update public.empleados set admin = false where store_id='1217' and empno='SU_NUMERO';

   PARA DAR DE BAJA A ALGUIEN (deja de poder entrar a la app):
   -- update public.empleados set activo = false where store_id='1217' and empno='SU_NUMERO';
   ============================================================ */
