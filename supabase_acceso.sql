/* ============================================================
   HES Red — cerrar la fuga de la tabla `tiendas`
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   PROBLEMA QUE RESUELVE
   Hoy la tabla `tiendas` se puede leer sin PIN y sin cuenta con la
   clave publicable que viene en el código de index.html. Eso deja a
   la vista `admin_pin` (la llave de Admin), `gas_url` (el endpoint que
   escribe en la hoja) y `sheet_url`. Además el PIN del asesor es el
   propio número de tienda (1217), que está en el QR, en la URL y en
   el pie de cada pantalla.

   CÓMO QUEDA
   · Nadie puede leer la tabla sin ser el gerente dueño.
   · El asesor entra por una función que valida el PIN del lado del
     servidor y devuelve SOLO lo que la app necesita (sin admin_pin).
   · El PIN de Admin se verifica en el servidor: ya no viaja al celular.
   · El PIN del asesor pasa a ser una columna aparte, que puedes cambiar
     sin tocar el número de tienda.

   NO se tocan las políticas de INSERT ni UPDATE, para no romper el
   registro de tiendas nuevas ni el guardado de configuración de Admin.
   ============================================================ */

-- ── 1. PIN de asesor independiente del número de tienda ──────────────
alter table public.tiendas add column if not exists asesor_pin text;

comment on column public.tiendas.asesor_pin is
  'PIN de 4 dígitos para los asesores. Si queda vacío se usa store_id (como antes).';

-- ── 2. Login del asesor: valida el PIN y entrega solo lo necesario ───
-- SECURITY DEFINER = corre con permisos del dueño de la función, así que
-- puede leer la tabla aunque quien la llame no tenga permiso de lectura.
create or replace function public.login_asesor(p_pin text)
returns table (
  store_id   text,
  nombre     text,
  ciudad     text,
  vendedores jsonb
)
language sql
security definer
set search_path = public
as $$
  select t.store_id, t.nombre, t.ciudad, to_jsonb(t.vendedores)
  from public.tiendas t
  where coalesce(t.activo, true) = true
    and length(coalesce(p_pin,'')) >= 4
    and p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  limit 1;
$$;

-- ── 3. PIN de Admin: se verifica aquí, no en el celular ──────────────
create or replace function public.verificar_pin_admin(p_store_id text, p_pin text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.tiendas t
    where t.store_id = p_store_id
      and coalesce(t.activo, true) = true
      and length(coalesce(p_pin,'')) >= 4
      and p_pin = coalesce(nullif(t.admin_pin, ''), t.store_id)
  );
$$;

-- ── 4. Permisos: los visitantes solo pueden llamar a las funciones ───
grant execute on function public.login_asesor(text)                to anon, authenticated;
grant execute on function public.verificar_pin_admin(text, text)   to anon, authenticated;

-- ── 5. Lectura de la tabla: cerrar la fuga ──────────────────────────
-- APLICADO EL 30-jul-2026. Al revisar qué políticas había (antes de borrar
-- nada) resultó que solo UNA era el problema:
--   ver_propia_tienda      [SELECT] auth.uid() = user_id   <- correcta
--   editar_propia_tienda   [UPDATE] auth.uid() = user_id   <- correcta
--   crear_tienda           [INSERT] auth.uid() = user_id   <- correcta
--   public_read_store_config [SELECT] using=true           <- LA FUGA
-- Así que no hubo que rehacer nada: se retiró solo esa, porque
-- ver_propia_tienda ya cubre el acceso legítimo del gerente dueño.
drop policy if exists public_read_store_config on public.tiendas;

-- ── 6. Comprobación ─────────────────────────────────────────────────
-- Debe devolver 1 fila con los datos de la tienda, SIN admin_pin:
select * from public.login_asesor('1217');

-- Debe devolver true con el PIN correcto de Admin y false con otro:
select public.verificar_pin_admin('1217', '1217') as pin_correcto,
       public.verificar_pin_admin('1217', '0000') as pin_incorrecto;

-- Debe quedar UNA sola política de SELECT, la del dueño:
select policyname, cmd, roles from pg_policies
where schemaname='public' and tablename='tiendas' order by cmd, policyname;

/* ============================================================
   DESPUÉS de correr esto (recomendado, en el propio SQL Editor):

   -- Un PIN para los asesores que no sea el número de tienda:
   -- update public.tiendas set asesor_pin = 'PON_4_DIGITOS' where store_id = '1217';

   -- Y un PIN de Admin distinto del número de tienda:
   -- update public.tiendas set admin_pin = 'OTROS_4_DIGITOS' where store_id = '1217';

   Ambos de 4 dígitos, y que no sean 1217 ni fechas obvias.
   Al cambiarlos, los asesores tendrán que volver a entrar con el nuevo.
   ============================================================ */
