/* ============================================================
   HES Red — que el subgerente tenga su propia cuenta
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   HOY: solo el dueño de la tienda (el correo de tienda) puede
   administrar. El subgerente entra con su número, pero no puede tocar
   la tabla del equipo.

   CON ESTO: se registra con SU correo y, al entrar, la app lo reconoce
   como parte del equipo de la tienda con permiso de Admin.
   Queda claro quién hizo cada cambio, y si se va se le quita el
   permiso sin cambiarle la contraseña a nadie más.

   Cómo se enlazan las dos cosas: en Admin → Equipo se escribe el
   correo de la persona en su ficha. Cuando esa persona crea su cuenta
   con ESE correo e inicia sesión, se vincula sola.
   ============================================================ */

-- ── 1. La ficha del empleado guarda su correo y su cuenta ───────────
alter table public.empleados add column if not exists email   text;
alter table public.empleados add column if not exists user_id uuid;

comment on column public.empleados.email is
  'Correo con el que esa persona inicia sesión. Al entrar por primera vez, su cuenta se vincula sola.';

create unique index if not exists empleados_user_id_uniq
  on public.empleados (user_id) where user_id is not null;

-- ── 2. ¿Quien está usando la app administra esta tienda? ────────────
-- Vale el dueño de la tienda (correo de tienda) y cualquier empleado
-- vinculado que tenga admin. SECURITY DEFINER para que no choque con las
-- propias políticas que la usan.
create or replace function public.admin_de(p_store_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
      select 1 from public.tiendas t
      where t.store_id = p_store_id and t.user_id = auth.uid()
    ) or exists (
      select 1 from public.empleados e
      where e.store_id = p_store_id and e.user_id = auth.uid()
        and e.activo = true and e.admin = true
    );
$$;

grant execute on function public.admin_de(text) to authenticated;

-- ── 3. Vincular la cuenta recién creada con su ficha ────────────────
-- La llama la app después de iniciar sesión. Busca una ficha con ese
-- correo y le pega el usuario. Devuelve la tienda a la que pertenece.
create or replace function public.vincular_mi_cuenta()
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text;
  v_store text;
  v_nombre text;
  v_admin boolean;
  v_empno text;
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
  returning e.store_id, e.nombre, e.admin, e.empno
       into v_store, v_nombre, v_admin, v_empno;

  if v_store is null then
    return json_build_object('ok', false, 'error', 'sin ficha');
  end if;
  return json_build_object('ok', true, 'store_id', v_store, 'nombre', v_nombre,
                           'admin', v_admin, 'empno', v_empno);
end $$;

grant execute on function public.vincular_mi_cuenta() to authenticated;

-- ── 4. Permisos: el dueño Y los admin vinculados ────────────────────
-- Tienda: leerla y editar su configuración
do $$
declare p record;
begin
  for p in select policyname, cmd from pg_policies
           where schemaname='public' and tablename='tiendas' and cmd in ('SELECT','UPDATE')
  loop
    execute format('drop policy %I on public.tiendas', p.policyname);
  end loop;
end $$;

create policy "gerente o admin leen la tienda"
  on public.tiendas for select to authenticated
  using (public.admin_de(store_id));

create policy "gerente o admin editan la tienda"
  on public.tiendas for update to authenticated
  using (public.admin_de(store_id))
  with check (public.admin_de(store_id));

-- Equipo: dar de alta, dar de baja y repartir permisos
drop policy if exists "el dueno administra a su gente" on public.empleados;
-- Y la de aquí mismo: sin esto, repegar el SQL falla con «policy already
-- exists». Las dos de `tiendas` se libran porque el bloque de arriba las borra
-- por nombre desde pg_policies, sean las que sean.
drop policy if exists "gerente o admin administran al equipo" on public.empleados;
create policy "gerente o admin administran al equipo"
  on public.empleados for all to authenticated
  using (public.admin_de(store_id))
  with check (public.admin_de(store_id));

-- ── 5. El correo de quien vaya a administrar ────────────────────────
-- Lo normal es ponerlo desde Admin → 👥 Equipo (✉️ Poner correo). A mano:
-- update public.empleados set email = 'su.correo@ejemplo.com'
--  where store_id = '<tienda>' and empno = '<empno>';

-- ── 6. Comprobación ─────────────────────────────────────────────────
select store_id, empno, nombre, admin, activo, email,
       (user_id is not null) as ya_vinculo_su_cuenta
from public.empleados order by store_id, admin desc, nombre;

select policyname, cmd from pg_policies
where schemaname='public' and tablename in ('tiendas','empleados') order by tablename, cmd;

/* ============================================================
   PARA QUITARLE EL ACCESO A ALGUIEN CON CUENTA:
   -- update public.empleados set admin=false, activo=false, user_id=null
   --  where store_id='1217' and empno='SU_NUMERO';
   Su cuenta seguirá existiendo, pero ya no administra ni entra.
   ============================================================ */
