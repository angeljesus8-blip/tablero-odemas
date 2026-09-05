-- Generado por armar_sql.py. No se edita a mano: se edita el .sql
-- que toque y se vuelve a generar, o el cambio se pierde.
--
-- Se pega ENTERO en el SQL Editor de Supabase, de una vez y en este
-- orden. Cada archivo lleva al final sus propias comprobaciones.
--
-- 30 archivos, en 4 etapas.


--------------------------------------------------------------
--  ETAPA: Base — la tienda y quien entra
--------------------------------------------------------------


-- ========== supabase_00_tiendas.sql ==========

-- ============================================================
--  LA TABLA `tiendas` — el primer archivo, antes que cualquier otro
-- ============================================================
--
--  POR QUE ESTE ARCHIVO ES NUEVO
--  ------------------------------------------------------------
--  En la tienda de origen esta tabla NO estaba versionada en ningun sitio: se
--  creo a mano en el panel de Supabase y nunca se escribio el `create table`.
--  Todo lo demas —las diez tablas del esquema, las 80 funciones— cuelga de
--  ella: `store_id` es clave foranea en todas y `escritura_ok_` la consulta en
--  cada guardado.
--
--  O sea que el proyecto entero no se podia volver a montar desde cero. Se
--  reconstruye aqui a partir de como la usan el SQL y las cinco pantallas.
--
--  Se corre PRIMERO. Sin esta tabla, `supabase_migracion_esquema.sql` falla en
--  su primera linea con «relation "tiendas" does not exist».


-- ── 1 · La tabla ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.tiendas (
  -- El numero de tienda tal cual lo dice el POS. Es texto y no entero: se
  -- compara con lo que imprime el ticket y con lo que teclea el asesor, y una
  -- tienda con cero delante dejaria de casar si esto fuera numerico.
  store_id   text PRIMARY KEY,

  -- La cuenta del gerente que la registro. Las tres politicas de RLS de abajo
  -- cuelgan de aqui: es lo unico que separa una tienda de otra.
  user_id    uuid REFERENCES auth.users(id) ON DELETE SET NULL,

  nombre     text NOT NULL,
  ciudad     text,

  /* LA CREDENCIAL DE ESCRITURA. El nombre viene del Apps Script, que ya no
     existe; lo que hay detras es `escritura_ok_` (supabase_preventa_series.sql)
     y las 36 funciones que la exigen para guardar una venta, apartar una pieza
     o dar de alta a alguien.

     La genera la base, no el navegador. Escrita a mano acabaria siendo el
     numero de tienda —que es publico— y esta cadena es lo unico que separa a
     quien puede guardar ventas de quien no. 32 hex = 128 bits, con
     gen_random_uuid() y no con random(), que es predecible. */
  gas_token  text NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),

  -- Quien puede abrir «Ventas del dia» en Captura de Series, ademas del
  -- gerente y el subgerente. Es el NOMBRE del asesor, tal cual esta en
  -- `vendedores`: se compara letra por letra.
  hoja_auth  text,

  /* El equipo, para los desplegables. Array de verdad y no "a,b,c": partir una
     cadena por comas rompe con los nombres compuestos.

     jsonb y NO text[]. Los dos aguantan lo que hace la app —PostgREST convierte
     el array de JavaScript a cualquiera de los dos, y `to_jsonb()` de vuelta
     tambien—, asi que la diferencia no se ve al usarla: se ve al pegar el SQL.
     `supabase_hoja_auth.sql` comprueba el nombre con
     `jsonb_array_elements_text(vendedores)`, que con text[] truena con
     «function jsonb_array_elements_text(text[]) does not exist» y **corta el
     pegado a la mitad** (31-ago-2026, montando la primera copia).

     jsonb es ademas lo que hay en la tienda de origen: ahi ya se intento
     `unnest(vendedores)` dando por hecho que era text[] y fallo al reves
     («function unnest(jsonb) does not exist», 4-ago-2026). Que las dos bases
     tengan el mismo tipo es lo que permite copiar un SQL de una a otra. */
  vendedores jsonb NOT NULL DEFAULT '[]'::jsonb,

  -- PIN de Admin y PIN de asesor. Si quedan vacios se usa `store_id`, que es
  -- lo que hacia antes de que existieran. Ver supabase_acceso.sql.
  admin_pin  text,
  asesor_pin text,

  -- A donde lleva una notificacion push al tocarla. Ver
  -- supabase_notificaciones.sql; vacio = el aviso se manda sin enlace.
  app_url    text,

  -- Dar de baja una tienda sin borrarla: sus ventas y su historico se quedan.
  -- Los logins comprueban `coalesce(activo, true)`.
  activo     boolean NOT NULL DEFAULT true,

  creada_en  timestamptz NOT NULL DEFAULT now()
);

/* ── 1-bis · Y para una base que YA tiene la tabla ──────────
   `CREATE TABLE IF NOT EXISTS` no toca una tabla que ya existe: no anade
   columnas ni cambia tipos. Asi que en una base donde `tiendas` se creo antes
   —la tienda de origen, o un pegado que se corto a la mitad— todo lo de arriba
   no hace NADA, y el pegado sigue como si estuviera puesto.

   Paso el 31-ago-2026: el primer intento creo `tiendas` con `vendedores
   text[]`, y al repegar el archivo corregido la columna seguia siendo text[]
   —el CREATE no se aplica— y volvia a morir en el mismo sitio.

   Por eso cada columna se repite aqui como ALTER. Es redundante a proposito:
   el CREATE describe la tabla, esto la arregla donde ya estaba. */
ALTER TABLE public.tiendas
  ADD COLUMN IF NOT EXISTS user_id        uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ciudad         text,
  ADD COLUMN IF NOT EXISTS gas_token      text NOT NULL DEFAULT replace(gen_random_uuid()::text, '-', ''),
  ADD COLUMN IF NOT EXISTS hoja_auth      text,
  ADD COLUMN IF NOT EXISTS vendedores     jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS admin_pin      text,
  ADD COLUMN IF NOT EXISTS asesor_pin     text,
  ADD COLUMN IF NOT EXISTS app_url        text,
  ADD COLUMN IF NOT EXISTS activo         boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS creada_en      timestamptz NOT NULL DEFAULT now();

/* El tipo, no solo la existencia. Si la columna ya estaba como `text[]`, el
   ADD COLUMN de arriba no hace nada y se queda mal. Con `USING to_jsonb(...)`
   la convierte sin perder los nombres, y si ya es jsonb no cambia nada. */
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'tiendas'
                AND column_name = 'vendedores' AND data_type <> 'jsonb') THEN
    ALTER TABLE public.tiendas
      ALTER COLUMN vendedores DROP DEFAULT,
      ALTER COLUMN vendedores TYPE jsonb USING to_jsonb(vendedores),
      ALTER COLUMN vendedores SET DEFAULT '[]'::jsonb;
  END IF;
END $$;

COMMENT ON TABLE public.tiendas IS
  'Una fila por tienda. Todo lo demas cuelga de store_id.';
COMMENT ON COLUMN public.tiendas.gas_token IS
  'Credencial de ESCRITURA de Supabase (escritura_ok_). El nombre es herencia '
  'del Apps Script, que ya no existe. La genera la base sola.';


-- ── 2 · RLS: cada gerente ve y toca SOLO su tienda ──────────
-- Sin esto, cualquiera con la anon key —que viaja en el HTML, que es publico—
-- podria leer los token de escritura de TODAS las tiendas. Y con un token se
-- puede escribir en esa tienda: seria la llave de la casa pegada en la puerta.
ALTER TABLE public.tiendas ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS ver_propia_tienda    ON public.tiendas;
DROP POLICY IF EXISTS editar_propia_tienda ON public.tiendas;
DROP POLICY IF EXISTS crear_tienda         ON public.tiendas;

CREATE POLICY ver_propia_tienda    ON public.tiendas FOR SELECT
  USING (auth.uid() = user_id);
CREATE POLICY editar_propia_tienda ON public.tiendas FOR UPDATE
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY crear_tienda         ON public.tiendas FOR INSERT
  WITH CHECK (auth.uid() = user_id);

/* NO se crea ninguna politica de SELECT publica.

   Hubo una —`public_read_store_config`, con `using(true)`— y estuvo abierta
   meses: cualquiera con la anon key podia leer la tabla entera. Se retiro el
   30-jul-2026. El asesor no la necesita: entra por `login_asesor`, que es
   SECURITY DEFINER y devuelve solo los campos que hacen falta, nunca los PIN.

   Si algun dia una pantalla «no ve la tienda», la respuesta NO es volver a
   abrir el SELECT: es pasar por una funcion SECURITY DEFINER que entregue lo
   justo. */


-- ── 3 · Comprobacion ────────────────────────────────────────
-- Tiene que devolver exactamente estas tres politicas y ninguna mas:
--   crear_tienda [INSERT] · editar_propia_tienda [UPDATE] · ver_propia_tienda [SELECT]
SELECT policyname, cmd FROM pg_policies
 WHERE schemaname = 'public' AND tablename = 'tiendas'
 ORDER BY cmd, policyname;

-- Y esto tiene que dar CERO filas: una tienda sin clave de escritura se ve
-- entera y no guarda nada.
SELECT store_id, nombre FROM public.tiendas
 WHERE coalesce(gas_token, '') = '' OR length(gas_token) < 8;


-- ========== supabase_empleados.sql ==========

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
   los datos que no van en un repo publico:

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


-- ========== supabase_acceso.sql ==========

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
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.login_asesor(text);

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


-- ========== supabase_admin_por_empleado.sql ==========

/* ============================================================
   HES Red — quién puede entrar a Admin
   Correr en Supabase → SQL Editor → New query → Run.
   ------------------------------------------------------------
   QUÉ CAMBIA
   Hoy Admin se abre con el PIN 1217, que está impreso en el QR: quien
   tenga el link puede editar promos, precios, EOL y comisiones.
   Con esto Admin se habilita según QUIÉN entró:
     · el gerente, con su correo y contraseña (como hasta ahora), o con
       su número de empleado;
     · el subgerente, con su número de empleado (también necesita subir
       archivos);
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

/* Quién administra se reparte desde **Admin → 👥 Equipo**, con un botón por
   persona. Aquí no van números de empleado: este repo es público y el número
   es la llave con la que esa persona entra a la app.

   La primera vez no hace falta: el gerente abre Admin con su sesión de
   Supabase —la del correo con el que registró la tienda— y desde ahí se lo da
   a quien toque. Si alguna vez hay que hacerlo a mano, la forma es:

     -- update public.empleados set admin = true
     --  where store_id = '<tienda>' and empno in ('<empno>', '<empno>');

   Dáselo a quien de verdad suba archivos. Admin carga inventario, promos y
   comisiones de toda la tienda; no es una pantalla de consulta. */

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
-- Un número inventado NO puede administrar. Esto corre en una base recién
-- montada, sin nadie dado de alta todavía, y tiene que dar false:
select public.puede_admin('0000','999999') as inventado_no_administra;

-- Con el equipo ya cargado desde Admin, quien administre debe dar true y el
-- resto false. Sustituye <tienda> y <empno>:
--   select public.puede_admin('<tienda>','<empno>') as administra;
--   select emp_no, emp_nombre, emp_admin from public.login_empleado('<empno>');

-- Quién administra hoy, en todas las tiendas de esta base:
select store_id, empno, nombre, puesto, admin
  from public.empleados order by admin desc, store_id, nombre;

/* ============================================================
   PARA QUITAR O DAR ADMIN A ALGUIEN después:
   -- update public.empleados set admin = true  where store_id='1217' and empno='SU_NUMERO';
   -- update public.empleados set admin = false where store_id='1217' and empno='SU_NUMERO';

   PARA DAR DE BAJA A ALGUIEN (deja de poder entrar a la app):
   -- update public.empleados set activo = false where store_id='1217' and empno='SU_NUMERO';
   ============================================================ */


-- ========== supabase_cuenta_subgerente.sql ==========

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


-- ========== supabase_hoja_auth.sql ==========

-- ============================================================
-- El login debe entregar hoja_auth y sheet_url
-- APLICADO EN PRODUCCIÓN el 2-ago-2026. Ver "Lo que salió" abajo.
-- ============================================================
--
-- Qué estaba roto
-- ---------------
-- Captura de Series decide quién ve las ventas del día así:
--
--     const DESCARGA_AUTORIZADA = (_cfgCS && _cfgCS.hoja_auth) || '';
--     const ok = currentVend === DESCARGA_AUTORIZADA;
--
-- La columna `hoja_auth` existía y ya traía el nombre correcto, pero
-- login_asesor devolvía solo (store_id, nombre, ciudad, gas_url,
-- vendedores, gas_token). El dato estaba bien guardado y nunca salía:
-- llegaba undefined, se guardaba como '', y la comparación era falsa
-- para todos. El botón estuvo oculto para todo el mundo —incluida la
-- única persona que lo usa— desde el 1-ago.
--
-- El 1-ago se corrigió el nombre del campo en el cliente y se dio por
-- cerrado. El cliente pedía bien un dato que el servidor nunca mandó.
--
-- Un cambio no termina hasta probarlo de punta a punta (MAPA.md).
--
-- ------------------------------------------------------------
-- PASO 1 · Ver cómo está antes de tocar
-- ------------------------------------------------------------
SELECT store_id, nombre,
       (hoja_auth IS NOT NULL AND hoja_auth <> '') AS tiene_hoja_auth
FROM public.tiendas
ORDER BY store_id;

-- ------------------------------------------------------------
-- PASO 2 · Las columnas, por si alguna falta (otra tienda nueva)
-- ------------------------------------------------------------
-- `sheet_url` (el link a la hoja de Google) ya no se anade: no hay hoja.
ALTER TABLE public.tiendas
  ADD COLUMN IF NOT EXISTS hoja_auth text;

COMMENT ON COLUMN public.tiendas.hoja_auth IS
  'Nombre EXACTO del vendedor que puede ver las ventas del día en Captura de '
  'Series, tal como aparece en la lista de vendedores. Se compara letra por '
  'letra: una tilde o un espacio de más y deja de funcionar. Vacío = nadie.';

-- ------------------------------------------------------------
-- PASO 3 · Comprobar que el nombre coincide con la lista
-- ------------------------------------------------------------
-- Esto es lo que de verdad decide si el botón aparece. `currentVend` sale de la
-- lista de vendedores, y se compara con `===` contra `hoja_auth`: si difieren
-- en una tilde, el botón no sale y nada avisa.
--
-- La lista sale de `empleados` desde el 2-sep-2026 (ver el bloque de abajo), así
-- que la comprobación se hace contra los nombres dados de alta.
SELECT t.store_id,
       t.hoja_auth,
       EXISTS (SELECT 1 FROM public.empleados e
                WHERE e.store_id = t.store_id AND e.activo = true
                  AND e.nombre = t.hoja_auth) AS coincide_letra_por_letra
  FROM public.tiendas t
 WHERE coalesce(t.hoja_auth,'') <> ''
 ORDER BY t.store_id;

-- `coincide_letra_por_letra` tiene que ser true. Si sale false, ese nombre no
-- está en el equipo tal cual: cópialo de Admin → Equipo sin retocarlo a mano, o
-- ese asesor no podrá abrir «Ventas del día» y nada dirá por qué.

-- ------------------------------------------------------------
-- PASO 4 · Que las funciones lo entreguen  ← lo único que hacía falta
-- ------------------------------------------------------------
-- Cambia el tipo de retorno, así que CREATE OR REPLACE no basta: hay que
-- DROP primero. El cuerpo es el mismo de GAS_guardian.sql; lo único nuevo
-- son t.hoja_auth y t.sheet_url al final.
--
-- Entre el DROP y el CREATE nadie puede entrar a la app: correr de corrido.

/* Lo que el login NO nombra aqui llega VACIO al telefono, y lo que dependa de
   ese campo se apaga sin dar un error. Paso con `hoja_auth`: el gerente lo tenia
   puesto en Admin, el cliente lo leia, y el boton de las ventas del dia estuvo
   oculto para todos porque el servidor no lo devolvia.

   Los comentarios van arriba del CREATE y no entre la firma y el RETURNS TABLE:
   `r_cadenas` empareja los dos y solo admite un salto de linea, asi que un
   comentario en medio la ciega. */
/* ── DE DONDE SALE `vendedores` (2-sep-2026) ─────────────────
   De la tabla `empleados`, no de `tiendas.vendedores`.

   Hasta hoy eran DOS listas con la misma gente, las dos escritas a mano: la de
   Admin -> Equipo (quien ENTRA, con su numero) y la de Admin -> Config (los
   nombres que salen al CAPTURAR una venta). Nadie las ataba, y una letra de
   diferencia entre ellas no da error: manda las ventas de esa persona a otro
   sitio. En la tienda de origen paso con un apellido con una letra de mas —19
   ventas de accesorio y 32 de `ventas` contadas como de otra persona— y se
   descubrio a fin de mes.

   Ahora hay una sola lista y se da de alta una vez.

   `tiendas.vendedores` queda como PUENTE y solo se usa si la tienda no tiene
   a nadie dado de alta todavia: sin eso, una tienda que ya estaba funcionando
   se quedaria sin poder capturar el dia que se pegue esto, que es peor que la
   duplicacion que venimos a quitar. En cuanto haya un empleado activo, manda
   `empleados` y el campo viejo deja de mirarse. */
CREATE OR REPLACE FUNCTION public.vendedores_de_(p_store text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT jsonb_agg(e.nombre ORDER BY e.nombre)
       FROM public.empleados e
      WHERE e.store_id = p_store AND e.activo = true),
    (SELECT to_jsonb(t.vendedores) FROM public.tiendas t WHERE t.store_id = p_store),
    '[]'::jsonb);
$$;

REVOKE ALL ON FUNCTION public.vendedores_de_(text) FROM public, anon, authenticated;


DROP FUNCTION IF EXISTS public.login_asesor(text);

CREATE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb, gas_token text,
               hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id), t.gas_token,
         t.hoja_auth
  FROM public.tiendas t
  WHERE coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  LIMIT 1;
$$;

DROP FUNCTION IF EXISTS public.login_empleado(text);

CREATE FUNCTION public.login_empleado(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb,
               emp_no text, emp_nombre text, emp_puesto text, emp_admin boolean,
               gas_token text, hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id),
         e.empno, e.nombre, e.puesto, e.admin,
         t.gas_token, t.hoja_auth
  FROM public.empleados e
  JOIN public.tiendas  t ON t.store_id = e.store_id
  WHERE e.activo = true
    AND coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND e.empno = p_pin
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.login_asesor(text)   FROM public;
REVOKE ALL ON FUNCTION public.login_empleado(text) FROM public;
GRANT EXECUTE ON FUNCTION public.login_asesor(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_empleado(text) TO anon, authenticated;

-- ------------------------------------------------------------
-- PASO 5 · Comprobar que quedó, sin escribir el PIN aquí
-- ------------------------------------------------------------
-- Una fila por tienda registrada. En una base recién montada no hay ninguna
-- todavía: cero filas aquí es lo normal, y el alta se hace desde la app
-- (menú → Registrar tienda).
SELECT t.store_id,
  (SELECT count(*) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)))
    AS el_login_responde,
  (SELECT (l.hoja_auth IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS ya_entrega_hoja_auth,
  (SELECT (l.gas_token IS NOT NULL) FROM public.login_asesor(coalesce(nullif(t.asesor_pin,''), t.store_id)) l)
    AS sigue_trayendo_token
FROM public.tiendas t ORDER BY t.store_id;

/* Y que el login por número de empleado tampoco se haya roto.

   Dice en palabras si no hay a quién preguntarle: con la tabla `empleados`
   vacía, la versión anterior devolvía «0, 0, 0» y eso se lee igual que «los
   tres empleados que entran perdieron el token», que es un incendio. Una
   comprobación que devuelve lo mismo cuando todo va bien y cuando todo va mal
   no está comprobando nada. */
SELECT CASE
    WHEN count(*) = 0
      THEN 'todavía no hay nadie dado de alta — normal en una base nueva; '
           'se registran en Admin → Equipo'
    WHEN count(*) FILTER (WHERE (SELECT l.gas_token FROM public.login_empleado(e.empno) l) IS NOT NULL) = count(*)
      THEN 'los ' || count(*) || ' entran y todos reciben su clave de escritura'
    ELSE '⚠ ' || count(*) FILTER (WHERE (SELECT l.gas_token FROM public.login_empleado(e.empno) l) IS NULL)
         || ' de ' || count(*) || ' entran SIN clave de escritura: la app se '
         || 'les ve entera y no guarda nada'
  END AS login_por_numero
FROM public.empleados e
WHERE e.activo = true
  AND (SELECT count(*) FROM public.login_empleado(e.empno)) = 1;

/* ============================================================
   Lo que salió al aplicarlo — 2-ago-2026
   ============================================================

   PASO 1 · La columna hoja_auth YA existía y YA traía el nombre correcto,
            y sheet_url también. O sea que nunca hubo que tocar datos: el
            único hueco era que las funciones no lo devolvían.

   PASO 3 · coincide_exacto = 1 de 5 vendedores. El nombre calza letra por
            letra con la lista, que es lo que compara el cliente.

            Aquí salió el error del propio archivo: la primera versión usaba
            unnest(vendedores) dando por hecho que era text[]. Es jsonb.
            Se corrigió arriba.

   PASO 4 · Success. No rows returned.

   PASO 5 · login_asesor  → responde 1, entrega hoja_auth, sigue con token.
            login_empleado → 5 empleados entran, los 5 con hoja_auth y token,
                             2 admins. Nada se rompió.

   FALTA: que la persona autorizada SALGA y vuelva a ENTRAR en Captura de
   Series. La sesión
   se guarda en el aparato al entrar; con la vieja sigue sin hoja_auth y el
   botón sigue oculto aunque aquí ya esté todo bien.
   ============================================================ */


--------------------------------------------------------------
--  ETAPA: Esquema y lecturas
--------------------------------------------------------------


-- ========== supabase_migracion_esquema.sql ==========

-- ============================================================
-- HES Red — mover el tablero de Google Sheets a Supabase
-- Esquema base. NO correr completo de un jalón: ver el plan al final.
-- 1-ago-2026
-- ============================================================
--
-- Por qué
-- -------
-- Hoy cada tienda necesita su propia hoja de Google Y su propio proyecto de
-- Apps Script, con su URL pegada a mano en Admin (campo gas_url). Montar una
-- tienda son cuatro pasos manuales, y cada corrección de código obliga a
-- redesplegar en TODAS. Con diez tiendas eso no se sostiene.
--
-- Además, tres cosas que rompieron esta semana son del producto, no del código:
--   · Sheets convierte texto en fechas solo — dejó 117 promos invisibles.
--   · Apps Script descarta llamadas encimadas RESPONDIENDO 200: por eso el
--     tablero trae una cola con 1.5 s de separación. Con 30 asesores no aguanta.
--   · No hay constraints: nada impide apartar 37 piezas de un cupo de 36.
--
-- Regla de este diseño: TODA tabla lleva store_id. Cada gerente sube sus
-- documentos y sus datos quedan en su tienda; nadie ve ni pisa los de otra.
--
-- Lo que NO cambia: el flujo de trabajo del gerente. Sigue subiendo su Excel
-- de Sonar, su CEA y sus comisiones, desde las mismas pantallas.
-- ============================================================


-- ── Ayudas ──────────────────────────────────────────────────
-- admin_de(store_id) ya existe (dueño de la tienda o empleado con admin=true).
-- Se reutiliza tal cual para no inventar un modelo de permisos nuevo.

CREATE OR REPLACE FUNCTION public.toca_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END $$;


-- ── 1 · CATÁLOGO (del Informe de Artículos Totales) ─────────
-- Reemplaza las hojas Catalogo y Catalogo_ref.

CREATE TABLE IF NOT EXISTS public.catalogo (
  store_id    text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku         text        NOT NULL,
  descripcion text        NOT NULL DEFAULT '',
  upc         text,
  precio      numeric(12,2),
  -- Catalogo_ref conserva SKUs que ya no vienen en el Excel: son los agotados
  -- que el cliente sigue pidiendo y se traen de otra tienda.
  vigente     boolean     NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

-- ── 2 · INVENTARIO (On Hand + exhibición) ───────────────────
CREATE TABLE IF NOT EXISTS public.inventario (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  onhand     integer     NOT NULL DEFAULT 0 CHECK (onhand >= 0),
  exhibicion integer     NOT NULL DEFAULT 0 CHECK (exhibicion >= 0),
  -- Corte propio de exhibición: NO se reinicia con el On Hand diario, para que
  -- una pieza vendida no reaparezca al día siguiente.
  exh_vendida integer    NOT NULL DEFAULT 0 CHECK (exh_vendida >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

-- ── 3 · PROMOCIONES (del CEA) ───────────────────────────────
-- d1/d2 son DATE de verdad: se acabó el "2026-08-01" contra "Sat Aug 01 2026".
CREATE TABLE IF NOT EXISTS public.promos (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  producto   text        NOT NULL DEFAULT '',
  precio_reg numeric(12,2),
  precio_pro numeric(12,2),
  estatus    text,
  msi        text,
  vigente_desde date,
  vigente_hasta date     NOT NULL,   -- obligatoria: sin fecha no hay promo
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku),
  CONSTRAINT promo_menor_que_regular CHECK (precio_pro IS NULL OR precio_reg IS NULL OR precio_pro < precio_reg),
  CONSTRAINT vigencia_coherente CHECK (vigente_desde IS NULL OR vigente_desde <= vigente_hasta)
);
CREATE INDEX IF NOT EXISTS promos_vigentes ON public.promos (store_id, vigente_hasta);

-- ── 4 · EOL, COMBOS Y AVISOS ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.eol (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  precio     numeric(12,2),
  pausado    boolean     NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, sku)
);

CREATE TABLE IF NOT EXISTS public.bundles (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  nombre     text        NOT NULL,
  skus       text[]      NOT NULL,          -- array de verdad, no "a,b,c"
  precio     numeric(12,2) NOT NULL,
  vigente_desde date,
  vigente_hasta date     NOT NULL,
  activo     boolean     NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.avisos (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  titulo     text        NOT NULL,
  detalle    text,
  prioridad  text        NOT NULL DEFAULT 'normal',
  vigente_hasta date,
  creado_en  timestamptz NOT NULL DEFAULT now()
);

-- ── 5 · VENTAS (lo que captura el asesor) ───────────────────
CREATE TABLE IF NOT EXISTS public.ventas (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  vendida_en timestamptz NOT NULL DEFAULT now(),
  serie      text        NOT NULL,
  sku        text        NOT NULL,
  descripcion text,
  precio     numeric(12,2),
  vendedor   text        NOT NULL,
  con_seguro boolean,                        -- NULL = ventas viejas sin dato
  foto_url   text,
  UNIQUE (store_id, serie)                   -- una serie no se vende dos veces
);
CREATE INDEX IF NOT EXISTS ventas_del_dia ON public.ventas (store_id, vendida_en DESC);

-- ── 6 · APARTADOS (preventa) ────────────────────────────────
-- El cupo se respeta en la base, no en el navegador: dos asesores apartando
-- a la vez ya no pueden pasarse del límite.
CREATE TABLE IF NOT EXISTS public.preventa_cupo (
  store_id  text    NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku       text    NOT NULL,
  cupo      integer NOT NULL CHECK (cupo >= 0),
  PRIMARY KEY (store_id, sku)
);

CREATE TABLE IF NOT EXISTS public.apartados (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  sku        text        NOT NULL,
  cliente    text        NOT NULL,
  telefono   text,
  piezas     integer     NOT NULL DEFAULT 1 CHECK (piezas > 0),
  con_seguro boolean     NOT NULL DEFAULT false,
  estatus    text        NOT NULL DEFAULT 'Apartado',
  vendedor   text,
  creado_en  timestamptz NOT NULL DEFAULT now(),

  /* 31-ago-2026 · Las ocho de abajo estaban en la base de la tienda de origen
     y NO aquí, igual que le pasó a `tiendas.vendedores`. Tres de ellas
     —color, precio, transaccion— no las creaba ningún archivo: se añadieron a
     mano en el panel y el `create table` nunca se actualizó, así que la tabla
     versionada llevaba meses sin describir la tabla de verdad.

     Las otras cinco sí se añaden más abajo (preventa_series, apartados_traspaso)
     pero DESPUÉS de que `inventario_vivo` las use, y una función `LANGUAGE sql`
     se valida al crearse: el pegado moría en «column a.venta_id does not
     exist», con la base a medio montar.

     Declararlas aquí no rompe nada donde ya existen —este CREATE es IF NOT
     EXISTS y los ALTER de más abajo son IF NOT EXISTS— y quita la dependencia
     de orden, que es la que no se ve venir. */
  color       text,         -- el producto entero, tal como se apartó
  precio      numeric(12,2),
  transaccion text,         -- ticket del POS: el enlace con la venta

  serie         text,       -- la pieza concreta, al asignarla del embarque
  asignado_en   timestamptz,
  entregado_en  timestamptz,
  entregado_por text,       -- quien la entregó, que no siempre es el vendedor
  venta_id      bigint      -- la venta que la entregó; sin ella se contaría dos veces
);

-- Y las mismas como ALTER, por la misma razón que en supabase_00_tiendas.sql:
-- donde `apartados` ya existe —la tienda de origen, o un pegado que se cortó a
-- la mitad— el CREATE de arriba no hace nada y las columnas seguirían faltando.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS color         text,
  ADD COLUMN IF NOT EXISTS precio        numeric(12,2),
  ADD COLUMN IF NOT EXISTS transaccion   text,
  ADD COLUMN IF NOT EXISTS serie         text,
  ADD COLUMN IF NOT EXISTS asignado_en   timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_en  timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_por text,
  ADD COLUMN IF NOT EXISTS venta_id      bigint;

CREATE OR REPLACE FUNCTION public.apartado_cabe()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE tope integer; usado integer;
BEGIN
  SELECT cupo INTO tope FROM public.preventa_cupo
   WHERE store_id = NEW.store_id AND sku = NEW.sku;
  IF tope IS NULL THEN RETURN NEW; END IF;   -- sin cupo definido, sin límite
  SELECT coalesce(sum(piezas),0) INTO usado FROM public.apartados
   WHERE store_id = NEW.store_id AND sku = NEW.sku
     AND estatus <> 'Cancelado' AND id <> coalesce(NEW.id, -1);
  IF usado + NEW.piezas > tope THEN
    RAISE EXCEPTION 'Cupo agotado: % de % piezas ya apartadas', usado, tope;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS apartado_cabe_trg ON public.apartados;
CREATE TRIGGER apartado_cabe_trg BEFORE INSERT OR UPDATE ON public.apartados
  FOR EACH ROW EXECUTE FUNCTION public.apartado_cabe();

-- ── 7 · COMISIONES ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.comisiones (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  empno      text        NOT NULL,
  nombre     text        NOT NULL,
  puesto     text,
  venta      numeric(14,2),
  ppto_pct   numeric(6,2),
  alcance    numeric(6,2),
  gar_pct    numeric(6,2),
  gar_pzas   integer,
  gar_elegible integer,
  gar_monto  numeric(12,2),
  periodo    text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, empno)
);
-- Ojo: alcance y gar_pct SÍ pueden pasar de 100 (ventana de 30 días para
-- comprar el seguro), así que aquí NO va un CHECK <= 100.


-- ── 8 · RLS — cada tienda ve solo lo suyo ───────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo','inventario','promos','eol','bundles',
                           'avisos','ventas','preventa_cupo','apartados','comisiones']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_admin', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated
         USING (public.admin_de(store_id)) WITH CHECK (public.admin_de(store_id))',
      t||'_admin', t);
  END LOOP;
END $$;

-- El asesor entra por PIN, no con cuenta de Supabase, así que NO lee las tablas
-- directo: lo hace por funciones SECURITY DEFINER que validan su PIN, igual que
-- login_asesor. Se definen en el siguiente archivo para no alargar este.


-- ── 9 · updated_at automático ───────────────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['catalogo','inventario','promos','eol','bundles','comisiones']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.%I', t||'_touch', t);
    EXECUTE format('CREATE TRIGGER %I BEFORE UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.toca_updated_at()',
                   t||'_touch', t);
  END LOOP;
END $$;


-- ============================================================
-- PLAN — por fases, sin apagar nada hasta que lo nuevo funcione
--
--  1. Correr este archivo. No toca nada de lo que hay: solo crea tablas
--     vacías. El tablero sigue leyendo del Apps Script.
--  2. Copiar los datos de hoy de las 10 hojas a estas tablas (838 filas en
--     total; un script lo hace en un rato).
--  3. Las funciones de lectura para el asesor (SECURITY DEFINER + PIN).
--  4. Las pantallas de carga escriben en LOS DOS lados un par de semanas.
--     Si algo sale mal, se apaga el nuevo y nadie se entera.
--  5. El tablero lee de Supabase, con el GAS como respaldo.
--  6. Se apaga el Apps Script. Y con él: la hoja por tienda, el despliegue
--     por tienda y el campo gas_url de Admin.
--
-- Montar una tienda nueva pasa de "crear hoja + crear script + desplegar +
-- pegar URL" a un INSERT en tiendas.
-- ============================================================


-- ========== supabase_funciones_lectura.sql ==========

-- ============================================================
-- Fase 1 · Las lecturas del Apps Script, traducidas a SQL
-- 2-ago-2026 · APLICADO (comprobado el 4-ago: las siete responden en Supabase
--              con datos reales — 215 SKUs, 117 promos, las ventas históricas)
--
-- Decía "NO APLICADO TODAVÍA" dos días después de estar corriendo. Si la
-- cabecera de un archivo no se puede creer, no sirve de nada: comprobar contra
-- la base antes de fiarse.
--
-- Faltaban SEIS lecturas más que las apps sí usan. Están en
-- `supabase_funciones_lectura_resto.sql`.
-- ============================================================
--
-- Cada función de aquí tiene que devolver EXACTAMENTE lo mismo que su modo del
-- GAS. Mientras no coincidan, no se pasa a la fase 2.
--
-- Se traduce lógica que costó descubrir. Los comentarios dicen por qué es así,
-- no qué hace: sin eso, alguien lo "simplifica" y rompe algo que ya se pagó.
--
-- ------------------------------------------------------------
-- PASO 0 · Los cortes de inventario dejan de ser propiedades sueltas
-- ------------------------------------------------------------
-- En el GAS viven en Propiedades del script como dos JSON gigantes
-- (`ventaBaseline` y `exhibBaseline`). Ahí no se pueden consultar, ni auditar,
-- ni saber cuándo se tomaron. Como tabla, sí.
--
-- Por qué son DOS y no uno: el On Hand se sube a diario y reinicia su corte;
-- la exhibición se sube solo cuando se exhibe algo nuevo. Si el corte diario
-- reiniciara también el de piso, una pieza de exhibición ya vendida
-- reaparecería al día siguiente. Eso pasó y por eso están separados.

CREATE TABLE IF NOT EXISTS public.inventario_corte (
  store_id   text NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  tipo       text NOT NULL CHECK (tipo IN ('onhand','exhibicion')),
  sku        text NOT NULL,
  vendidas   integer NOT NULL DEFAULT 0 CHECK (vendidas >= 0),
  tomado_en  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, tipo, sku)
);
ALTER TABLE public.inventario_corte ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.inventario_corte IS
  'Foto del total de ventas por SKU en el momento de subir un reporte. tipo=onhand '
  'se retoma a diario con el Excel de almacén; tipo=exhibicion solo cuando se sube '
  'el piso. Lo vendido "desde el corte" es (ventas totales - vendidas).';

-- El SKU de una venta puede venir vacío: pasa cuando se captura a las prisas.
-- Son ventas reales y no se pueden perder por un dato que falta.
ALTER TABLE public.ventas ALTER COLUMN sku DROP NOT NULL;

-- ------------------------------------------------------------
-- 1 · INVENTARIO EN VIVO  ←  leerInventario_
-- ------------------------------------------------------------
-- La más delicada de todas. Se verificó CONTANDO CAJAS EN PISO que el reporte
-- On Hand NO incluye las piezas de exhibición: son cantidades independientes y
-- no se restan entre sí. Si alguien "corrige" esto restando, el tablero va a
-- mostrar menos stock del que hay y se van a perder ventas.
CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH vendidas AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
    GROUP BY v.sku
  )
  SELECT
    c.sku,
    c.descripcion,
    c.precio,
    coalesce(i.onhand, 0)                                            AS onhand,
    -- vendido DESDE el corte diario, no en total
    greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0))::int AS vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, coalesce(i.onhand,0)
              - greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0)))::int AS stock,
    coalesce(i.exhibicion, 0)                                        AS exhibicion,
    -- vendido desde la última subida de piso, con su propio corte
    greatest(0, coalesce(vd.total,0) - coalesce(ce.vendidas,0))::int AS exh_vendida
  FROM public.catalogo c
  LEFT JOIN public.inventario i  ON i.store_id  = c.store_id AND i.sku  = c.sku
  LEFT JOIN vendidas vd          ON vd.sku      = c.sku
  LEFT JOIN public.inventario_corte co
         ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
  LEFT JOIN public.inventario_corte ce
         ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
  WHERE c.store_id = p_store;
$$;

-- ------------------------------------------------------------
-- 2 · PRECIO DE REMATE AL 50%  ←  leerEolVenta_
-- ------------------------------------------------------------
-- Solo para los EOL en estado "listo": ya no queda nada en almacén pero SÍ
-- queda pieza de exhibición. Ese es el único caso en que la pieza de piso se
-- puede vender, y se vende a mitad de precio.
--
-- `exhib_restante` descuenta de la exhibición únicamente las ventas que se
-- pasaron del almacén — las que solo pudieron salir del piso.
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.eol_precio_venta(text);

CREATE OR REPLACE FUNCTION public.eol_precio_venta(p_store text)
RETURNS TABLE (sku text, precio50 numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT iv.sku,
         round(coalesce(nullif(e.precio, 0), iv.precio) / 2.0, 2) AS precio50
  FROM public.inventario_vivo(p_store) iv
  JOIN public.eol e ON e.store_id = p_store AND e.sku = iv.sku AND NOT e.pausado
  WHERE iv.stock = 0
    AND greatest(0, iv.exhibicion - greatest(0, iv.exh_vendida - iv.onhand)) > 0
    AND coalesce(nullif(e.precio, 0), iv.precio) > 0;
$$;

-- ------------------------------------------------------------
-- 3 · PROMOS VIGENTES  ←  leerPromos_
-- ------------------------------------------------------------
-- Aquí ya no hace falta isoFecha_: en la hoja las fechas eran texto y Sheets
-- convertía algunas a Date, así que "2026-08-01" se comparaba contra
-- "Sat Aug 01 2026..." y la promo nunca entraba. 117 promos quedaron invisibles
-- por eso. Con columnas DATE el problema desaparece de raíz.
--
-- La fecha de hoy va en hora de México, no UTC: con UTC las promos se caían
-- seis horas antes, desde las 6 pm de su último día.
CREATE OR REPLACE FUNCTION public.promos_vigentes(p_store text)
RETURNS TABLE (sku text, producto text, precio_reg numeric, precio_pro numeric,
               estatus text, msi text, vigente_desde date, vigente_hasta date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.sku, p.producto, p.precio_reg, p.precio_pro, p.estatus, p.msi,
         p.vigente_desde, p.vigente_hasta
  FROM public.promos p
  WHERE p.store_id = p_store
    AND (p.vigente_desde IS NULL
         OR p.vigente_desde <= (now() AT TIME ZONE 'America/Mexico_City')::date)
    AND p.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date;
$$;

-- ------------------------------------------------------------
-- 4 · COMBOS VIGENTES  ←  leerBundles_
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bundles_vigentes(p_store text)
RETURNS TABLE (id bigint, nombre text, skus text[], precio numeric,
               vigente_desde date, vigente_hasta date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT b.id, b.nombre, b.skus, b.precio, b.vigente_desde, b.vigente_hasta
  FROM public.bundles b
  WHERE b.store_id = p_store
    AND b.activo
    AND (b.vigente_desde IS NULL
         OR b.vigente_desde <= (now() AT TIME ZONE 'America/Mexico_City')::date)
    AND b.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date;
$$;

-- ------------------------------------------------------------
-- 5 · AVISOS VIGENTES  ←  leerAvisos_
-- ------------------------------------------------------------
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.avisos_vigentes(text);

CREATE OR REPLACE FUNCTION public.avisos_vigentes(p_store text)
RETURNS TABLE (id bigint, titulo text, detalle text, prioridad text,
               vigente_hasta date, creado_en timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.titulo, a.detalle, a.prioridad, a.vigente_hasta, a.creado_en
  FROM public.avisos a
  WHERE a.store_id = p_store
    AND (a.vigente_hasta IS NULL
         OR a.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY a.creado_en DESC;
$$;

-- ------------------------------------------------------------
-- 6 · LEADERBOARD DE ASSURANT  ←  leerVentasHoy_
-- ------------------------------------------------------------
-- `con_seguro` NULL son las ventas anteriores a julio-2026, cuando no existía
-- el campo: 124 de 223. Contarlas como "sin seguro" hundiría el attach rate sin
-- razón, así que se ignoran — igual que en el GAS.
CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.vendedor,
         count(*) FILTER (WHERE v.con_seguro)         AS con_seguro,
         count(*) FILTER (WHERE NOT v.con_seguro)     AS sin_seguro
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND v.con_seguro IS NOT NULL
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = (now() AT TIME ZONE 'America/Mexico_City')::date
  GROUP BY v.vendedor;
$$;

-- ------------------------------------------------------------
-- 7 · SERIES DEL DÍA  ←  leerVentasDetalle_
-- ------------------------------------------------------------
-- Sin fecha, las de hoy. Aquí el parámetro ya es DATE de verdad: se acabó
-- mandar "2/8/2026" como texto y rezar que coincida letra por letra.
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.ventas_detalle(text,date);

CREATE OR REPLACE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro, v.vendida_en
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY v.vendida_en;
$$;

-- ------------------------------------------------------------
-- Permisos
-- ------------------------------------------------------------
-- SECURITY DEFINER + store_id explícito: la función decide qué se ve, no el
-- cliente. Igual que login_asesor.
REVOKE ALL ON FUNCTION public.inventario_vivo(text)    FROM public;
REVOKE ALL ON FUNCTION public.eol_precio_venta(text)   FROM public;
REVOKE ALL ON FUNCTION public.promos_vigentes(text)    FROM public;
REVOKE ALL ON FUNCTION public.bundles_vigentes(text)   FROM public;
REVOKE ALL ON FUNCTION public.avisos_vigentes(text)    FROM public;
REVOKE ALL ON FUNCTION public.ventas_hoy(text)         FROM public;
REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;

GRANT EXECUTE ON FUNCTION public.inventario_vivo(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_precio_venta(text)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.promos_vigentes(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundles_vigentes(text)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.avisos_vigentes(text)     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;

/* ============================================================
   Lo que falta antes de dar esto por bueno

   Cargar los datos y comparar CADA función contra su modo del GAS con los
   mismos datos. Mientras no den idéntico, no se pasa a la fase 2.

   Los tres que más fácil van a diferir, y por qué:

   1. inventario_vivo — depende de que los cortes se carguen bien. El GAS los
      tiene como dos JSON en Propiedades del script; hay que volcarlos a
      inventario_corte tal cual, sin recalcularlos, o el "vendido desde el
      corte" saldrá distinto.

   2. eol_precio_venta — hereda lo anterior. Si el inventario difiere en un
      SKU, aquí puede aparecer o desaparecer un precio de remate.

   3. ventas_hoy — la hoja guarda la fecha como texto sin hora fiable y aquí
      es timestamptz. Al cargar hay que armar vendida_en juntando fecha y hora
      en zona de México, no en UTC.
   ============================================================ */


-- ========== supabase_funciones_lectura_resto.sql ==========

-- ============================================================
-- Fase 1 (cierre) · Las SEIS lecturas que faltaban
-- 4-ago-2026
-- ============================================================
--
-- Por qué existe este archivo
-- ---------------------------
-- `supabase_funciones_lectura.sql` tradujo siete modos del Apps Script y el
-- commit los dio por buenos: "las siete lecturas dan idéntico". Es cierto, y
-- aun así la fase 1 no estaba cerrada: **las apps usan trece lecturas, no
-- siete**. Se contó lo que se había escrito, no lo que hacía falta.
--
-- Estas son las seis que quedaban, sacadas con grep de los seis html y no de
-- memoria:
--
--   modo=todo          tablero          ← el viaje único; sin esto la fase 2
--                                         no da la velocidad que promete
--   modo=catalogo      captura_series   ← el autollenado al teclear un SKU
--   modo=apartados     tablero          ← la preventa
--   modo=eol_cloud     tablero, admin
--   modo=comisiones    comisiones, admin
--   modo=estado        captura, admin, actualizar_datos
--
-- Igual que las otras siete: SECURITY DEFINER con store_id explícito, para que
-- decida el servidor y no el cliente.
-- ============================================================


-- ------------------------------------------------------------
-- PASO 0 · Dos datos que el GAS da y el esquema no sabía guardar
-- ------------------------------------------------------------
-- `modo=estado` devuelve catBy y promoBy —quién subió el último catálogo y las
-- últimas promos— y actualizar_datos.html lo muestra en pantalla ("Por ..."),
-- que es como el gerente sabe quién tocó los precios por última vez.
--
-- En el esquema nuevo no había dónde ponerlo. Migrar sin esto no rompe nada,
-- pero borra una respuesta que hoy se puede dar. Se añade ahora, que es barato;
-- las escrituras de la fase 4 solo tendrán que llenarlo.
ALTER TABLE public.catalogo   ADD COLUMN IF NOT EXISTS subido_por text;
ALTER TABLE public.promos     ADD COLUMN IF NOT EXISTS subido_por text;

-- El GAS guarda DOS periodos de comisiones: el de venta y el de garantías, que
-- no coinciden. La tabla solo tenía uno.
ALTER TABLE public.comisiones ADD COLUMN IF NOT EXISTS periodo_gar text;


-- ------------------------------------------------------------
-- 8 · CATÁLOGO COMPLETO  ←  leerCatalogo_
-- ------------------------------------------------------------
-- Aquí se devuelven FILAS; el índice lo arma el cliente. Y tiene que armarlo
-- con cuidado, porque esto es lo que costó un producto invisible:
--
-- Hay códigos de barras comodín compartidos por varios productos —6942100000000
-- lo usan seis—. Cuando el catálogo se indexaba SOLO por código, se pisaban
-- entre sí y sobrevivía uno; los demás desaparecían y al teclear su SKU no
-- salía nada, sin ningún aviso. Por eso cada SKU lleva SIEMPRE su entrada
-- propia `sku:XXXX` además de la del código.
--
-- El upc se devuelve tal cual, como texto. Nunca como número: en la hoja, un
-- código en notación científica acabó redondeado y seis productos terminaron
-- compartiendo el mismo.
CREATE OR REPLACE FUNCTION public.catalogo_completo(p_store text)
RETURNS TABLE (sku text, descripcion text, upc text,
               precio numeric, onhand integer, vigente boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT c.sku, c.descripcion, c.upc, c.precio,
         coalesce(i.onhand, 0)::int AS onhand,
         c.vigente
  FROM public.catalogo c
  LEFT JOIN public.inventario i ON i.store_id = c.store_id AND i.sku = c.sku
  WHERE c.store_id = p_store
  ORDER BY c.sku;
$$;


-- ------------------------------------------------------------
-- 9 · LISTA DE EOL  ←  leerEolCloud_
-- ------------------------------------------------------------
-- Los EOL marcados y no pausados. Distinto de eol_precio_venta, que solo trae
-- los que YA están en remate al 50%; este trae todos los marcados.
--
-- 111 de 133 no tienen precio ni propio ni en el catálogo (fase 1, hallazgo 3).
-- Se devuelven igual, con precio NULL: el tablero los tiene que listar aunque
-- no pueda calcularles el remate. Filtrarlos aquí los haría desaparecer de la
-- pantalla sin que nadie supiera por qué.
CREATE OR REPLACE FUNCTION public.eol_lista(p_store text)
RETURNS TABLE (sku text, precio numeric, precio_efectivo numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.sku,
         e.precio,
         -- el que se usaría para el 50%: propio, y si no, el del catálogo
         coalesce(nullif(e.precio, 0), c.precio) AS precio_efectivo
  FROM public.eol e
  LEFT JOIN public.catalogo c ON c.store_id = e.store_id AND c.sku = e.sku
  WHERE e.store_id = p_store
    AND NOT e.pausado
  ORDER BY e.sku;
$$;


-- ------------------------------------------------------------
-- 10 · APARTADOS  ←  leerApartados_
-- ------------------------------------------------------------
-- Trae también el cupo y lo ya apartado, que en el GAS el tablero calculaba por
-- su cuenta sumando en el navegador. Contarlo aquí es lo que hace que dos
-- asesores apartando a la vez no puedan pasarse del límite: el trigger
-- apartado_cabe usa esta misma suma.
--
-- Los cancelados NO cuentan para el cupo pero SÍ se devuelven: el gerente tiene
-- que poder ver que existieron.
-- 31-ago-2026 · DROP delante. Esta función se vuelve a definir más abajo en
-- el pegado con OTRAS columnas, así que repegar el archivo entero sobre una
-- base que ya tiene la versión de después falla con «42P13: cannot change
-- return type of existing function» y deja el pegado a medias. Con el DROP,
-- el SQL se puede volver a pegar tantas veces como haga falta. El GRANT de
-- más abajo vuelve a abrirla: el DROP se lleva los permisos por delante.
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE OR REPLACE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         pc.cupo,
         (SELECT coalesce(sum(x.piezas), 0)::int
            FROM public.apartados x
           WHERE x.store_id = a.store_id AND x.sku = a.sku
             AND x.estatus <> 'Cancelado') AS apartadas
  FROM public.apartados a
  LEFT JOIN public.preventa_cupo pc
         ON pc.store_id = a.store_id AND pc.sku = a.sku
  WHERE a.store_id = p_store
  ORDER BY a.creado_en DESC;
$$;


-- ------------------------------------------------------------
-- 11 · COMISIONES  ←  leerComisiones_
-- ------------------------------------------------------------
-- alcance y gar_pct SÍ pueden pasar de 100: hay una ventana de 30 días para
-- comprar el seguro, así que un vendedor puede cerrar el mes por encima del
-- 100 %. Si alguien mete aquí un LEAST(...,100) "para que se vea bien", estará
-- borrando trabajo hecho de verdad.
CREATE OR REPLACE FUNCTION public.comisiones_lista(p_store text)
RETURNS TABLE (empno text, nombre text, puesto text, venta numeric,
               ppto_pct numeric, alcance numeric, gar_pct numeric,
               gar_pzas integer, gar_elegible integer, gar_monto numeric,
               periodo text, periodo_gar text, actualizado timestamptz)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT k.empno, k.nombre, k.puesto, k.venta, k.ppto_pct, k.alcance,
         k.gar_pct, k.gar_pzas, k.gar_elegible, k.gar_monto,
         k.periodo, k.periodo_gar, k.updated_at
  FROM public.comisiones k
  WHERE k.store_id = p_store
  ORDER BY k.venta DESC NULLS LAST;
$$;


-- ------------------------------------------------------------
-- 12 · ESTADO DE LAS SUBIDAS  ←  modo=estado
-- ------------------------------------------------------------
-- En el GAS esto sale de Propiedades del script (catCount, catAt, promoCount…),
-- que se escriben a mano en cada subida y pueden quedar mintiendo si una subida
-- falla a medias. Aquí se cuenta la tabla: el número no puede desincronizarse
-- de los datos porque ES los datos.
--
-- `ventasGid` no se devuelve: era el id de pestaña de la hoja de Google, para
-- abrirla en el navegador. Cuando no haya hoja no significará nada.
CREATE OR REPLACE FUNCTION public.estado_datos(p_store text)
RETURNS TABLE (cat_count integer, cat_at timestamptz, cat_by text,
               cat_ref_count integer,
               promo_count integer, promo_at timestamptz, promo_by text,
               comis_at timestamptz, comis_periodo text,
               ventas_total integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT
    (SELECT count(*)::int FROM public.catalogo WHERE store_id = p_store AND vigente),
    (SELECT max(updated_at) FROM public.catalogo WHERE store_id = p_store),
    (SELECT subido_por FROM public.catalogo
      WHERE store_id = p_store AND subido_por IS NOT NULL
      ORDER BY updated_at DESC LIMIT 1),
    (SELECT count(*)::int FROM public.catalogo WHERE store_id = p_store AND NOT vigente),
    (SELECT count(*)::int FROM public.promos WHERE store_id = p_store),
    (SELECT max(updated_at) FROM public.promos WHERE store_id = p_store),
    (SELECT subido_por FROM public.promos
      WHERE store_id = p_store AND subido_por IS NOT NULL
      ORDER BY updated_at DESC LIMIT 1),
    (SELECT max(updated_at) FROM public.comisiones WHERE store_id = p_store),
    (SELECT periodo FROM public.comisiones
      WHERE store_id = p_store AND periodo IS NOT NULL LIMIT 1),
    (SELECT count(*)::int FROM public.ventas WHERE store_id = p_store);
$$;


-- ------------------------------------------------------------
-- 13 · TODO DE UN VIAJE  ←  modo=todo
-- ------------------------------------------------------------
-- El modo que justifica media migración. En el Apps Script el tablero no puede
-- pedir siete cosas a la vez: las llamadas encimadas se descartan RESPONDIENDO
-- 200, así que hay una cola con 1.5 s de separación y abrir el tablero cuesta
-- ~4 s. `modo=todo` se inventó para meterlo en un solo viaje.
--
-- Aquí no hay cola ni descarte, así que esto podrían ser siete llamadas en
-- paralelo. Se mantiene igualmente en una: es un viaje de red en vez de siete
-- desde un celular en la tienda, y deja el cambio del cliente en algo pequeño.
--
-- Devuelve jsonb con las mismas siete claves que el GAS, para que la fase 2 sea
-- cambiar de dónde se pide y no reescribir el tablero.
CREATE OR REPLACE FUNCTION public.tablero_todo(p_store text)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'inventario', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.inventario_vivo(p_store) t),
    'eol',        (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.eol_lista(p_store) t),
    'eol_venta',  (SELECT coalesce(jsonb_object_agg(t.sku, t.precio50), '{}'::jsonb)
                     FROM public.eol_precio_venta(p_store) t),
    'promos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.promos_vigentes(p_store) t),
    'bundles',    (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.bundles_vigentes(p_store) t),
    'avisos',     (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.avisos_vigentes(p_store) t),
    'apartados',  (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.apartados_lista(p_store) t),
    'ventas_hoy', (SELECT coalesce(jsonb_agg(to_jsonb(t)), '[]'::jsonb)
                     FROM public.ventas_hoy(p_store) t)
  );
$$;


-- ------------------------------------------------------------
-- Permisos
-- ------------------------------------------------------------
REVOKE ALL ON FUNCTION public.catalogo_completo(text) FROM public;
REVOKE ALL ON FUNCTION public.eol_lista(text)         FROM public;
REVOKE ALL ON FUNCTION public.apartados_lista(text)   FROM public;
REVOKE ALL ON FUNCTION public.comisiones_lista(text)  FROM public;
REVOKE ALL ON FUNCTION public.estado_datos(text)      FROM public;
REVOKE ALL ON FUNCTION public.tablero_todo(text)      FROM public;

GRANT EXECUTE ON FUNCTION public.catalogo_completo(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_lista(text)         TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartados_lista(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.comisiones_lista(text)  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.estado_datos(text)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.tablero_todo(text)      TO anon, authenticated;


/* ============================================================
   Antes de dar la fase 1 por cerrada — esta vez de verdad

   Comparar CADA una de las trece contra su modo del GAS con los mismos datos.
   No vale contar las que están escritas: eso fue lo que dejó seis fuera.

   El comparador no puede llamar al GAS desde fuera: desde el 4-ago el endpoint
   exige token. Se corre desde el navegador con la sesión abierta, que ya lo
   tiene — así el token no sale a ningún lado. Ver MIGRACION_comparar.js.

   Lo que más fácil va a diferir, y por qué:

   1. catalogo — el GAS entrega un objeto ya indexado (por código y por
      `sku:XXXX`); aquí son filas. Comparar los CONJUNTOS de SKU y los valores,
      no la forma. Si falta un SKU, es el bug de los códigos comodín otra vez.

   2. estado — no puede dar idéntico a propósito: el GAS lee contadores
      guardados a mano y esto cuenta las filas. Si difieren, lo más probable es
      que el contador del GAS esté mintiendo, no que falte un dato aquí.
      Comprobarlo contra la hoja antes de "arreglar" nada.

   3. apartados — el GAS no devuelve cupo ni apartadas; se calculaban en el
      navegador. Comparar solo los campos que existen en los dos lados.
   ============================================================ */


-- ========== supabase_horarios.sql ==========

-- ============================================================
--  HORARIOS — traer el planeador a HES Red (4-ago-2026)
-- ============================================================
-- Hasta hoy el planeador vivía en un proyecto de Supabase aparte
-- (lgnyqfstmcqpkbekspte) con su propio login y su propio PIN. El equipo entraba
-- dos veces: su número en el tablero, y otro PIN para ver su horario.
--
-- Esto lo trae al proyecto de HES Red, con las mismas reglas que el resto:
--   · toda tabla lleva store_id
--   · escribe quien administra la tienda -> admin_de(store_id), la misma
--     función que ya cuida `tiendas` y `empleados` (dueño O subgerente con
--     admin = true). Hasta hoy el subgerente NO podía editar horarios.
--   · el asesor no tiene cuenta de Supabase: lee por una función
--     SECURITY DEFINER que valida su número, igual que login_empleado.
--
-- Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
-- Es idempotente: se puede volver a correr sin romper nada.
-- ============================================================


-- ── 1 · La tabla ────────────────────────────────────────────
-- Mismas cuatro claves que ya usaba el planeador, ahora por tienda y no por
-- usuario: así el gerente y el subgerente ven y editan el MISMO horario. Antes
-- colgaba de user_id, o sea que solo existía para quien lo hubiera creado.
CREATE TABLE IF NOT EXISTS public.horarios_config (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  clave      text        NOT NULL,
  contenido  jsonb       NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, clave),
  -- Un typo en el nombre de la clave creaba una fila huérfana que nadie leía y
  -- nadie reportaba. Que falle de frente.
  CONSTRAINT horarios_clave_valida
    CHECK (clave IN ('equipo','historial','excepciones','semanas_guardadas'))
);


-- ── 2 · RLS ─────────────────────────────────────────────────
ALTER TABLE public.horarios_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS horarios_config_admin ON public.horarios_config;
CREATE POLICY horarios_config_admin ON public.horarios_config
  FOR ALL TO authenticated
  USING (public.admin_de(store_id))
  WITH CHECK (public.admin_de(store_id));

-- Nadie anónimo lee esta tabla directo. El asesor pasa por horario_equipo().


-- ── 3 · updated_at ──────────────────────────────────────────
DROP TRIGGER IF EXISTS horarios_config_touch ON public.horarios_config;
CREATE TRIGGER horarios_config_touch
  BEFORE UPDATE ON public.horarios_config
  FOR EACH ROW EXECUTE FUNCTION public.toca_updated_at();


-- ── 4 · Lectura del asesor, con su número de empleado ───────
-- Sustituye a get_horario_publico(p_pin) del proyecto viejo. Ya no hay un PIN
-- compartido que haya que cambiarle a todos cuando alguien se va: se le da de
-- baja en Admin -> Equipo (activo = false) y deja de ver el horario.
--
-- Devuelve las cuatro claves. `semanas_guardadas` va tal cual, así que se acaba
-- el rodeo de publicar una foto dentro de excepciones.__publicadas: eso existía
-- solo porque el RPC viejo no la devolvía y no había permiso para cambiarlo.
CREATE OR REPLACE FUNCTION public.horario_equipo(p_store_id text, p_empno text)
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE WHEN EXISTS (
      SELECT 1 FROM public.empleados e
      WHERE e.store_id = p_store_id
        AND e.empno    = p_empno
        AND e.activo   = true
    )
    THEN (
      SELECT json_object_agg(
               h.clave,
               -- El PIN viejo del planeador quedó guardado dentro de `equipo`.
               -- No tiene por qué bajar al teléfono de nadie.
               CASE WHEN h.clave = 'equipo' THEN h.contenido - 'pin' ELSE h.contenido END)
      FROM public.horarios_config h
      WHERE h.store_id = p_store_id
    )
    ELSE NULL
  END;
$$;

GRANT EXECUTE ON FUNCTION public.horario_equipo(text, text) TO anon, authenticated;


-- ── 5 · Verificación ────────────────────────────────────────
-- Correr DESPUÉS de restaurar el respaldo desde la app.
--
--   a) La tabla quedó y tiene las cuatro claves de la 1217:
--        SELECT clave, jsonb_typeof(contenido), updated_at
--        FROM horarios_config WHERE store_id = '1217' ORDER BY clave;
--
--   b) Un número activo SÍ recibe horario (los reales, en `_privado/datos_equipo.txt`):
--        SELECT horario_equipo('1217','<empno-activo>') IS NOT NULL;   -- espera true
--
--   c) Un número que no existe NO recibe nada:
--        SELECT horario_equipo('1217','000000');               -- espera NULL
--
--   d) El PIN viejo no viaja en la respuesta:
--        SELECT horario_equipo('1217','<empno-activo>')->'equipo'->'pin';  -- espera NULL
--
--   e) La tabla NO se puede leer sin cuenta. Desde fuera, con la clave
--      publicable que está en el HTML:
--        curl "https://rjdrljtujbwooejrpyqv.supabase.co/rest/v1/horarios_config?select=*" \
--             -H "apikey: <clave publicable>"
--      Espera [] — si devuelve filas, la política no quedó.


-- ========== supabase_venta_guardar.sql ==========

-- ============================================================
-- Fase 3 · Guardar una venta en Supabase (doble escritura)
-- 4-ago-2026 · APLICADO y probado el mismo día
--
-- Probado contra la base antes de conectar el cliente:
--   alta          -> {"ok":true,"id":692}
--   la misma otra vez -> {"ok":true,"duplicada":true}   (no error: reintento)
--   sin serie     -> {"ok":false,"error":"sin serie"}
--   una de las 8:30 p.m. -> dia_venta 2026-08-04 y hora 20:30 en México,
--                           NO el día siguiente, que era el riesgo real
--   filas de prueba borradas: 231 ventas antes y después
-- ============================================================
--
-- Regla que manda sobre todo lo demás
-- -----------------------------------
-- **El Sheet sigue siendo la fuente de verdad.** Esto se escribe ADEMÁS, nunca
-- en lugar de. Si esta función falla, la venta ya está guardada en el Sheet y
-- no se pierde nada; si fallara al revés, se perdería una venta, y eso ya pasó
-- el 1-ago-2026 y costó un día entero.
--
-- Por eso la función **no lanza nunca**: devuelve el problema como jsonb. Del
-- lado del cliente, un fallo aquí no puede tocar la cola de pendientes ni el
-- aviso al asesor.
--
-- Dos decisiones que no son obvias
-- --------------------------------
-- 1 · **Una serie repetida el mismo día NO es un error aquí.** La restricción
--     `ventas_serie_por_dia` existe para atrapar la doble captura humana, pero
--     en doble escritura el mismo INSERT puede llegar dos veces por un reintento
--     de red. Devolver error haría que el cliente reintentara para siempre. Se
--     responde `ok:true, duplicada:true`: la venta está, que es lo que importa.
--     Así la escritura es idempotente y se puede reintentar sin miedo.
--
-- 2 · **La fecha se arma aquí, no en el teléfono.** Llegan `fecha` y `hora` como
--     texto ('4/8/2026', '01:26 p.m.') porque es lo que guarda la cola de
--     capturas pendientes, que puede subirse horas después. Convertirlas en el
--     cliente significaría depender de la zona del aparato: una venta de las
--     8 pm acabaría con la fecha del día siguiente. Aquí se fija en hora de
--     México, igual que hace `isoVenta_` en el Apps Script.
-- ============================================================

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,   -- '4/8/2026'  (d/M/yyyy, como la hoja)
  p_hora       text    DEFAULT NULL,   -- '01:26 p.m.'
  p_foto_url   text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- fecha: d/M/yyyy. Sin fecha reconocible se usa ahora, que es mejor que
  -- rechazar la venta: el dato existe y ya está en el Sheet.
  m := regexp_match(coalesce(p_fecha,''), '^(\d{1,2})/(\d{1,2})/(\d{4})$');
  IF m IS NULL THEN
    v_cuando := now();
  ELSE
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    -- hora: '1:26 p.m.' / '13:26'. Sin hora usable, mediodía: no se pasa de día
    -- en ninguna zona.
    m := regexp_match(lower(coalesce(p_hora,'')), '(\d{1,2}):(\d{2})\s*([ap])?');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF m[3] = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF m[3] = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := (format('%s-%s-%s %s:%s', v_a, lpad(v_m::text,2,'0'), lpad(v_d::text,2,'0'),
                        lpad(v_h::text,2,'0'), lpad(v_min::text,2,'0'))::timestamp)
                AT TIME ZONE 'America/Mexico_City';
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro, foto_url)
  VALUES
    (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
     nullif(trim(coalesce(p_desc,'')),''), p_precio,
     nullif(trim(coalesce(p_vendedor,'')),''), p_seguro,
     nullif(trim(coalesce(p_foto_url,'')),''))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  WHEN unique_violation THEN
    -- ya estaba: reintento de red, no un problema
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text) IS
  'Doble escritura de la fase 3. El Sheet manda; esto escribe ADEMAS. No lanza '
  'nunca: devuelve el problema en jsonb para que un fallo aqui no pueda tocar la '
  'cola de capturas. Una serie repetida el mismo dia responde ok+duplicada, '
  'para que un reintento de red no se convierta en un bucle.';


-- ------------------------------------------------------------
-- Comprobar antes de conectar el cliente
-- ------------------------------------------------------------
--   select public.venta_guardar('1217','PRUEBA-F3-1','100304280','prueba',
--                               999,'prueba',true,'4/8/2026','01:26 p.m.');
--     → {"ok": true, "id": ...}
--
--   -- la misma otra vez: debe decir duplicada, NO error
--   select public.venta_guardar('1217','PRUEBA-F3-1','100304280','prueba',
--                               999,'prueba',true,'4/8/2026','01:26 p.m.');
--     → {"ok": true, "duplicada": true}
--
--   -- la fecha tiene que caer en el día correcto, no en el siguiente
--   select serie, dia_venta, vendida_en at time zone 'America/Mexico_City' as hora_mx
--   from public.ventas where serie = 'PRUEBA-F3-1';
--     → dia_venta 2026-08-04 y hora 13:26
--
--   delete from public.ventas where serie like 'PRUEBA-F3-%';
-- ============================================================


-- ========== supabase_ventas_devolucion.sql ==========

-- ============================================================
-- Una serie SÍ se puede vender dos veces: devolución y reventa
-- 4-ago-2026 · APLICADO y probado el mismo día
-- ============================================================
--
-- Probado en la base, no sobre el papel:
--   · misma serie el 4 y el 5 de agosto  → las dos entran (devolución)
--   · otra vez el 5 de agosto            → ERROR 23505,
--     "duplicate key value violates unique constraint ventas_serie_por_dia"
--   · las filas de prueba, borradas; 220 ventas antes y después
--
-- **El código de error es 23505.** Es el que la captura tiene que reconocer en
-- la fase 3 para decir "esa serie ya se capturó hoy" en vez de tragárselo.
-- ============================================================
--
-- Qué estaba mal
-- --------------
-- El esquema traía `UNIQUE (store_id, serie)` con el comentario "una serie no
-- se vende dos veces". Suena obvio y es falso: si un cliente devuelve un equipo
-- y se revende, la misma serie sale dos veces, con toda la razón.
--
-- Los datos ya lo decían. Al cotejar la hoja el 2-ago aparecieron DOS series
-- repetidas, y no son el mismo caso:
--
--   · terminada en 4925 — 8-jul y 19-jul, once días aparte, mismo SKU, precio
--     y vendedor. Devolución y reventa. Legítimo.
--   · terminada en 3098 — las dos el 1-ago, mismo SKU, precio y vendedor. Ese
--     fue el día en que la app decía que guardaba sin guardar y se recapturó a
--     mano. Doble captura del mismo equipo. NO legítimo.
--
-- Los hallazgos de la fase 1 dejaron la decisión abierta y nadie la tomó: se
-- sorteó cargando una sola de las dos. Confirmado con Ángel el 4-ago-2026 que
-- las devoluciones pasan y son normales.
--
-- Por qué corre prisa
-- -------------------
-- Con la restricción actual, la primera reventa de un equipo devuelto hace
-- fallar el INSERT **en el mostrador, con el cliente delante**. En fase 3 la
-- venta se guarda en los dos lados: el GAS la aceptaría y Supabase no, y los
-- dos lados dejarían de cuadrar justo en la comparación que decide si se apaga
-- el GAS.
--
-- La regla correcta distingue los dos casos de arriba por sí sola: la misma
-- serie puede repetirse en DÍAS DISTINTOS (devolución), pero no dentro del
-- mismo día (doble captura).
-- ============================================================


-- ── 1 · El día de la venta, como columna propia ─────────────
-- Hace falta una columna real: (vendida_en AT TIME ZONE ...)::date no es
-- IMMUTABLE y Postgres no deja indexarla. Además deja el día a la vista, que
-- es como se consulta siempre.
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS dia_venta date;

-- Rellenar lo que ya está cargado, en hora de México y NO en UTC: una venta de
-- las 8 pm quedaría con la fecha del día siguiente.
UPDATE public.ventas
   SET dia_venta = (vendida_en AT TIME ZONE 'America/Mexico_City')::date
 WHERE dia_venta IS NULL;

ALTER TABLE public.ventas
  ALTER COLUMN dia_venta SET NOT NULL;


-- ── 2 · Que no se pueda desincronizar ───────────────────────
-- Si dia_venta se pusiera a mano y no coincidiera con vendida_en, la
-- restricción dejaría de proteger sin que nada avisara. El trigger la deriva
-- siempre, tanto al insertar como al corregir la fecha de una venta.
CREATE OR REPLACE FUNCTION public.ventas_dia_venta()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.dia_venta := (NEW.vendida_en AT TIME ZONE 'America/Mexico_City')::date;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS ventas_dia_venta_trg ON public.ventas;
CREATE TRIGGER ventas_dia_venta_trg
  BEFORE INSERT OR UPDATE OF vendida_en ON public.ventas
  FOR EACH ROW EXECUTE FUNCTION public.ventas_dia_venta();


-- ── 3 · Cambiar la restricción ──────────────────────────────
-- Se quita la vieja y se pone la nueva en la misma transacción: entre una y
-- otra no hay ni un instante sin protección contra la doble captura.
BEGIN;

ALTER TABLE public.ventas DROP CONSTRAINT IF EXISTS ventas_store_id_serie_key;

-- Y la propia, para poder repegar el SQL: `ADD CONSTRAINT` no tiene IF NOT
-- EXISTS y la segunda vez falla con «constraint already exists». Va DENTRO de
-- la transacción, así que no hay ni un instante sin la protección puesta.
ALTER TABLE public.ventas DROP CONSTRAINT IF EXISTS ventas_serie_por_dia;

ALTER TABLE public.ventas
  ADD CONSTRAINT ventas_serie_por_dia UNIQUE (store_id, serie, dia_venta);

COMMIT;

COMMENT ON CONSTRAINT ventas_serie_por_dia ON public.ventas IS
  'Una serie puede repetirse en días distintos (devolución y reventa: pasó el '
  '8-jul y el 19-jul-2026), pero no dos veces el mismo día (doble captura: pasó '
  'el 1-ago-2026 al recapturar a mano).';


-- ── 4 · Comprobar que quedó ─────────────────────────────────
-- Las dos primeras deben pasar y la tercera debe fallar. Si la tercera pasa,
-- la restricción NO está protegiendo y hay que parar antes de la fase 3.
--
--   INSERT INTO public.ventas (store_id, vendida_en, serie, sku, vendedor)
--   VALUES ('1217', '2026-08-04 10:00-06', 'PRUEBA-DEV-1', 'X', 'prueba');   -- ok
--
--   INSERT INTO public.ventas (store_id, vendida_en, serie, sku, vendedor)
--   VALUES ('1217', '2026-08-05 10:00-06', 'PRUEBA-DEV-1', 'X', 'prueba');   -- ok (otro día)
--
--   INSERT INTO public.ventas (store_id, vendida_en, serie, sku, vendedor)
--   VALUES ('1217', '2026-08-05 18:00-06', 'PRUEBA-DEV-1', 'X', 'prueba');   -- DEBE FALLAR
--
--   DELETE FROM public.ventas WHERE serie = 'PRUEBA-DEV-1';
--
-- Y lo que hay que resolver en la app antes de la fase 3: cuando el INSERT
-- falle por esta restricción, la captura tiene que DECIRLO ("esa serie ya se
-- capturó hoy"), no tragárselo. Un error que se calla aquí es una venta que
-- nadie sabe si entró.
-- ============================================================


-- ========== supabase_preventa_cupo.sql ==========

-- ============================================================
--  PREVENTA — el cupo se respeta en la base, no en el navegador
-- ============================================================
--  GENERADO por preventa_cupo_gen.py desde la const PREVENTA de tablero.html.
--  No editar a mano: cambia el cupo en tablero.html y vuelve a generarlo.
--
--  Medido el 5-ago-2026: la tabla `preventa_cupo` estaba VACÍA. El trigger
--  `apartado_cabe` ya existía, pero con el tope en NULL deja pasar todo —lo dice
--  su propia línea: "sin cupo definido, sin límite"—. O sea que el único freno
--  era el número del navegador, y dos asesores apartando la última pieza a la
--  vez podían guardarla los dos.
--
--  Al correr esto, el tope empieza a aplicarse DE VERDAD: un apartado que se
--  pase se rechaza con "Cupo agotado: X de Y piezas ya apartadas".
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · Los cupos (12 SKUs, 37 piezas) ──────────────────
-- Aqui iban los cupos de un embarque concreto: doce SKU con las piezas que le
-- tocaron a esa tienda. No se siembran. El cupo es lo que impide apartar mas
-- piezas de las que van a llegar, asi que un cupo heredado de otra tienda hace
-- exactamente el dano que esta tabla existe para evitar: prometerle a un
-- cliente una pieza que no viene.
--
--   INSERT INTO public.preventa_cupo (store_id, sku, cupo)
--   VALUES ('<tu-tienda>', '<sku>', <piezas>)
--   ON CONFLICT (store_id, sku) DO UPDATE SET cupo = excluded.cupo;



-- ── 2 · Que cancelar no cuente contra el cupo ───────────────
-- El trigger sumaba NEW.piezas siempre, incluso al marcar un apartado como
-- Cancelado: la pieza que se está liberando contaba como ocupada. Hoy no
-- estorba porque ningún SKU está al tope, pero con el cupo lleno impediría
-- cancelar — justo cuando hace falta liberar el lugar.
CREATE OR REPLACE FUNCTION public.apartado_cabe()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE tope integer; usado integer;
BEGIN
  IF NEW.estatus = 'Cancelado' THEN RETURN NEW; END IF;
  SELECT cupo INTO tope FROM public.preventa_cupo
   WHERE store_id = NEW.store_id AND sku = NEW.sku;
  IF tope IS NULL THEN RETURN NEW; END IF;   -- sin cupo definido, sin límite
  SELECT coalesce(sum(piezas),0) INTO usado FROM public.apartados
   WHERE store_id = NEW.store_id AND sku = NEW.sku
     AND estatus <> 'Cancelado' AND id <> coalesce(NEW.id, -1);
  IF usado + NEW.piezas > tope THEN
    RAISE EXCEPTION 'Cupo agotado: % de % piezas ya apartadas', usado, tope;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS apartado_cabe_trg ON public.apartados;
CREATE TRIGGER apartado_cabe_trg BEFORE INSERT OR UPDATE ON public.apartados
  FOR EACH ROW EXECUTE FUNCTION public.apartado_cabe();


-- ── 3 · Verificación ────────────────────────────────────────
--  a) Los cupos quedaron y NINGUNO está por debajo de lo ya apartado.
--     La columna `sobrepasado` tiene que salir toda en false: si alguna dice
--     true, ese SKU tiene más apartados que cupo y habría que subirle el cupo
--     o cancelar alguno ANTES de que alguien intente tocarlo.
--
--     SELECT c.sku, c.cupo,
--            coalesce(sum(a.piezas) FILTER (WHERE a.estatus <> 'Cancelado'), 0) AS apartadas,
--            coalesce(sum(a.piezas) FILTER (WHERE a.estatus <> 'Cancelado'), 0) > c.cupo AS sobrepasado
--       FROM public.preventa_cupo c
--       LEFT JOIN public.apartados a ON a.store_id = c.store_id AND a.sku = c.sku
--      WHERE c.store_id = '1217'
--      GROUP BY c.sku, c.cupo
--      ORDER BY c.sku;
--
--  b) El tope frena de verdad. Con Orange Ocean (100307499) lleno, esto DEBE
--     fallar con "Cupo agotado". Va dentro de una transacción que se deshace,
--     así que no deja rastro:
--
--     BEGIN;
--       INSERT INTO public.apartados (store_id, sku, cliente, piezas)
--       VALUES ('1217', '100307499', 'PRUEBA — no dejar', 99);
--     ROLLBACK;
--
--  c) Cancelar sigue siendo posible aunque el SKU esté al tope. (UPDATE no
--     acepta ORDER BY ... LIMIT en Postgres, de ahí la subconsulta.)
--
--     BEGIN;
--       UPDATE public.apartados SET estatus = 'Cancelado'
--        WHERE id = (SELECT id FROM public.apartados
--                     WHERE store_id = '1217' AND sku = '100307499'
--                       AND estatus <> 'Cancelado'
--                     ORDER BY id LIMIT 1);
--     ROLLBACK;


--------------------------------------------------------------
--  ETAPA: Escrituras, cargas y avisos
--------------------------------------------------------------


-- ========== supabase_cargas_admin.sql ==========

-- ============================================================
--  LAS CARGAS DE ADMIN — catálogo, inventario, exhibición,
--  promos, comisiones y catálogo_ref, directo a Supabase
--  Etapa 3 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`) y de
--  supabase_inventario_preventa.sql (el filtro de las entregas). Correr esos
--  primero.
--
--  ------------------------------------------------------------
--  SUBIR EL CATÁLOGO NO ES GUARDAR UNA TABLA: ES TOMAR EL CORTE
--  ------------------------------------------------------------
--  `actualizarCatalogo_` (GAS_Codigo.gs, l. 203-215) hace algo que no se ve en
--  su nombre: además de reescribir el catálogo, **cuenta las ventas por SKU en
--  ese instante** y las guarda como `ventaBaseline`. Todo el cálculo del stock
--  cuelga de ese número:
--
--      stock = On Hand del informe − (ventas de ahora − ventas al subirlo)
--
--  Si el corte se toma en otro momento, o contando distinto, el tablero miente
--  sobre el stock y no se entera nadie hasta que falta mercancía. Es el riesgo 1
--  del plan de migración y la función que se verificó CONTANDO CAJAS EN PISO.
--
--  Por eso el corte se toma AQUÍ DENTRO, en la misma transacción que escribe el
--  On Hand. Hacerlo en dos llamadas dejaría una ventana en la que una venta
--  cabe entre el corte y la escritura, y esa pieza se contaría dos veces.
--
--  La exhibición lleva su PROPIO corte, y eso también es a propósito: es
--  ocasional, no diaria. Con un corte compartido, una pieza de piso ya vendida
--  reaparecería con el On Hand del día siguiente.
--
--  ------------------------------------------------------------
--  EL FILTRO DE PREVENTA VA TAMBIÉN AQUÍ
--  ------------------------------------------------------------
--  Los cortes cuentan ventas, así que tienen que contar con el MISMO criterio
--  que `inventario_vivo`: sin las entregas de preventa, que el POS ya descontó.
--  Si uno excluye y el otro no, cada entrega resta una venta normal del conteo.
--  Ver supabase_inventario_preventa.sql.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · Catálogo + inventario + corte  ←  tipo:'catalogo' ───
-- p_filas: [{upc, sku, desc, onhand, precio}, ...] tal cual lo arma
-- actualizar_datos.html al parsear el Excel.
--
-- `vigente` = el SKU trae On Hand en el informe. Es la misma regla que usa el
-- Apps Script (el campo `o` no vacío) y la que separa lo que hay en tienda de
-- lo que solo se conserva como referencia.
CREATE OR REPLACE FUNCTION public.carga_catalogo(
  p_store text,
  p_token text,
  p_filas jsonb,
  p_by    text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int; n_inv int; n_corte int; n_cero int := 0; n_con_stock int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' OR jsonb_array_length(p_filas) = 0 THEN
    -- Un Excel que se parseó mal llega como lista vacía. Aceptarlo borraría el
    -- catálogo entero y dejaría el tablero en blanco, y el gerente vería
    -- "actualizado ✓". Se rechaza: mejor no subir nada que subir la nada.
    RETURN jsonb_build_object('ok', false, 'error', 'el archivo no trajo ninguna fila');
  END IF;

  CREATE TEMP TABLE _carga (
    sku text, descripcion text, upc text, precio numeric, onhand int
  ) ON COMMIT DROP;

  -- La subconsulta NO es adorno: `DISTINCT ON` no puede referirse a los alias de
  -- salida del propio SELECT —eso solo lo permite ORDER BY—, así que
  -- `DISTINCT ON (sku)` sobre columnas sin nombre falla con
  -- «42703: column "sku" does not exist». Pasó el 7-ago-2026 al subir el primer
  -- informe de verdad. Se nombran los campos dentro y se filtra fuera.
  INSERT INTO _carga (sku, descripcion, upc, precio, onhand)
  SELECT DISTINCT ON (sku) sku, descripcion, upc, precio, onhand
  FROM (
    SELECT trim(x->>'sku') AS sku,
           coalesce(x->>'desc','') AS descripcion,
           nullif(trim(coalesce(x->>'upc','')),'') AS upc,
           nullif(regexp_replace(coalesce(x->>'precio',''),'[^0-9.]','','g'),'')::numeric AS precio,
           -- `inventario.onhand` tiene CHECK (onhand >= 0). Un negativo en el
           -- Excel —pasa cuando el POS arrastra un ajuste— reventaría el INSERT
           -- y tumbaría la carga ENTERA, con el gerente delante y sin saber por
           -- qué. Un stock negativo no significa nada en piso: es cero.
           greatest(0, coalesce(nullif(regexp_replace(coalesce(x->>'onhand',''),'[^0-9-]','','g'),'')::int, 0)) AS onhand
    FROM jsonb_array_elements(p_filas) x
    WHERE trim(coalesce(x->>'sku','')) <> ''
  ) p
  -- Un mismo SKU puede venir en varias filas del Excel (varios UPC). Gana la
  -- que trae On Hand, y entre esas la de precio más alto: es el criterio que ya
  -- usaba `cargar_catalogo` y evita quedarse con una fila vacía por azar.
  ORDER BY sku, onhand DESC, precio DESC NULLS LAST;

  GET DIAGNOSTICS n = ROW_COUNT;

  -- Lo que ya no viene en el informe deja de ser vigente. NO se borra: los
  -- agotados siguen en el catálogo como referencia —el cliente los pide y se
  -- traen de otra tienda— y borrarlos los sacaría del buscador.
  -- El 4-ago esto estuvo mal en `cargar_catalogo` con un OR que impedía volver
  -- a false: un SKU marcado vigente lo era para siempre.
  UPDATE public.catalogo c SET vigente = false, updated_at = now()
   WHERE c.store_id = p_store AND c.vigente
     AND NOT EXISTS (SELECT 1 FROM _carga g WHERE g.sku = c.sku AND g.onhand <> 0);

  -- `subido_por` alimenta el "Por Fulano" de la pantalla de estado. Se le
  -- pasaba p_by y solo se devolvia en la respuesta: la columna se quedaba en
  -- NULL y esa linea decia siempre un guion. Encontrado el 7-ago al comprobar
  -- por que no se movia cat_at.
  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, precio, vigente, subido_por)
  SELECT p_store, g.sku, g.descripcion, g.upc, g.precio, (g.onhand <> 0),
         nullif(trim(coalesce(p_by,'')),'')
  FROM _carga g
  ON CONFLICT (store_id, sku) DO UPDATE
    SET descripcion = excluded.descripcion,
        upc         = coalesce(excluded.upc, public.catalogo.upc),
        precio      = coalesce(excluded.precio, public.catalogo.precio),
        vigente     = excluded.vigente,
        subido_por  = coalesce(excluded.subido_por, public.catalogo.subido_por),
        updated_at  = now();

  -- On Hand. La exhibición NO se toca aquí: tiene su propia carga y su propio
  -- corte, porque se sube en otro momento.
  INSERT INTO public.inventario (store_id, sku, onhand)
  SELECT p_store, g.sku, g.onhand FROM _carga g
  ON CONFLICT (store_id, sku) DO UPDATE
    SET onhand = excluded.onhand;

  /* ── Lo que YA NO viene en el archivo se pone en cero ──────
     5-sep-2026, encontrado en la tienda de origen: tres articulos agotados
     seguian ofreciendose con stock. El archivo es el ON HAND del dia; cuando
     un articulo se acaba, deja de venir. Hasta hoy esta carga solo tocaba los
     SKUs presentes, asi que al ausente le quedaba el numero del ultimo dia que
     aparecio — y `inventario_vivo` lo enseñaba igual, porque no mira si el
     catalogo sigue vigente. El asesor prometia una pieza que no existe.

     SOLO `onhand`. La columna `exhibicion` vive en esta misma tabla y se sube
     por separado y de higos a brevas (`carga_exhibicion`): tocarla aqui
     borraria el piso entero en cada carga diaria. Un articulo agotado en bodega
     que conserve su pieza de muestra tiene que seguir viendose —0 en stock, 1
     en piso—, que es justo lo que distingue `inventario_vivo`.

     LA SALVAGUARDA: si el archivo trae menos de la mitad de los SKUs que ya
     tienen existencia, no se pone nada en cero. Una carga completa que se acaba
     de subir no puede encoger a la mitad de un dia para otro; si encoge, lo que
     se subio fue un pedazo —una categoria, un archivo filtrado— y ponerle cero
     al resto vaciaria la tienda entera sin que nadie lo pidiera. Se avisa en la
     respuesta y no se toca nada. */
  SELECT count(*) INTO n_con_stock FROM public.inventario i
   WHERE i.store_id = p_store AND coalesce(i.onhand,0) > 0;

  IF n_con_stock > 0 AND (SELECT count(*) FROM _carga WHERE onhand > 0) * 2 < n_con_stock THEN
    n_cero := -1;   -- lo lee la app: archivo sospechosamente corto
  ELSE
    UPDATE public.inventario i SET onhand = 0
     WHERE i.store_id = p_store
       AND coalesce(i.onhand,0) <> 0
       AND NOT EXISTS (SELECT 1 FROM _carga g WHERE g.sku = i.sku);
    GET DIAGNOSTICS n_cero = ROW_COUNT;
  END IF;
  GET DIAGNOSTICS n_inv = ROW_COUNT;

  -- EL CORTE. Va aquí dentro, en la misma transacción que el On Hand: si se
  -- hiciera en otra llamada, una venta que entre en medio se contaría dos veces.
  -- El filtro de entregas de preventa es el MISMO que usa inventario_vivo.
  -- Solo ventas de BODEGA (17-ago-2026). Una venta marcada como pieza de
  -- exhibición no debe entrar aquí: si entrara, el corte de On Hand quedaría
  -- alto y la siguiente venta de bodega no descontaría stock. Ver
  -- `supabase_venta_exhibicion.sql`.
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'onhand', g.sku, public.corte_tomar_(p_store, 'onhand', g.sku)
  FROM _carga g
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();
  GET DIAGNOSTICS n_corte = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'skus', n, 'inventario', n_inv,
                            'corte', n_corte, 'by', coalesce(p_by,''),
                            -- -1 = no se puso nada en cero porque el archivo
                            -- venia demasiado corto. La app lo enseña.
                            'agotados', n_cero);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 2 · Exhibición + su corte  ←  tipo:'exhibicion' ─────────
-- p_filas: [{sku, exhibe}, ...]
CREATE OR REPLACE FUNCTION public.carga_exhibicion(
  p_store text,
  p_token text,
  p_filas jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  /* Que las filas traigan el campo que esta funcion lee (2-sep-2026).

     El campo se llama `exhibe`. Una carga que lo mande con otro nombre —pasó
     llamándolo `exhibicion`— entra por el coalesce de abajo como CERO en todo,
     y esto respondía `ok: true, skus: 4`: cuatro SKUs guardados con cero
     piezas en el aparador. O sea que decía que sí y dejaba el piso vacío.

     Se RECHAZA en vez de avisar: si ninguna fila trae el campo, esta carga no
     puede hacer nada útil, y lo que sí puede hacer es borrar la exhibición que
     ya estaba puesta.

     Una carga legítima que quiera vaciar el aparador manda `exhibe: 0`, que sí
     trae la clave y pasa. La diferencia entre «ponlo en cero» y «no sé de qué
     me hablas» tiene que notarse. */
  IF jsonb_array_length(p_filas) > 0 AND NOT EXISTS (
       SELECT 1 FROM jsonb_array_elements(p_filas) x WHERE x ? 'exhibe') THEN
    RETURN jsonb_build_object(
      'ok', false,
      'error', 'ninguna fila trae el campo `exhibe`: se guardarían ceros y se '
               'borraría la exhibición que ya está puesta');
  END IF;

  CREATE TEMP TABLE _exh (sku text PRIMARY KEY, exhibe int) ON COMMIT DROP;
  INSERT INTO _exh (sku, exhibe)
  SELECT DISTINCT ON (trim(x->>'sku'))
         trim(x->>'sku'),
         coalesce(nullif(regexp_replace(coalesce(x->>'exhibe',''),'[^0-9-]','','g'),'')::int, 0)
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'sku','')) <> '';

  -- Lo que no viene en la subida de piso queda en cero: es una foto completa
  -- del piso, no un parche. Un SKU que se retiró de exhibición y no se pusiera
  -- a cero seguiría contando como pieza de muestra para siempre.
  UPDATE public.inventario i SET exhibicion = 0
   WHERE i.store_id = p_store AND coalesce(i.exhibicion,0) <> 0
     AND NOT EXISTS (SELECT 1 FROM _exh e WHERE e.sku = i.sku);

  INSERT INTO public.inventario (store_id, sku, exhibicion)
  SELECT p_store, e.sku, e.exhibe FROM _exh e
  ON CONFLICT (store_id, sku) DO UPDATE SET exhibicion = excluded.exhibicion;
  GET DIAGNOSTICS n = ROW_COUNT;

  -- Corte PROPIO, independiente del de On Hand. Ver la cabecera.
  -- Y solo con las ventas DE EXHIBICIÓN (17-ago-2026): si contara todas, el
  -- corte quedaría siempre por encima de las marcadas y el aparador no bajaría
  -- nunca — la marca no serviría de nada, sin dar ningún error.
  INSERT INTO public.inventario_corte (store_id, tipo, sku, vendidas)
  SELECT p_store, 'exhibicion', e.sku, public.corte_tomar_(p_store, 'exhibicion', e.sku)
  FROM _exh e
  ON CONFLICT (store_id, tipo, sku) DO UPDATE
    SET vendidas = excluded.vendidas, tomado_en = now();

  RETURN jsonb_build_object('ok', true, 'skus', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · Catálogo de referencia  ←  tipo:'catalogo_ref' ──────
-- Los agotados que el cliente sigue pidiendo y se traen de otra tienda. Entran
-- como NO vigentes y sin tocar el precio de los que ya están: este archivo no
-- trae precios, y escribir NULL encima borraría el último precio conocido.
CREATE OR REPLACE FUNCTION public.carga_catalogo_ref(
  p_store text,
  p_token text,
  p_filas jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  INSERT INTO public.catalogo (store_id, sku, descripcion, upc, vigente)
  SELECT DISTINCT ON (trim(x->>'sku'))
         p_store, trim(x->>'sku'), coalesce(x->>'desc',''),
         nullif(trim(coalesce(x->>'upc','')),''), false
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'sku','')) <> ''
  ON CONFLICT (store_id, sku) DO UPDATE
    SET descripcion = excluded.descripcion,
        upc         = coalesce(excluded.upc, public.catalogo.upc),
        -- vigente NO se toca: si ese SKU sí está en el informe del día, es
        -- vigente, y este archivo no sabe nada de eso.
        updated_at  = now();
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'skus', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Promos  ←  tipo:'promos' ────────────────────────────
-- MEZCLA, no reemplaza: `actualizarPromos_` conserva las promos anteriores y
-- encima pone las del CEA nuevo. Un CEA trae solo las promos de esa quincena, y
-- reemplazar borraría las que siguen vigentes de la anterior.
--
-- LA TABLA TIENE DOS CANDADOS QUE LA HOJA NO TENÍA, y cualquiera de los dos
-- tumba la carga entera si se le manda una fila que no cumple:
--
--   · `vigente_hasta` es NOT NULL — sin fecha no hay promo
--   · CHECK (precio_pro < precio_reg)
--
-- En la hoja esas filas entraban sin más y luego no se veían. Aquí reventarían
-- el INSERT completo y el gerente vería "no se pudo subir" sin saber que fue por
-- una fila de 117. Así que se APARTAN y se CUENTAN: las buenas entran, y la
-- respuesta dice cuántas se quedaron fuera y por qué. Descartarlas en silencio
-- sería peor — una promo que no aparece es un precio que el asesor no cobra.
CREATE OR REPLACE FUNCTION public.carga_promos(
  p_store text,
  p_token text,
  p_filas jsonb,
  p_by    text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int; sin_fecha int; precio_malo int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin filas');
  END IF;

  CREATE TEMP TABLE _pro ON COMMIT DROP AS
  SELECT DISTINCT ON (sku) * FROM (
    SELECT trim(x->>'sku') AS sku,
           coalesce(x->>'desc','') AS producto,
           nullif(regexp_replace(coalesce(x->>'pr',''),'[^0-9.]','','g'),'')::numeric AS precio_reg,
           nullif(regexp_replace(coalesce(x->>'pp',''),'[^0-9.]','','g'),'')::numeric AS precio_pro,
           nullif(trim(coalesce(x->>'est','')),'') AS estatus,
           nullif(trim(coalesce(x->>'msi','')),'') AS msi,
           nullif(trim(coalesce(x->>'d1','')),'')::date AS vigente_desde,
           nullif(trim(coalesce(x->>'d2','')),'')::date AS vigente_hasta
    FROM jsonb_array_elements(p_filas) x
    WHERE trim(coalesce(x->>'sku','')) <> ''
  ) p ORDER BY sku, vigente_hasta DESC NULLS LAST;

  SELECT count(*) INTO sin_fecha   FROM _pro WHERE vigente_hasta IS NULL;
  SELECT count(*) INTO precio_malo FROM _pro
   WHERE vigente_hasta IS NOT NULL
     AND precio_pro IS NOT NULL AND precio_reg IS NOT NULL
     AND precio_pro >= precio_reg;

  INSERT INTO public.promos (store_id, sku, producto, precio_reg, precio_pro,
                             estatus, msi, vigente_desde, vigente_hasta, subido_por)
  SELECT p_store, sku, producto, precio_reg, precio_pro,
         estatus, msi, vigente_desde, vigente_hasta,
         nullif(trim(coalesce(p_by,'')),'')
  FROM _pro
  WHERE vigente_hasta IS NOT NULL
    AND (precio_pro IS NULL OR precio_reg IS NULL OR precio_pro < precio_reg)
    -- la vigencia al revés también tiene CHECK
    AND (vigente_desde IS NULL OR vigente_desde <= vigente_hasta)
  ON CONFLICT (store_id, sku) DO UPDATE
    SET producto      = excluded.producto,
        precio_reg    = excluded.precio_reg,
        precio_pro    = excluded.precio_pro,
        estatus       = excluded.estatus,
        msi           = excluded.msi,
        vigente_desde = excluded.vigente_desde,
        vigente_hasta = excluded.vigente_hasta,
        subido_por    = coalesce(excluded.subido_por, public.promos.subido_por),
        updated_at    = now();
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'promos', n,
                            'sin_fecha', sin_fecha, 'precio_invalido', precio_malo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Comisiones  ←  tipo:'comisiones' ────────────────────
-- Esta SÍ reemplaza: el reporte trae el mes completo cada vez.
--
-- `alcance` y `gar_pct` PUEDEN pasar de 100 y no se recortan. Hay una ventana de
-- 30 días para comprar el seguro, así que un vendedor puede cerrar por encima
-- del 100 %. Un LEAST(...,100) "para que se vea bien" borraría trabajo hecho.
CREATE OR REPLACE FUNCTION public.carga_comisiones(
  p_store   text,
  p_token   text,
  p_filas   jsonb,
  p_periodo text DEFAULT NULL,
  -- El periodo de garantías es OTRO campo y otra ventana de fechas: lo pinta
  -- comisiones.html (l. 132). Sin él esa pantalla muestra un guion, y el equipo
  -- no sabe a qué semana corresponde su attach.
  p_periodo_gar text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_filas IS NULL OR jsonb_typeof(p_filas) <> 'array' OR jsonb_array_length(p_filas) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el reporte no trajo ninguna fila');
  END IF;

  DELETE FROM public.comisiones WHERE store_id = p_store;

  INSERT INTO public.comisiones (store_id, empno, nombre, puesto, venta, ppto_pct,
                                 alcance, gar_pct, gar_pzas, gar_elegible, gar_monto,
                                 periodo, periodo_gar)
  SELECT p_store,
         nullif(trim(coalesce(x->>'empNo','')),''),
         trim(coalesce(x->>'nombre','')),
         nullif(trim(coalesce(x->>'puesto','')),''),
         coalesce(nullif(regexp_replace(coalesce(x->>'venta',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'pptoPct',''),'[^0-9.]','','g'),'')::numeric, 0),
         coalesce(nullif(regexp_replace(coalesce(x->>'alcance',''),'[^0-9.]','','g'),'')::numeric, 0),
         nullif(regexp_replace(coalesce(x->>'garantiaPct',''),'[^0-9.]','','g'),'')::numeric,
         nullif(regexp_replace(coalesce(x->>'garantiaPzas',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'garantiaElegible',''),'[^0-9.]','','g'),'')::int,
         nullif(regexp_replace(coalesce(x->>'garantiaMonto',''),'[^0-9.]','','g'),'')::numeric,
         nullif(trim(coalesce(p_periodo,'')),''),
         nullif(trim(coalesce(p_periodo_gar,'')),'')
  FROM jsonb_array_elements(p_filas) x
  WHERE trim(coalesce(x->>'nombre','')) <> '';
  GET DIAGNOSTICS n = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'empleados', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.carga_catalogo(text,text,jsonb,text)   FROM public;
REVOKE ALL ON FUNCTION public.carga_exhibicion(text,text,jsonb)      FROM public;
REVOKE ALL ON FUNCTION public.carga_catalogo_ref(text,text,jsonb)    FROM public;
REVOKE ALL ON FUNCTION public.carga_promos(text,text,jsonb,text)          FROM public;
REVOKE ALL ON FUNCTION public.carga_comisiones(text,text,jsonb,text,text) FROM public;

GRANT EXECUTE ON FUNCTION public.carga_catalogo(text,text,jsonb,text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_exhibicion(text,text,jsonb)      TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_catalogo_ref(text,text,jsonb)    TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_promos(text,text,jsonb,text)          TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.carga_comisiones(text,text,jsonb,text,text) TO anon, authenticated;


-- ── 7 · resincronizar() deja de poder pisar lo nuevo ────────
-- ESTE PASO ES OBLIGATORIO, y es el más peligroso del archivo si se salta.
--
-- `resincronizar()` trae de la HOJA el catálogo, el inventario, los cortes, las
-- promos y las comisiones. Desde hoy la hoja ya no recibe ninguna de esas
-- cargas, así que correrlo reemplazaría los datos buenos por una foto vieja —el
-- catálogo entero, 227 filas— y terminaría diciendo "los seis pasos en verde".
--
-- Es el mismo caso que `cargar_apartados_comisiones` el 7-ago, pero sobre el
-- inventario. Se desactiva entera en vez de borrarla: si alguien la llama por
-- costumbre, tiene que enterarse de que ya no debe.
CREATE OR REPLACE FUNCTION public.resincronizar(p_store text)
RETURNS TABLE (paso int, que text, resultado text)
LANGUAGE plpgsql AS $fn$
BEGIN
  paso := 1;
  que  := 'resincronizar';
  resultado := 'DESACTIVADA (7-ago-2026). La hoja ya no recibe cargas: '
            || 'catalogo, inventario, promos y comisiones se suben directo a '
            || 'Supabase desde Admin. Correr esto reemplazaria los datos buenos '
            || 'por la ultima foto de la hoja. Ver supabase_cargas_admin.sql.';
  RETURN NEXT;
END $fn$;


-- ============================================================
--  COMPROBAR — hacerlo, y en este orden
-- ============================================================
--
--  1) Sin token no se carga nada:
--       select public.carga_catalogo('1217','', '[{"sku":"1","desc":"x"}]'::jsonb);
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Un archivo vacío se RECHAZA (si se aceptara, borraría el catálogo):
--       select public.carga_catalogo('1217','<TOKEN>', '[]'::jsonb);
--     -> {"ok": false, "error": "el archivo no trajo ninguna fila"}
--
--  3) resincronizar ya no hace nada:
--       select * from public.resincronizar('1217');
--     -> un solo renglon que dice DESACTIVADA
--
--  4) LA PRUEBA DE VERDAD, y no se salta: subir el informe del día desde
--     actualizar_datos.html y comprobar que el inventario NO cambió de forma
--     rara. Antes de subirlo:
--
--       CREATE TEMP TABLE inv_antes AS SELECT * FROM public.inventario_vivo('1217');
--
--     Después de subirlo, en la MISMA pestaña del editor:
--
--       SELECT a.sku, a.onhand AS antes, b.onhand AS ahora,
--              a.stock AS stock_antes, b.stock AS stock_ahora
--         FROM inv_antes a JOIN public.inventario_vivo('1217') b USING (sku)
--        WHERE a.onhand <> b.onhand OR a.stock <> b.stock
--        ORDER BY abs(a.stock - b.stock) DESC LIMIT 20;
--
--     Lo que se espera: cambios que se expliquen por las ventas del día y por
--     la mercancía que entró. Lo que NO se espera: que el stock se vaya a cero
--     en muchos SKU a la vez, o que salten SKUs que no se movieron. Si sale
--     algo así, el corte se tomó mal — parar y avisar.
-- ============================================================


-- ========== supabase_escrituras_resto.sql ==========

-- ============================================================
--  ESCRITURAS QUE FALTABAN — EOL, avisos, combos y borrar venta
--  Etapa 2 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql: usa su guardia `escritura_ok_`.
--  Correr ESE primero.
--
--  ------------------------------------------------------------
--  LO QUE ESTE ARCHIVO ARREGLA, Y NO ES UNA MEJORA: ES UNA FUGA
--  ------------------------------------------------------------
--  Borrar una captura en Captura de Series avisa al Apps Script
--  (`gasEnviar({tipo:'eliminar'})`, captura_series.html l. 806) y **no le dice
--  nada a Supabase**. La venta desaparece de la hoja y se queda en la tabla.
--
--  Eso importa porque desde la fase 2 el tablero lee `inventario_vivo`, que
--  descuenta lo vendido de la tabla `ventas` DE SUPABASE. Una venta borrada en
--  la hoja sigue descontando pieza en el tablero: **el tablero muestra menos
--  stock del que hay en bodega**, para siempre, en ese SKU. Nadie recibe un
--  error; solo se ve un producto agotado que sí está.
--
--  Es el reverso exacto del incidente del 4-ago —cuando el tablero mostraba una
--  pieza de MÁS por cada venta del día— y por la misma causa de fondo: leer de
--  un lado lo que se escribe en el otro. La doble escritura cerró el alta; el
--  borrado se quedó fuera.
--
--  Para poder borrar hace falta saber QUÉ fila borrar, y ahí estaba el hueco:
--  la app identifica cada captura con su `id` propio ('i' + timestamp) y la
--  tabla `ventas` no lo guardaba. Por eso el paso 1 es una columna nueva.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · El enlace entre la captura y la fila ────────────────
-- `captura_id` es el id que genera Captura de Series. Es lo único que permite
-- volver a encontrar la venta para borrarla: la serie no basta —una devolución
-- puede repetirla otro día— y la fecha tampoco.
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS captura_id text;

-- Parcial: las ventas históricas cargadas de la hoja no traen captura_id y no
-- deben chocar entre sí por ser todas NULL.
CREATE UNIQUE INDEX IF NOT EXISTS ventas_captura_unica
  ON public.ventas (store_id, captura_id)
  WHERE captura_id IS NOT NULL;


-- ── 2 · venta_guardar, ahora con captura_id ─────────────────
-- El parámetro va AL FINAL y con DEFAULT: PostgREST resuelve por nombre, así
-- que una app vieja que no lo mande sigue funcionando igual. Sin esa
-- precaución, publicar esto rompería la captura de todos los celulares que aún
-- no se hayan actualizado.
--
-- ⚠️ EL DROP DE ABAJO NO ES OPCIONAL, y esto se aprendió rompiéndolo.
--
-- `CREATE OR REPLACE` solo reemplaza si la lista de parámetros es IDÉNTICA. Al
-- agregar uno, Postgres no sustituye: crea una SEGUNDA función con el mismo
-- nombre. Y entonces PostgREST recibe una llamada de diez parámetros, ve dos
-- candidatas y responde PGRST203 «could not choose the best candidate» — o sea
-- que la captura deja de guardar en Supabase para TODOS los celulares que aún
-- no se actualizaron, que son justo los que este DEFAULT venía a proteger.
--
-- Pasó de verdad el 7-ago-2026, entre que se aplicó este archivo y que se
-- comprobó. Las ventas no se perdieron —la cola de Captura de Series las
-- retuvo y las reintentó— pero durante ese rato el inventario de Supabase se
-- quedó atrás, que es lo que infla el stock del tablero.
--
-- Regla: si cambia la firma, DROP explícito de la firma vieja. Siempre.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,   -- '4/8/2026'  (d/M/yyyy, como la hoja)
  p_hora       text    DEFAULT NULL,   -- '01:26 p.m.'
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL    -- el id de la app, para poder borrarla
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- fecha: d/M/yyyy. Sin fecha reconocible se usa ahora, que es mejor que
  -- rechazar la venta: el dato existe y ya está en el Sheet.
  m := regexp_match(coalesce(p_fecha,''), '^(\d{1,2})/(\d{1,2})/(\d{4})$');
  IF m IS NULL THEN
    v_cuando := now();
  ELSE
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    -- hora: '1:26 p.m.' / '13:26'. Sin hora usable, mediodía: no se pasa de día
    -- en ninguna zona.
    m := regexp_match(lower(coalesce(p_hora,'')), '(\d{1,2}):(\d{2})\s*([ap])?');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF m[3] = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF m[3] = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := (format('%s-%s-%s %s:%s', v_a, lpad(v_m::text,2,'0'), lpad(v_d::text,2,'0'),
                        lpad(v_h::text,2,'0'), lpad(v_min::text,2,'0'))::timestamp)
                AT TIME ZONE 'America/Mexico_City';
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id)
  VALUES
    (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
     nullif(trim(coalesce(p_desc,'')),''), p_precio,
     nullif(trim(coalesce(p_vendedor,'')),''), p_seguro,
     nullif(trim(coalesce(p_foto_url,'')),''),
     nullif(trim(coalesce(p_captura_id,'')),''))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  WHEN unique_violation THEN
    -- ya estaba: reintento de red, no un problema
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

GRANT EXECUTE ON FUNCTION
  public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text)
  TO anon, authenticated;


-- ── 3 · Borrar una venta  ←  reemplaza tipo:'eliminar' ──────
-- Borra de verdad, no marca. Es lo mismo que hace la hoja al quitar la fila, y
-- el inventario tiene que volver a contar esa pieza como disponible.
CREATE OR REPLACE FUNCTION public.venta_eliminar(
  p_store      text,
  p_token      text,
  p_captura_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id');
  END IF;

  -- Una venta ligada a un apartado entregado NO se borra por aquí: el equipo
  -- salió de la tienda y el apartado seguiría apuntando a una fila que ya no
  -- existe. Se cancela desde la preventa, que sabe deshacer las dos cosas.
  IF EXISTS (SELECT 1 FROM public.apartados a
              JOIN public.ventas v ON v.id = a.venta_id
             WHERE v.store_id = p_store AND v.captura_id = trim(p_captura_id)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta es la entrega de un apartado: deshazla desde Preventa');
  END IF;

  DELETE FROM public.ventas
   WHERE store_id = p_store AND captura_id = trim(p_captura_id);
  GET DIAGNOSTICS n = ROW_COUNT;

  -- Cero borradas NO es un error: la captura pudo no haber llegado nunca
  -- (quedó en la cola y se borró antes de subir). Se responde ok y se dice
  -- cuántas, para que la app no invente un fallo que no existe.
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · EOL  ←  reemplaza eol_add / eol_del ─────────────────
-- La hoja guarda una tercera columna 'si'/'no' que la lectura usa para filtrar;
-- aquí eso es `pausado`, al revés. 'si' (activo) = pausado false.
--
-- Si no llega precio, se busca en el catálogo: es lo que hace `agregarEol_` en
-- el Apps Script recorriendo la hoja Catalogo. Sin esa búsqueda, el EOL entra
-- con precio vacío y `eol_precio_venta` no puede calcular el 50 % — o sea, el
-- producto aparece marcado pero sin precio de venta, que es peor que no estar.
CREATE OR REPLACE FUNCTION public.eol_guardar(
  p_store  text,
  p_token  text,
  p_sku    text,
  p_precio numeric DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_precio numeric;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;

  -- Ya estaba: se responde `existe` y NO se toca. Es lo que hace `agregarEol_`
  -- en el Apps Script, y Admin lo muestra como "Ya existe este SKU". Cambiarlo
  -- por un upsert silencioso pisaría el precio que alguien puso a mano sin que
  -- se viera, y el precio del EOL es lo que decide cuánto se cobra en piso.
  IF EXISTS (SELECT 1 FROM public.eol e
              WHERE e.store_id = p_store AND e.sku = trim(p_sku)) THEN
    RETURN jsonb_build_object('ok', true, 'existe', true, 'sku', trim(p_sku));
  END IF;

  v_precio := p_precio;
  IF v_precio IS NULL THEN
    SELECT c.precio INTO v_precio FROM public.catalogo c
     WHERE c.store_id = p_store AND c.sku = trim(p_sku);
  END IF;

  INSERT INTO public.eol (store_id, sku, precio, pausado)
  VALUES (p_store, trim(p_sku), v_precio, false);

  RETURN jsonb_build_object('ok', true, 'sku', trim(p_sku), 'precio', v_precio);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.eol_eliminar(
  p_store text,
  p_token text,
  p_sku   text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.eol WHERE store_id = p_store AND sku = trim(coalesce(p_sku,''));
  GET DIAGNOSTICS n = ROW_COUNT;
  -- Igual que en la hoja: quitar algo que no estaba no es un fallo.
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Avisos  ←  reemplaza aviso_add / aviso_del ──────────
-- Sin fecha de fin, siete días: es lo que hace `guardarAviso_`. Un aviso sin
-- caducidad se queda en la pantalla de todos hasta que alguien se acuerda de
-- borrarlo, y nadie se acuerda.
--
-- LA COLUMNA `tipo` FALTABA, y no es cosmética: el tablero la pinta como
-- etiqueta azul (cardAviso, tablero.html l. 1354) para distinguir un CEA/LEA
-- oficial de un recado interno. La hoja la guardaba (columna 7) y
-- `leerAvisos_` la devolvía; el esquema de Supabase se quedó sin ella.
--
-- O sea que esto ya estaba roto ANTES de esta etapa: desde que las lecturas se
-- movieron a Supabase (fase 2), `_deSupabase` no tenía de dónde sacarla y
-- ponía 'manual' fijo. Los avisos oficiales llevan desde entonces sin su
-- etiqueta. Nadie lo reportó porque un aviso sin distintivo se sigue leyendo
-- igual — solo pierde la señal de que viene de corporativo.
ALTER TABLE public.avisos
  ADD COLUMN IF NOT EXISTS tipo text NOT NULL DEFAULT 'manual';

-- La lectura tiene que devolverla, o la columna nueva no llega a nadie.
DROP FUNCTION IF EXISTS public.avisos_vigentes(text);

CREATE FUNCTION public.avisos_vigentes(p_store text)
RETURNS TABLE (id bigint, titulo text, detalle text, prioridad text,
               vigente_hasta date, creado_en timestamptz, tipo text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.titulo, a.detalle, a.prioridad, a.vigente_hasta, a.creado_en, a.tipo
  FROM public.avisos a
  WHERE a.store_id = p_store
    AND (a.vigente_hasta IS NULL
         OR a.vigente_hasta >= (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY a.creado_en DESC;
$$;

REVOKE ALL ON FUNCTION public.avisos_vigentes(text) FROM public;
GRANT EXECUTE ON FUNCTION public.avisos_vigentes(text) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.aviso_guardar(
  p_store     text,
  p_token     text,
  p_titulo    text,
  p_detalle   text DEFAULT NULL,
  p_prioridad text DEFAULT 'normal',
  p_hasta     date DEFAULT NULL,
  p_tipo      text DEFAULT 'manual'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_titulo),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin titulo');
  END IF;

  INSERT INTO public.avisos (store_id, titulo, detalle, prioridad, vigente_hasta, tipo)
  VALUES (p_store, trim(p_titulo), nullif(trim(coalesce(p_detalle,'')),''),
          coalesce(nullif(trim(coalesce(p_prioridad,'')),''), 'normal'),
          coalesce(p_hasta, ((now() AT TIME ZONE 'America/Mexico_City')::date + 7)),
          coalesce(nullif(trim(coalesce(p_tipo,'')),''), 'manual'))
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.aviso_eliminar(
  p_store text,
  p_token text,
  p_id    bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.avisos WHERE store_id = p_store AND id = p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no encontrado');
  END IF;
  RETURN jsonb_build_object('ok', true);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Combos  ←  bundle_add / bundle_del / bundle_clear ───
-- Los combos están retirados de la vista desde julio (ver MAPA, l. 440), pero
-- las escrituras se reponen igual: si se retiran del plan, el día que vuelvan
-- habrá que reconstruirlas con el Apps Script ya apagado, y ahí ya no habrá de
-- dónde copiar la lógica.
--
-- `skus` es un array de verdad en Supabase y "a,b,c" en la hoja. La conversión
-- se hace AQUÍ y no en el cliente, para que solo exista en un sitio.
CREATE OR REPLACE FUNCTION public.bundle_guardar(
  p_store  text,
  p_token  text,
  p_nombre text,
  p_skus   text,            -- "a,b,c" como lo manda admin.html
  p_precio numeric,
  p_desde  date DEFAULT NULL,
  p_hasta  date DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint; v_skus text[];
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_nombre),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin nombre');
  END IF;

  SELECT array_agg(s) INTO v_skus
    FROM (SELECT trim(x) AS s
            FROM unnest(string_to_array(coalesce(p_skus,''), ',')) x
           WHERE trim(x) <> '') t;
  IF v_skus IS NULL OR array_length(v_skus,1) IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin skus');
  END IF;

  INSERT INTO public.bundles (store_id, nombre, skus, precio, vigente_desde, vigente_hasta, activo)
  VALUES (p_store, trim(p_nombre), v_skus, p_precio, p_desde,
          -- vigente_hasta es NOT NULL en el esquema; sin fecha, 30 días
          coalesce(p_hasta, ((now() AT TIME ZONE 'America/Mexico_City')::date + 30)), true)
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.bundle_eliminar(
  p_store text,
  p_token text,
  p_id    bigint
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.bundles WHERE store_id = p_store AND id = p_id;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', n > 0, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

CREATE OR REPLACE FUNCTION public.bundle_limpiar(
  p_store text,
  p_token text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE n int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  DELETE FROM public.bundles WHERE store_id = p_store;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('ok', true, 'borradas', n);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 7 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.venta_eliminar(text,text,text)                   FROM public;
REVOKE ALL ON FUNCTION public.eol_guardar(text,text,text,numeric)              FROM public;
REVOKE ALL ON FUNCTION public.eol_eliminar(text,text,text)                     FROM public;
REVOKE ALL ON FUNCTION public.aviso_guardar(text,text,text,text,text,date,text) FROM public;
REVOKE ALL ON FUNCTION public.aviso_eliminar(text,text,bigint)                 FROM public;
REVOKE ALL ON FUNCTION public.bundle_guardar(text,text,text,text,numeric,date,date) FROM public;
REVOKE ALL ON FUNCTION public.bundle_eliminar(text,text,bigint)                FROM public;
REVOKE ALL ON FUNCTION public.bundle_limpiar(text,text)                        FROM public;

GRANT EXECUTE ON FUNCTION public.venta_eliminar(text,text,text)                   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_guardar(text,text,text,numeric)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.eol_eliminar(text,text,text)                     TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aviso_guardar(text,text,text,text,text,date,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.aviso_eliminar(text,text,bigint)                 TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_guardar(text,text,text,text,numeric,date,date) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_eliminar(text,text,bigint)                TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.bundle_limpiar(text,text)                        TO anon, authenticated;


-- ============================================================
--  COMPROBAR ANTES DE CONECTAR LAS APPS
-- ============================================================
--
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) La columna nueva no rompió la captura. Una venta SIN captura_id, como
--     las que manda la app vieja, tiene que seguir entrando:
--       select public.venta_guardar('1217','PRUEBA-E2-1','100304280','prueba',
--                                   999,'prueba',true,null,null);
--     -> {"ok": true, "id": ...}
--
--  2) Y una CON captura_id:
--       select public.venta_guardar('1217','PRUEBA-E2-2','100304280','prueba',
--                                   999,'prueba',true,null,null,null,'iPRUEBA1');
--     -> {"ok": true, "id": ...}
--
--  3) Borrarla por su id de captura:
--       select public.venta_eliminar('1217','<TOKEN>','iPRUEBA1');
--     -> {"ok": true, "borradas": 1}
--
--  4) Borrar algo que no existe NO es un error (la captura pudo no haber
--     subido nunca):
--       select public.venta_eliminar('1217','<TOKEN>','iNOEXISTE');
--     -> {"ok": true, "borradas": 0}
--
--  5) Sin token no se borra nada:
--       select public.venta_eliminar('1217','','iPRUEBA1');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  6) EOL sin precio lo saca del catálogo:
--       select public.eol_guardar('1217','<TOKEN>','100304280');
--     -> "precio" NO puede venir null si ese SKU tiene precio en catalogo
--       select public.eol_eliminar('1217','<TOKEN>','100304280');
--
--  7) Limpiar las pruebas:
--       delete from public.ventas where serie like 'PRUEBA-E2-%';
-- ============================================================


-- ========== supabase_fotos_venta.sql ==========

-- ============================================================
--  FOTOS DE VENTA — de Google Drive a la base
--  Etapa 4 de "apagar la hoja"
--  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`).
--
--  ------------------------------------------------------------
--  POR QUÉ ESTO NO ES SOLO "MOVER LAS FOTOS DE SITIO"
--  ------------------------------------------------------------
--  Antes de tocar nada se miró quién las usa, y la respuesta fue: NADIE. Ninguna
--  pantalla las muestra —`ventas_detalle` ni siquiera devolvía el campo— y la
--  única forma de ver una era abrir la hoja de cálculo y pinchar el enlace de
--  Drive. Encima `venta_guardar` aceptaba `p_foto_url` y el cliente nunca se lo
--  mandaba: las ventas que ya están en Supabase no tienen foto ninguna.
--
--  O sea que se estaban sacando, comprimiendo y subiendo fotos que se borraban
--  a los 7 días sin que nadie las hubiera visto.
--
--  Para lo que sirven —confirmado con Ángel el 7-ago— es para **verificar una
--  serie dudosa**: cuando un número no cuadra o hay un reclamo, poder mirar la
--  foto de esa caja. Así que además de guardarlas hay que poder ABRIRLAS desde
--  el panel de Ventas del día. Guardarlas mejor y que siguieran sin verse habría
--  sido trabajo para nada.
--
--  ------------------------------------------------------------
--  POR QUÉ EN LA BASE Y NO EN STORAGE
--  ------------------------------------------------------------
--  Storage es lo canónico para archivos, pero subir desde el celular obliga a
--  abrir el bucket a la anon key, que está en el HTML y es pública: cualquiera
--  que la lea podría subir archivos hasta llenarlo. Cerrar eso bien pide una
--  Edge Function, que es justo lo que se dejó para el final.
--
--  Aquí la foto entra por una RPC con el MISMO token de tienda que protege todo
--  lo demás. Sobre el tamaño: a ~10 ventas al día y ~150 KB por foto, los 31
--  días de retención salen a unos 46 MB. Con 7 días eran 10 MB.
--
--  RETENCIÓN: 31 DÍAS (24-ago-2026). Eran 7, y 7 es lo que dura una serie
--  dudosa: se reclama en caliente o no se reclama. Pero la misma tabla guarda
--  desde el 18-ago los tickets de accesorio y ahora los de reparación, que son
--  la evidencia de un CORTE MENSUAL, y con 7 días los de la primera semana ya
--  no existían al cotejarlo. Una evidencia que caduca antes de que llegue el
--  momento de usarla no es evidencia.
--
--  ⚠️ 31 días cubren el mes EN CURSO, no el anterior. Un ticket del 1 de mes
--  mirado el 10 del siguiente ya no está. Es una decisión tomada —el cotejo se
--  hace dentro del mes—, no un descuido: si algún día hay que revisar un mes
--  cerrado, esto es lo primero que hay que subir.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · La tabla ────────────────────────────────────────────
-- Aparte de `ventas` a propósito: esa tabla se consulta en cada carga del
-- tablero, y arrastrar un bytea de 150 KB por fila en cada `SELECT *` la
-- volvería lenta para todos. Aquí la foto solo se toca cuando alguien la pide.
--
-- Se liga por `captura_id`, el id que genera Captura de Series, y NO por el id
-- de la venta: la foto se sube en el mismo momento que la venta y no hay forma
-- de saber el id que le tocó sin una segunda consulta.
CREATE TABLE IF NOT EXISTS public.venta_fotos (
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  captura_id text        NOT NULL,
  imagen     bytea       NOT NULL,
  mime       text        NOT NULL DEFAULT 'image/jpeg',
  bytes      integer     NOT NULL,
  creada_en  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (store_id, captura_id)
);

ALTER TABLE public.venta_fotos ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS venta_fotos_edad ON public.venta_fotos (store_id, creada_en);

COMMENT ON TABLE public.venta_fotos IS
  'Fotos de captura, 7 dias de retencion. Sirven para verificar una serie '
  'dudosa. Se borran solas: cada guardado limpia las viejas.';


-- ── 2 · Guardar  ←  reemplaza guardarFoto_ (Drive) ──────────
-- La imagen llega en base64 SIN el prefijo `data:image/jpeg;base64,`. El cliente
-- lo quita antes: mandarlo entero haría que `decode` guardara basura al
-- principio del JPEG y la foto no abriría — y eso solo se descubre el día que
-- alguien intenta mirarla, que es justo el día que importa.
CREATE OR REPLACE FUNCTION public.venta_foto_guardar(
  p_store      text,
  p_token      text,
  p_captura_id text,
  p_imagen_b64 text,
  p_mime       text DEFAULT 'image/jpeg'
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE datos bytea; n int; viejas int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id de captura');
  END IF;
  IF coalesce(p_imagen_b64,'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin imagen');
  END IF;

  BEGIN
    datos := decode(p_imagen_b64, 'base64');
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la imagen no es base64 valido');
  END;

  n := octet_length(datos);
  -- Tope de 1,5 MB. El cliente comprime a ~150 KB, así que esto no estorba a una
  -- foto normal: está para que la anon key no pueda usarse para llenar la base
  -- subiendo archivos grandes.
  IF n > 1572864 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la imagen pesa mas de 1.5 MB');
  END IF;

  INSERT INTO public.venta_fotos (store_id, captura_id, imagen, mime, bytes)
  VALUES (p_store, trim(p_captura_id), datos,
          coalesce(nullif(trim(p_mime),''), 'image/jpeg'), n)
  ON CONFLICT (store_id, captura_id) DO UPDATE
    SET imagen = excluded.imagen, mime = excluded.mime,
        bytes = excluded.bytes, creada_en = now();

  -- Limpieza oportunista: las de más de 7 días se van con cada foto nueva.
  -- Se hace aquí y no con un cron a propósito: un trabajo programado es una
  -- pieza más que puede estar apagada sin que nadie lo note, y esto se ejecuta
  -- justo cuando hay algo que limpiar. Si un día dejan de subirse fotos, las
  -- últimas se quedan — 10 MB parados, que no molestan a nadie.
  DELETE FROM public.venta_fotos
   WHERE store_id = p_store AND creada_en < now() - interval '31 days';
  GET DIAGNOSTICS viejas = ROW_COUNT;

  RETURN jsonb_build_object('ok', true, 'bytes', n, 'borradas', viejas);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · Leer  ←  lo que hoy NO existe ───────────────────────
-- Devuelve la foto en base64 para pintarla en un <img>. Pide token: una foto de
-- captura puede tener a la vista el ticket o la caja de un cliente.
CREATE OR REPLACE FUNCTION public.venta_foto_leer(
  p_store      text,
  p_token      text,
  p_captura_id text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE f public.venta_fotos%ROWTYPE;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO f FROM public.venta_fotos
   WHERE store_id = p_store AND captura_id = trim(coalesce(p_captura_id,''));
  IF NOT FOUND THEN
    -- No es un error: puede ser una venta capturada sin foto, o una de hace más
    -- de 7 días. La app lo dice con esas palabras en vez de "fallo al cargar".
    RETURN jsonb_build_object('ok', false, 'error', 'sin foto');
  END IF;

  RETURN jsonb_build_object('ok', true, 'mime', f.mime,
                            'b64', encode(f.imagen, 'base64'),
                            'creada_en', f.creada_en);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 4 · Ventas del día, ahora diciendo si hay foto ──────────
-- Sin esto el panel no sabe en qué venta pintar el botón de la lupa, y habría
-- que pedir la foto de todas para averiguarlo.
--
-- Se devuelve `captura_id` además: es la llave con la que se pide la foto.
DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
         v.vendida_en, v.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos f
                  WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id)
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date)
  ORDER BY v.vendida_en;
$$;


-- ── 5 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.venta_foto_guardar(text,text,text,text,text) FROM public;
REVOKE ALL ON FUNCTION public.venta_foto_leer(text,text,text)              FROM public;
REVOKE ALL ON FUNCTION public.ventas_detalle(text,date)                    FROM public;

GRANT EXECUTE ON FUNCTION public.venta_foto_guardar(text,text,text,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.venta_foto_leer(text,text,text)              TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date)                    TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Sin token no se guarda ni se lee:
--       select public.venta_foto_guardar('1217','','iX','AAAA');
--       select public.venta_foto_leer('1217','','iX');
--     -> las dos: no_autorizado
--
--  2) Guardar y leer una de prueba (un GIF de 1x1 en base64):
--       select public.venta_foto_guardar('1217','<TOKEN>','iPRUEBAFOTO',
--         'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7','image/gif');
--     -> {"ok": true, "bytes": 43, ...}
--       select public.venta_foto_leer('1217','<TOKEN>','iPRUEBAFOTO');
--     -> ok:true y el mismo b64 que se mandó
--
--  3) Una imagen que no es base64 se rechaza con un mensaje legible:
--       select public.venta_foto_guardar('1217','<TOKEN>','iX','no soy base64 %%%');
--     -> {"ok": false, "error": "la imagen no es base64 valido"}
--
--  4) ventas_detalle trae los campos nuevos SIN perder los viejos:
--       select serie, vendedor, captura_id, tiene_foto
--         from public.ventas_detalle('1217') limit 5;
--     -> `serie` y `vendedor` NO pueden venir vacíos
--
--  5) Limpiar la prueba:
--       delete from public.venta_fotos where captura_id = 'iPRUEBAFOTO';
-- ============================================================


-- ========== supabase_inventario_preventa.sql ==========

-- ============================================================
--  Las entregas de preventa NO descuentan stock
--  7-ago-2026
-- ============================================================
--
--  EL PROBLEMA, CON LOS NÚMEROS QUE LO DESTAPARON
--  ----------------------------------------------
--  Una preventa se COBRA EN EL POS EL DÍA QUE EL CLIENTE APARTA, no el día que
--  se lleva el equipo. Así que para cuando llega el embarque, el POS ya
--  descontó esas piezas, y el "Informe de Artículos Totales" las trae fuera del
--  On Hand.
--
--  Se vio así, el 7-ago-2026, al subir el informe con los apartados ya ligados:
--
--      SKU 100307499 (Orange Ocean)  On Hand 1  ·  apartados 6
--      SKU 100307448 (Graphite Black) On Hand 1  ·  apartados 2
--
--  Seis piezas apartadas de una sola en existencia es imposible: la prueba de
--  que el On Hand ya venía sin ellas.
--
--  Con `apartado_entregar` registrando una venta, `inventario_vivo` volvía a
--  restarlas. No daba negativos —hay greatest(0,…)— y por eso no se vería como
--  un error: daría CERO. El tablero marcaría agotados dos SKUs de los que sí
--  queda una pieza libre, y el asesor le diría "no hay" a un cliente que sí
--  podía comprarlo. Se arreglaba solo al subir el informe siguiente, pero
--  mientras tanto es una venta que se escapa.
--
--  LA CORRECCIÓN
--  -------------
--  `inventario_vivo` deja de contar las ventas que son la entrega de un
--  apartado. Esas piezas ya las descontó el POS; contarlas aquí es descontarlas
--  dos veces.
--
--  Ojo con lo que esto NO cambia: la venta sigue existiendo, con su serie, su
--  vendedor y su fecha. Cuenta para comisiones, para el leaderboard y para el
--  detalle del día. Lo único que no hace es mover el stock.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
--
--  ------------------------------------------------------------
--  CÓMO COMPROBAR QUE NO ROMPIÓ NADA — hacerlo, no saltárselo
--  ------------------------------------------------------------
--  `inventario_vivo` es la función que se verificó CONTANDO CAJAS EN PISO. Si
--  se traduce mal, el tablero miente sobre el stock y nadie se entera hasta que
--  falta mercancía.
--
--  Hoy la prueba es fácil y concluyente: **no hay ni una venta ligada a un
--  apartado** (los 10 están en 'Asignado', ninguno 'Entregado'). Por lo tanto
--  este cambio NO PUEDE alterar ningún número. Si algo se mueve, está mal.
--
--  Antes de pegar:
--    CREATE TEMP TABLE inv_antes AS SELECT * FROM public.inventario_vivo('1217');
--
--  Después de pegar:
--    SELECT count(*) AS deben_ser_cero FROM (
--      SELECT sku, onhand, vendido, stock, exhibicion, exh_vendida FROM inv_antes
--      EXCEPT
--      SELECT sku, onhand, vendido, stock, exhibicion, exh_vendida
--        FROM public.inventario_vivo('1217')
--    ) d;
--    -- Tiene que dar 0. Si da cualquier otra cosa, NO seguir.
-- ============================================================


CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH vendidas AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      -- Las entregas de preventa NO cuentan: el POS ya descontó esas piezas el
      -- día que el cliente pagó el apartado, semanas antes de llevárselo. El On
      -- Hand del informe ya viene sin ellas. Ver la cabecera de este archivo.
      AND NOT EXISTS (
        SELECT 1 FROM public.apartados a
         WHERE a.venta_id = v.id
      )
    GROUP BY v.sku
  )
  SELECT
    c.sku,
    c.descripcion,
    c.precio,
    coalesce(i.onhand, 0)                                            AS onhand,
    -- vendido DESDE el corte diario, no en total
    greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0))::int AS vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, coalesce(i.onhand,0)
              - greatest(0, coalesce(vd.total,0) - coalesce(co.vendidas,0)))::int AS stock,
    coalesce(i.exhibicion, 0)                                        AS exhibicion,
    -- vendido desde la última subida de piso, con su propio corte
    greatest(0, coalesce(vd.total,0) - coalesce(ce.vendidas,0))::int AS exh_vendida
  FROM public.catalogo c
  LEFT JOIN public.inventario i  ON i.store_id  = c.store_id AND i.sku  = c.sku
  LEFT JOIN vendidas vd          ON vd.sku      = c.sku
  LEFT JOIN public.inventario_corte co
         ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
  LEFT JOIN public.inventario_corte ce
         ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
  WHERE c.store_id = p_store;
$$;


-- ------------------------------------------------------------
-- El corte tiene que contar igual, o el arreglo dura UN DÍA
-- ------------------------------------------------------------
-- Esto no es un extra: sin ello, el arreglo de arriba se convierte en un error
-- distinto en cuanto se suba el siguiente informe.
--
-- `cargar_cortes` no guarda el corte que le manda el GAS: lo DESPEJA, con
--     corte = (total de ventas en Supabase) - (lo que el GAS reporta como v)
--
-- Y ahí hay una asimetría que no se ve a simple vista: las entregas de preventa
-- las escribe `apartado_entregar` **solo en Supabase**. La hoja no se entera, o
-- sea que la `v` del GAS nunca las incluye, pero el `total` de Supabase sí.
-- Resultado: el corte se infla con las entregas de preventa.
--
-- Con la lectura ya filtrada, la cuenta quedaría:
--     vendido = total_sin_preventa - corte_inflado = v - (nº de entregas)
--
-- O sea que cada entrega de preventa RESTARÍA una venta normal del conteo. Con
-- 3 ventas del día y 6 entregas, `vendido` daría 0 en vez de 3, y el tablero
-- mostraría 3 piezas de más. El mismo desajuste de antes, al revés, y bastante
-- peor: enseñar stock que no existe manda a un asesor a buscar una caja que no
-- está, delante del cliente.
--
-- Las dos cuentas tienen que excluir exactamente lo mismo.
/* DESACTIVADA en esta copia.

   Traia los cortes de inventario del Apps Script, con `http_get(t.gas_url ...)`. Aqui no hay Apps
   Script: `gas_url` no existe como columna, asi que la funcion original ni
   siquiera compila. Solo la llamaba `resincronizar`, que ya estaba desactivada
   desde el 7-ago-2026 —el inventario se carga desde Admin—, o sea que
   esto era codigo muerto que ademas guardaba la unica referencia viva a la
   hoja dentro de la base.

   Se deja definida y no se borra: si algo la llamara, tiene que DECIR que no
   hace nada. Borrada daria «function does not exist», que se lee como base mal
   montada y manda a buscar donde no es. */
CREATE OR REPLACE FUNCTION public.cargar_cortes(p_store text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 'DESACTIVADA: no hay Apps Script del que traer nada. Sube el informe del dia desde Admin.'::text;
$fn$;


-- ============================================================
--  DESPUÉS DE APLICAR
-- ============================================================
--  1) La comprobación de arriba (deben_ser_cero) tiene que dar 0.
--
--  2) Cuando ya haya entregado alguna, el efecto se ve así:
--       SELECT a.cliente, a.sku, a.serie, v.id AS venta
--         FROM public.apartados a JOIN public.ventas v ON v.id = a.venta_id
--        WHERE a.store_id = '1217';
--     Esas ventas existen —cuentan para comisiones— y NO aparecen en el
--     `vendido` de inventario_vivo.
--
--  3) El stock de esos SKU debe seguir siendo el On Hand del informe:
--       SELECT sku, onhand, vendido, stock
--         FROM public.inventario_vivo('1217')
--        WHERE sku IN ('100307448','100307499');
--     -> vendido 0 y stock 1 en los dos, aunque se hayan entregado 8 piezas.
-- ============================================================


-- ========== supabase_preventa_series.sql ==========

-- ============================================================
--  PREVENTA NATIVA EN SUPABASE — apartados, series y entrega
--  Etapa 1 de "apagar la hoja" (fase 4 del MIGRACION_PLAN, adelantada)
--  7-ago-2026
-- ============================================================
--
--  QUE CAMBIA
--  ----------
--  Hasta hoy los apartados vivian SOLO en la hoja: `agregarApartado_`
--  (GAS_Codigo.gs, l. 559) hace appendRow y nada mas. El Apps Script NUNCA
--  escribio en Supabase. Los 9 apartados que hay en la tabla son el volcado
--  manual del 2-ago y ahi se quedaron congelados.
--
--  Efecto colateral que esto destapa: el trigger `apartado_cabe` que se
--  corrigio el 5-ago para frenar el doble apartado NUNCA SE HA DISPARADO,
--  porque nadie inserta en la tabla que vigila. El cupo real lo estaba
--  sosteniendo solo el numero del navegador.
--
--  A partir de aqui la tabla `apartados` es la unica verdad y la hoja deja de
--  recibir preventa.
--
--  EL ORDEN IMPORTA: correr `resincronizar('1217')` ANTES de esto, para traer
--  los apartados que la hoja tenga desde el 2-ago. Si se hace despues, la
--  resincronizacion pisa las series recien asignadas con las filas de la hoja,
--  que no las tienen.
--
--  Se pega completo en el SQL Editor del proyecto "HES" (rjdrljtujbwooejrpyqv).
--  Es idempotente.
-- ============================================================


-- ── 1 · Las columnas que faltaban ───────────────────────────
-- `serie` es el numero de serie del equipo fisico ligado a ese cliente.
-- Se separa `asignado_en` de `entregado_en` a proposito: asignar es apartar la
-- pieza al recibir la caja, entregar es que salio de la tienda. Con una sola
-- fecha no se puede saber cuanta mercancia esta comprometida pero todavia en
-- bodega, que es justo lo que hay que saber cuando llega el embarque.
--
-- `entregado_por` NO es lo mismo que `vendedor`: la venta se acredita a quien
-- hizo la preventa, pero quien puso el equipo en las manos del cliente puede
-- ser otro, y es la primera pregunta que se hace cuando hay un reclamo.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS serie         text,
  ADD COLUMN IF NOT EXISTS asignado_en   timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_en  timestamptz,
  ADD COLUMN IF NOT EXISTS entregado_por text,
  ADD COLUMN IF NOT EXISTS venta_id      bigint;


-- ── 2 · Una serie no puede estar en dos apartados ───────────
-- Es EL error que no se puede permitir: dos clientes con la misma pieza
-- prometida se descubre con los dos enfrente del mostrador. Los cancelados
-- quedan fuera del indice: si un apartado se cae, su serie se libera para otro.
CREATE UNIQUE INDEX IF NOT EXISTS apartados_serie_unica
  ON public.apartados (store_id, serie)
  WHERE serie IS NOT NULL AND estatus <> 'Cancelado';


-- ── 3 · La guardia de escritura ─────────────────────────────
-- Mismo candado que ya protege al Apps Script desde el 4-ago: el token de
-- tienda, que llega en la sesion (login_asesor/login_empleado lo devuelven como
-- `gas_token`). No es peor que hoy ni mejor: es EL MISMO secreto compartido,
-- movido de puerta. La anon key por si sola no basta para escribir.
--
-- Se llama `gas_token` porque asi se llama la columna hoy. Al retirar el Apps
-- Script (etapa 5) se renombra a `write_token`; renombrarla ahora obligaria a
-- tocar el login y las seis apps en el mismo movimiento, y esto tiene que poder
-- entrar solo.
CREATE OR REPLACE FUNCTION public.escritura_ok_(p_store text, p_token text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tiendas t
     WHERE t.store_id = p_store
       AND coalesce(t.activo, true) = true
       AND length(coalesce(p_token,'')) >= 8
       AND p_token = t.gas_token
  );
$$;


-- ── 4 · Guardar un apartado  ←  reemplaza modo=apartado_add ──
-- Devuelve el error en jsonb en vez de lanzarlo: el asesor tiene al cliente
-- enfrente y necesita leer que paso, no un 500 del PostgREST.
CREATE OR REPLACE FUNCTION public.apartado_guardar(
  p_store       text,
  p_token       text,
  p_sku         text,
  p_color       text    DEFAULT NULL,   -- producto entero, ver MAPA cadena 2-bis
  p_cliente     text    DEFAULT NULL,
  p_telefono    text    DEFAULT NULL,
  p_precio      numeric DEFAULT NULL,
  p_seguro      boolean DEFAULT false,
  p_vendedor    text    DEFAULT NULL,
  p_transaccion text    DEFAULT NULL    -- ticket del POS: el enlace con la venta
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_cliente),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin cliente');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;

  INSERT INTO public.apartados
    (store_id, sku, color, cliente, telefono, precio, con_seguro,
     vendedor, transaccion, piezas, estatus)
  VALUES
    (p_store, trim(p_sku), nullif(trim(coalesce(p_color,'')),''),
     trim(p_cliente), nullif(trim(coalesce(p_telefono,'')),''), p_precio,
     coalesce(p_seguro, false), nullif(trim(coalesce(p_vendedor,'')),''),
     nullif(trim(coalesce(p_transaccion,'')),''), 1, 'Apartado')
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);

EXCEPTION
  -- El trigger apartado_cabe lanza esto cuando el SKU llego a su cupo. Es un
  -- resultado esperado, no una averia: se traduce a algo que el asesor entienda.
  WHEN raise_exception THEN
    RETURN jsonb_build_object('ok', false, 'error', left(SQLERRM, 140));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 5 · Asignar la serie  ←  al recibir el embarque ─────────
-- Idempotente a proposito: volver a escanear la MISMA serie en el MISMO
-- apartado responde ok, no error. Un asesor que no vio el toast escanea otra
-- vez, y eso no puede ser un fallo.
CREATE OR REPLACE FUNCTION public.apartado_serie(
  p_store text,
  p_token text,
  p_id    bigint,
  p_serie text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE a public.apartados%ROWTYPE; ocupada text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  SELECT * INTO a FROM public.apartados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Cancelado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el apartado esta cancelado');
  END IF;
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ya se entrego, la serie no se cambia');
  END IF;

  -- ya la tiene: reintento, no problema
  IF a.serie IS NOT NULL AND trim(a.serie) = trim(p_serie) THEN
    RETURN jsonb_build_object('ok', true, 'id', a.id, 'serie', a.serie, 'repetida', true);
  END IF;

  -- la pieza ya esta prometida a otro cliente
  SELECT cliente INTO ocupada FROM public.apartados
   WHERE store_id = p_store AND serie = trim(p_serie)
     AND estatus <> 'Cancelado' AND id <> p_id
   LIMIT 1;
  IF ocupada IS NOT NULL THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa serie ya es de ' || ocupada);
  END IF;

  UPDATE public.apartados
     SET serie = trim(p_serie), asignado_en = now(),
         estatus = CASE WHEN estatus = 'Apartado' THEN 'Asignado' ELSE estatus END
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'serie', trim(p_serie),
                            'estatus', 'Asignado');
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false, 'error', 'esa serie ya esta asignada');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 6 · Entregar  ←  cuando el cliente se lleva el equipo ───
-- Hace DOS cosas en una transaccion: registra la venta y cierra el apartado.
-- Separarlas dejaria entregas sin venta si falla la segunda llamada, y eso no
-- da error: da inventario que no baja.
--
-- La venta se acredita al VENDEDOR DEL APARTADO, no a quien entrega —decidido
-- el 7-ago-2026—. Con la fecha de HOY, que es cuando el equipo sale. Ojo al
-- comparar con el POS: ahi el ticket se cobro semanas antes, asi que estas
-- piezas caen en meses distintos en un reporte y en el otro. Es esperado.
-- DROP explícito: si una versión anterior quedó con otra lista de parámetros,
-- CREATE OR REPLACE no la sustituye —crea una sobrecarga—, y PostgREST tendría
-- dos candidatas y elegiría mal sin avisar.
DROP FUNCTION IF EXISTS public.apartado_entregar(text,text,bigint,text);
DROP FUNCTION IF EXISTS public.apartado_entregar(text,text,bigint,text,text);

CREATE FUNCTION public.apartado_entregar(
  p_store text,
  p_token text,
  p_id    bigint,
  p_serie text DEFAULT NULL,    -- si viene, tiene que coincidir con la asignada
  p_quien text DEFAULT NULL     -- quién entrega, que no es quién vendió
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  a       public.apartados%ROWTYPE;
  v_serie text;
  v_desc  text;
  nuevo   bigint;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO a FROM public.apartados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Cancelado' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'el apartado esta cancelado');
  END IF;

  -- Ya entregado: no se vuelve a registrar la venta. Un doble toque del boton
  -- con mala señal no puede convertirse en dos ventas.
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', true, 'id', a.id, 'serie', a.serie,
                              'venta_id', a.venta_id, 'ya_entregado', true);
  END IF;

  v_serie := nullif(trim(coalesce(p_serie, a.serie, '')), '');
  IF v_serie IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie: asignala antes de entregar');
  END IF;
  -- Escanear al entregar es la verificacion de que sale LA pieza de ese cliente
  -- y no otra del mismo color. Si no coincide, se para aqui.
  IF a.serie IS NOT NULL AND trim(a.serie) <> v_serie THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa no es su pieza: tiene asignada la ' || a.serie);
  END IF;

  -- La descripcion sale del catalogo. Si el SKU todavia no esta cargado —el
  -- caso de la Pura 90S el 7-ago— se usa el texto del apartado, que desde el
  -- 4-ago trae el producto entero. Vale mas eso que una venta sin descripcion.
  SELECT c.descripcion INTO v_desc
    FROM public.catalogo c
   WHERE c.store_id = p_store AND c.sku = a.sku;
  v_desc := nullif(trim(coalesce(nullif(trim(coalesce(v_desc,'')),''), a.color, '')), '');

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro)
  VALUES
    (p_store, now(), v_serie, a.sku, v_desc, a.precio,
     coalesce(nullif(trim(coalesce(a.vendedor,'')),''), 'preventa'),
     coalesce(a.con_seguro, false))
  RETURNING id INTO nuevo;

  UPDATE public.apartados
     SET estatus = 'Entregado', serie = v_serie, entregado_en = now(),
         entregado_por = nullif(trim(coalesce(p_quien,'')),''),
         asignado_en = coalesce(asignado_en, now()), venta_id = nuevo
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'serie', v_serie,
                            'venta_id', nuevo, 'estatus', 'Entregado');

EXCEPTION
  -- La restriccion de ventas es "misma serie no dos veces el mismo dia"
  -- (supabase_ventas_devolucion.sql). Si salta aqui, esa serie ya se vendio hoy:
  -- casi siempre significa que alguien la capturo tambien por Captura de Series.
  WHEN unique_violation THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa serie ya se registro como vendida hoy');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 7 · Cancelar / corregir estatus  ←  modo=apartado_estatus ─
-- Cancelar un apartado ya entregado NO borra la venta: la pieza salio de la
-- tienda y el inventario tiene que seguir reflejandolo. Se rechaza y punto.
CREATE OR REPLACE FUNCTION public.apartado_estatus(
  p_store   text,
  p_token   text,
  p_id      bigint,
  p_estatus text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE a public.apartados%ROWTYPE;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF p_estatus NOT IN ('Apartado','Asignado','Cancelado') THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'estatus invalido: Entregado se pone con apartado_entregar');
  END IF;

  SELECT * INTO a FROM public.apartados WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'apartado no encontrado');
  END IF;
  IF a.estatus = 'Entregado' THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'ya se entrego: para revertirlo hay que anular la venta');
  END IF;

  UPDATE public.apartados
     SET estatus = p_estatus,
         -- al cancelar se suelta la serie, para que la pieza vuelva a estar
         -- disponible para otro cliente
         serie       = CASE WHEN p_estatus = 'Cancelado' THEN NULL ELSE serie END,
         asignado_en = CASE WHEN p_estatus = 'Cancelado' THEN NULL ELSE asignado_en END
   WHERE id = p_id AND store_id = p_store;

  RETURN jsonb_build_object('ok', true, 'id', p_id, 'estatus', p_estatus);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 8 · La lectura, ampliada ────────────────────────────────
-- OJO: la version que hay en produccion YA devuelve color, precio y transaccion
-- (se amplio en el editor el 4-ago y el .sql del repo se quedo atras). Esta
-- version incluye esos tres MAS los cuatro campos nuevos. Si se pega la del
-- repo viejo encima, se cae el numero de ticket sin que nada avise.
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               color text, precio numeric, transaccion text,
               serie text, asignado_en timestamptz, entregado_en timestamptz,
               entregado_por text, venta_id bigint,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         a.color, a.precio, a.transaccion,
         a.serie, a.asignado_en, a.entregado_en, a.entregado_por, a.venta_id,
         pc.cupo,
         (SELECT coalesce(sum(x.piezas), 0)::int
            FROM public.apartados x
           WHERE x.store_id = a.store_id AND x.sku = a.sku
             AND x.estatus <> 'Cancelado') AS apartadas
  FROM public.apartados a
  LEFT JOIN public.preventa_cupo pc
         ON pc.store_id = a.store_id AND pc.sku = a.sku
  WHERE a.store_id = p_store
  ORDER BY a.creado_en DESC;
$$;


-- ── 9 · Permisos ────────────────────────────────────────────
-- escritura_ok_ NO se expone: es la guardia, no una funcion de la app.
REVOKE ALL ON FUNCTION public.escritura_ok_(text,text) FROM public, anon, authenticated;

REVOKE ALL ON FUNCTION public.apartados_lista(text)                        FROM public;
REVOKE ALL ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_serie(text,text,bigint,text)        FROM public;
REVOKE ALL ON FUNCTION public.apartado_entregar(text,text,bigint,text,text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_estatus(text,text,bigint,text)      FROM public;

GRANT EXECUTE ON FUNCTION public.apartados_lista(text)                        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_serie(text,text,bigint,text)        TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_entregar(text,text,bigint,text,text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_estatus(text,text,bigint,text)      TO anon, authenticated;


-- ── 10 · Que resincronizar deje de pisar los apartados ──────
-- ESTE PASO NO ES OPCIONAL y es el que menos se ve venir.
--
-- `cargar_apartados_comisiones` —que corre dentro de `resincronizar()`— hace
-- DELETE FROM apartados y los reinserta desde la hoja. Tenía sentido cuando la
-- hoja era la verdad. A partir de ahora es al revés: correr `resincronizar()`
-- borraría TODAS las series asignadas, las entregas y los apartados nuevos, y
-- los sustituiría por la foto de una hoja que ya nadie escribe.
--
-- No avisaría de nada. `resincronizar` diría "los seis pasos en verde" y el
-- tablero mostraría los apartados sin serie, como si el embarque no hubiera
-- llegado.
--
-- Se queda cargando solo comisiones. El nombre se conserva porque
-- `resincronizar()` la llama por nombre; se limpia en la etapa 5.
/* DESACTIVADA en esta copia.

   Traia las comisiones del Apps Script, con `http_get(t.gas_url ...)`. Aqui no hay Apps
   Script: `gas_url` no existe como columna, asi que la funcion original ni
   siquiera compila. Solo la llamaba `resincronizar`, que ya estaba desactivada
   desde el 7-ago-2026 —el reporte se carga desde Admin—, o sea que
   esto era codigo muerto que ademas guardaba la unica referencia viva a la
   hoja dentro de la base.

   Se deja definida y no se borra: si algo la llamara, tiene que DECIR que no
   hace nada. Borrada daria «function does not exist», que se lee como base mal
   montada y manda a buscar donde no es. */
CREATE OR REPLACE FUNCTION public.cargar_apartados_comisiones(p_store text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT 'DESACTIVADA: no hay Apps Script del que traer nada. Sube el reporte de comisiones desde Admin.'::text;
$fn$;


-- ============================================================
--  COMPROBAR ANTES DE CONECTAR LAS APPS
--  (pegar de a poco; el bloque de arriba ya quedo aplicado)
-- ============================================================
--
--  0) Que la lectura traiga los campos nuevos y no haya perdido los viejos:
--       select id, cliente, transaccion, serie, estatus
--         from public.apartados_lista('1217') limit 3;
--     -> transaccion NO puede venir vacia. Si viene, se piso la funcion buena.
--
--  1) Sin token no se escribe:
--       select public.apartado_serie('1217','', 38, 'PRUEBA-1');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Con token (sacarlo de: select gas_token from tiendas where store_id='1217')
--       select public.apartado_serie('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "estatus": "Asignado"}
--
--  3) La misma serie otra vez en el MISMO apartado: repetida, no error
--       select public.apartado_serie('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "repetida": true}
--
--  4) La misma serie en OTRO apartado: tiene que negarse
--       select public.apartado_serie('1217','<TOKEN>', 37, 'PRUEBA-1');
--     -> {"ok": false, "error": "esa serie ya es de Jesus manuel"}
--
--  5) Entregar con una serie que no es la suya: tiene que negarse
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'OTRA-COSA');
--     -> {"ok": false, "error": "esa no es su pieza: tiene asignada la PRUEBA-1"}
--
--  6) Entregar bien -> crea la venta con el vendedor del apartado
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'PRUEBA-1');
--       select serie, sku, vendedor, con_seguro, dia_venta, descripcion
--         from public.ventas where serie = 'PRUEBA-1';
--     -> vendedor 'Maria' (el de la preventa), NO quien entrego
--
--  7) Entregar otra vez: NO puede crear una segunda venta
--       select public.apartado_entregar('1217','<TOKEN>', 38, 'PRUEBA-1');
--     -> {"ok": true, ..., "ya_entregado": true}
--       select count(*) from public.ventas where serie = 'PRUEBA-1';   -- 1
--
--  8) Deshacer la prueba:
--       delete from public.ventas where serie = 'PRUEBA-1';
--       update public.apartados
--          set estatus='Apartado', serie=NULL, asignado_en=NULL,
--              entregado_en=NULL, venta_id=NULL
--        where id = 38;
-- ============================================================


-- ========== supabase_notificaciones.sql ==========

-- ============================================================
--  NOTIFICACIONES PUSH — de Apps Script a Supabase
--  Etapa 5 de "apagar la hoja"  ·  7-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia `escritura_ok_`).
--  Y crea `tiendas.app_url`: a donde lleva el aviso al tocarlo.
--
--  ------------------------------------------------------------
--  POR QUÉ ESTE ERA "EL NUDO", Y POR QUÉ AL FINAL NO LO FUE
--  ------------------------------------------------------------
--  `notificar_` era lo único del Apps Script que no se podía traducir sin más:
--  la REST API key de OneSignal es SECRETA y no puede vivir en el HTML, que es
--  público. Todo lo demás del cliente se protege con el token de tienda, pero
--  ese token también viaja al navegador — sirve para decir "esta tienda puede
--  escribir", no para guardar un secreto de terceros.
--
--  La respuesta obvia era una Edge Function. Pero resulta que la extensión
--  `http` de Postgres YA está habilitada en este proyecto —`cargar_catalogo` la
--  usa con `extensions.http_get`—, así que la llamada a OneSignal se puede hacer
--  desde una función SQL `SECURITY DEFINER`:
--
--    · la llave vive en una tabla con RLS que `anon` no puede leer
--    · la función sí la lee, porque corre como su dueño
--    · el cliente manda el mensaje y su token, nunca la llave
--
--  Sin CLI, sin despliegue y sin una pieza más que mantener. La Edge Function
--  sigue siendo la vía canónica si algún día hace falta algo más (reintentos,
--  segmentar por usuario), pero para mandar un push no aporta nada.
--
--  ------------------------------------------------------------
--  ANTES DE PEGAR: TEN A MANO LAS DOS CLAVES
--  ------------------------------------------------------------
--  Están en el editor del Apps Script → ⚙ Configuración del proyecto →
--  Propiedades del script:  ONESIGNAL_APP_ID  y  ONESIGNAL_KEY
--
--  Se pegan en el PASO 3 de este archivo, directamente en el SQL Editor.
--  NO se escriben en ningún archivo del repo: es público.
-- ============================================================


-- ── 1 · Dónde vive la llave ─────────────────────────────────
-- Tabla aparte de `tiendas` a propósito: `login_asesor` devuelve campos de
-- `tiendas` al navegador, y una llave de OneSignal ahí acabaría saliendo por esa
-- puerta el día que alguien añada un `SELECT *`.
-- ── 0 · A dónde lleva el aviso ──────────────────────────────
-- Cada tienda publica su copia en su propia dirección. Se guarda entera y con
-- el https delante, tal cual se pega en el navegador. Ejemplo:
--   update public.tiendas
--      set app_url = 'https://usuario.github.io/tablero-odemas/tablero.html'
--    where store_id = '9999';
ALTER TABLE public.tiendas
  ADD COLUMN IF NOT EXISTS app_url text;

COMMENT ON COLUMN public.tiendas.app_url IS
  'URL del tablero de esta tienda. La usan las notificaciones push como destino '
  'al tocarlas. Vacio = el aviso se manda sin enlace.';

CREATE TABLE IF NOT EXISTS public.notif_config (
  store_id    text        PRIMARY KEY REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  app_id      text        NOT NULL,
  api_key     text        NOT NULL,
  actualizado timestamptz NOT NULL DEFAULT now()
);

-- RLS sin ninguna política = nadie llega por REST, ni anon ni authenticated.
-- Solo la ven las funciones SECURITY DEFINER de abajo.
ALTER TABLE public.notif_config ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.notif_config FROM anon, authenticated;

COMMENT ON TABLE public.notif_config IS
  'Credenciales de OneSignal. NUNCA exponer por una funcion que devuelva '
  'sus filas: la api_key es un secreto de terceros, no un token de tienda.';


-- ── 2 · Mandar la notificación  ←  reemplaza modo=notificar ─
CREATE OR REPLACE FUNCTION public.notificar(
  p_store  text,
  p_token  text,
  p_msg    text,
  p_titulo text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE
  cfg      public.notif_config%ROWTYPE;
  v_titulo text;
  v_url    text;
  resp     extensions.http_response;
  cuerpo   jsonb;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_msg),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin mensaje');
  END IF;

  SELECT * INTO cfg FROM public.notif_config WHERE store_id = p_store;
  IF NOT FOUND THEN
    -- Mismo texto que daba el Apps Script, para que quien lo vea sepa buscar
    -- en el sitio de siempre.
    RETURN jsonb_build_object('ok', false, 'error', 'OneSignal no configurado');
  END IF;

  -- El título sale de la tienda, no escrito a mano: el Apps Script tenía
  -- 'HES Angelópolis 1217' incrustado, y con una segunda tienda mandaría
  -- notificaciones firmadas por la primera.
  SELECT 'HES ' || t.store_id || ' · ' || coalesce(t.nombre,'')
    INTO v_titulo FROM public.tiendas t WHERE t.store_id = p_store;
  v_titulo := coalesce(nullif(trim(coalesce(p_titulo,'')),''), v_titulo, 'HES');

  -- La URL sale de la tienda. Iba fija, con un comentario que decía «cuando
  -- haya una segunda tienda se añade la columna y se cambia esta línea». Este
  -- archivo ES esa segunda tienda: con la URL fija, el aviso de CUALQUIER
  -- tienda abriría el tablero de otra — y el asesor vería stock y precios que
  -- no son los suyos, sin nada que se lo diga.
  SELECT nullif(trim(coalesce(t.app_url,'')), '')
    INTO v_url FROM public.tiendas t WHERE t.store_id = p_store;

  -- Sin URL configurada se manda el aviso IGUAL, solo que sin enlace: OneSignal
  -- abre la app y ya. Callar el aviso entero por un campo vacío sería perder la
  -- notificación —que es lo que se quería mandar— por un detalle de forma.
  IF v_url IS NOT NULL AND v_url !~* '^https://' THEN
    -- Un enlace que no es https no lo abre el navegador desde una push, y
    -- ademas seria el sitio donde alguien mandaria a los asesores.
    v_url := NULL;
  END IF;

  -- La extensión corta sola; sin esto una caída de OneSignal dejaría la
  -- transacción esperando y con ella al gerente mirando un botón girando.
  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '15');

  SELECT * INTO resp FROM extensions.http((
    'POST',
    'https://onesignal.com/api/v1/notifications',
    ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
    'application/json',
    jsonb_build_object(
      'app_id',            cfg.app_id,
      -- `target_channel` es obligatorio desde el modelo de usuarios nuevo de
      -- OneSignal: una app puede tener push, email y SMS, y sin decirlo responde
      -- 400 «Message Notifications must have At Least One Target Channel».
      -- El Apps Script no lo mandaba —se escribió cuando aún se asumía push— y
      -- por eso sus notificaciones tampoco habrían salido aunque hubiera habido
      -- suscriptores. (7-ago-2026)
      'target_channel',    'push',
      'included_segments', jsonb_build_array('All'),
      -- `en` es OBLIGATORIO: OneSignal lo usa como idioma de respaldo y sin él
      -- responde 400 «Message Notifications must have Any/English language».
      -- Va el mismo texto en español en las dos claves: el equipo lee español y
      -- traducir de verdad no aportaría nada. `es` se queda para que a quien
      -- tenga el teléfono en español le llegue por su idioma, no por el
      -- respaldo. (El Apps Script mandaba solo `es`, así que también habría
      -- fallado con este mismo 400.)
      'headings',          jsonb_build_object('en', v_titulo, 'es', v_titulo),
      'contents',          jsonb_build_object('en', trim(p_msg), 'es', trim(p_msg)),
      'url',               v_url
    )::text
  )::extensions.http_request);

  BEGIN
    cuerpo := resp.content::jsonb;
  EXCEPTION WHEN OTHERS THEN
    cuerpo := jsonb_build_object('respuesta_no_json', left(coalesce(resp.content,''), 200));
  END;

  -- "All included players are not subscribed" NO es un fallo: la llamada llegó,
  -- la llave es buena y OneSignal contestó 200. Lo que dice es que no hay NADIE
  -- suscrito al push todavía.
  --
  -- Se separa a propósito. Tratarlo como error haría que Admin dijera "la
  -- notificación no salió" cada vez que se sube un combo, y el gerente acabaría
  -- ignorando un aviso que un día sí significará algo. Lo que hay que hacer con
  -- esto no es arreglar código: es que el equipo toque la campana del tablero.
  -- (Medido el 7-ago-2026: cero suscriptores. Las notificaciones que mandaba el
  -- Apps Script no le llegaban a nadie, y nadie lo sabía porque
  -- `notificarEquipo` se tragaba el resultado con un console.warn.)
  IF resp.status = 200 AND cuerpo::text ILIKE '%not subscribed%' THEN
    RETURN jsonb_build_object('ok', true, 'destinatarios', 0,
                              'sin_suscriptores', true);
  END IF;

  -- OneSignal responde 200 con un array `errors` cuando rechaza algo, así que
  -- mirar solo el código HTTP daría por buena una notificación que nunca salió.
  IF resp.status <> 200 OR cuerpo ? 'errors' THEN
    RETURN jsonb_build_object('ok', false, 'http', resp.status,
                              'error', left(coalesce(cuerpo->>'errors', cuerpo::text), 200));
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', cuerpo->>'id',
                            'destinatarios', cuerpo->>'recipients');
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.notificar(text,text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.notificar(text,text,text,text) TO anon, authenticated;


-- ── 3 · PEGAR AQUÍ LA LLAVE ─────────────────────────────────
-- El `app_id` ya va puesto: NO es secreto. Está en tablero.html (l. 2246)
-- porque el navegador lo necesita para suscribirse al push, y ese archivo es
-- público. Escribirlo aquí no añade riesgo ninguno.
--
-- La REST API Key SÍ es secreta y es lo único que hay que pegar. Se saca de:
--
--   a) Apps Script → ⚙ Configuración del proyecto → Propiedades del script,
--      la fila `ONESIGNAL_KEY`. Si la interfaz no enseña el valor, ejecuta
--      `verClaveOneSignal` desde el editor (está en GAS_Codigo.gs) y sale en
--      el registro.
--
--   b) O de la fuente original: onesignal.com → tu app → Settings →
--      Keys & IDs → "REST API Key".
--
-- Se pega DIRECTAMENTE en el SQL Editor, nunca en un archivo del repo.
/*
INSERT INTO public.notif_config (store_id, app_id, api_key)
VALUES ('<tu-tienda>', 'PEGA_AQUI_EL_APP_ID', 'PEGA_AQUI_LA_REST_API_KEY')
ON CONFLICT (store_id) DO UPDATE
  SET app_id = excluded.app_id, api_key = excluded.api_key, actualizado = now();
*/


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token de tienda:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Sin token no se manda nada:
--       select public.notificar('1217','','hola');
--     -> {"ok": false, "error": "no_autorizado"}
--
--  2) Nadie puede leer la llave por REST. Desde el SQL Editor (que es dueño) sí
--     se ve; lo que importa es que la app NO. Se comprueba desde fuera:
--       curl -s -X POST '<url>/rest/v1/rpc/...' — no hay función que la devuelva.
--     Y por tabla:
--       select * from public.notif_config;   -- desde el editor: 1 fila
--     Con la anon key, la misma consulta por REST devuelve 0 filas (RLS).
--
--  3) LA PRUEBA DE VERDAD — manda una notificación real a los teléfonos:
--       select public.notificar('1217','<TOKEN>','Prueba desde Supabase, ignorar');
--     -> {"ok": true, "id": "...", "destinatarios": "N"}
--
--     Si `destinatarios` es 0, la llamada funcionó pero no hay nadie suscrito:
--     no es un fallo de esto.
--
--     Si devuelve `no configurado`, falta el PASO 3.
--     Si devuelve un error con `errors`, la llave o el app_id no son correctos:
--     se vuelven a copiar de las Propiedades del script.
-- ============================================================


-- ========== supabase_notif_diagnostico.sql ==========

-- ============================================================
--  DIAGNÓSTICO DE NOTIFICACIONES  ·  7-ago-2026
-- ============================================================
--
--  Le pregunta a OneSignal dos cosas que desde fuera no se ven:
--    · cuántas suscripciones tiene la app de verdad
--    · qué pasó con una notificación concreta (entregada, fallida, a cuántos)
--
--  Existe porque `ok:true` con `destinatarios:null` no dice nada: la
--  notificación se aceptó, pero no si llegó a alguien. Sin esto solo queda
--  probar a ciegas, y eso ya costó una hora hoy.
--
--  Usa la llave de `notif_config`, así que no hay que copiarla a ningún sitio.
--  Se pega completo en el SQL Editor.
-- ============================================================

CREATE OR REPLACE FUNCTION public.notif_diagnostico(
  p_store text,
  p_token text,
  p_notif text DEFAULT NULL     -- id de una notificación, para ver su entrega
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions
AS $fn$
DECLARE
  cfg  public.notif_config%ROWTYPE;
  r    extensions.http_response;
  subs jsonb;
  noti jsonb := NULL;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  SELECT * INTO cfg FROM public.notif_config WHERE store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'OneSignal no configurado');
  END IF;

  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '20');

  -- ── cuántas suscripciones hay ──
  SELECT * INTO r FROM extensions.http((
    'GET',
    'https://onesignal.com/api/v1/players?app_id=' || cfg.app_id || '&limit=1',
    ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
    NULL, NULL
  )::extensions.http_request);

  BEGIN subs := r.content::jsonb;
  EXCEPTION WHEN OTHERS THEN subs := jsonb_build_object('crudo', left(coalesce(r.content,''),200));
  END;

  -- ── qué pasó con esa notificación ──
  IF coalesce(trim(p_notif),'') <> '' THEN
    SELECT * INTO r FROM extensions.http((
      'GET',
      'https://onesignal.com/api/v1/notifications/' || trim(p_notif) || '?app_id=' || cfg.app_id,
      ARRAY[extensions.http_header('Authorization', 'Basic ' || cfg.api_key)],
      NULL, NULL
    )::extensions.http_request);
    BEGIN noti := r.content::jsonb;
    EXCEPTION WHEN OTHERS THEN noti := jsonb_build_object('crudo', left(coalesce(r.content,''),200));
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'suscripciones_totales', subs->'total_count',
    -- Lo que importa de cada suscripción: si está suscrita de verdad y a qué
    -- dispositivo. `invalid_identifier` en true = el navegador revocó el push.
    'primera_suscripcion', CASE
        WHEN jsonb_array_length(coalesce(subs->'players','[]'::jsonb)) > 0
        THEN jsonb_build_object(
               'tipo',    subs->'players'->0->>'device_type',
               'modelo',  subs->'players'->0->>'device_model',
               'activa',  subs->'players'->0->>'notification_types',
               'invalida',subs->'players'->0->>'invalid_identifier',
               'url',     subs->'players'->0->>'url')
        ELSE NULL END,
    'notificacion', CASE WHEN noti IS NULL THEN NULL ELSE jsonb_build_object(
        'exitosas',   noti->'successful',
        'fallidas',   noti->'failed',
        'con_error',  noti->'errored',
        'pendientes', noti->'remaining',
        'error',      noti->'errors') END
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.notif_diagnostico(text,text,text) FROM public, anon, authenticated;
-- NO se concede a anon: esto expone datos de dispositivos y solo se usa desde
-- el SQL Editor, con cuenta de dueño.


-- ============================================================
--  CÓMO USARLO
-- ============================================================
--   select public.notif_diagnostico(
--     '1217',
--     (select gas_token from public.tiendas where store_id='1217'),
--     'e7fe34b2-e039-4a8c-931a-a40b27a16da6');   -- id de la notificación
--
--  Cómo leerlo:
--
--   suscripciones_totales = 0
--     -> el alta nunca se completó. La campana se puso roja pero OneSignal no
--        registró el dispositivo. El problema está en el navegador.
--
--   suscripciones_totales > 0  pero  notificacion.exitosas = 0
--     -> hay dispositivos, pero el envío no llegó a ellos: casi siempre el
--        segmento. Las apps nuevas de OneSignal ya no traen "All"; se llama
--        "Subscribed Users" o "Total Subscriptions".
--
--   exitosas > 0 y aun así no sonó
--     -> salió de OneSignal y llegó al teléfono: es cosa del dispositivo
--        (batería, modo silencio, notificaciones de Chrome apagadas en Android).
--
--   primera_suscripcion.invalida = true
--     -> el navegador revocó el push. Hay que borrar datos del sitio y
--        volver a suscribirse.
-- ============================================================


-- ========== supabase_apartados_traspaso.sql ==========

-- ============================================================
--  APARTADOS: vender con promesa de entrega
--  8-ago-2026
-- ============================================================
--
--  Depende de supabase_preventa_series.sql (guardia y funciones de apartado) y
--  de supabase_attach_apartados.sql (el attach del día del cobro).
--
--  ------------------------------------------------------------
--  POR QUÉ NO ES UNA TABLA NUEVA
--  ------------------------------------------------------------
--  Pedirle un equipo a otra tienda para un cliente es, paso por paso, lo mismo
--  que una preventa: el cliente PAGA COMPLETO, no hay equipo, llega días
--  después y se entrega con su serie. Los estados son los mismos
--  (Apartado → Asignado → Entregado), la entrega genera la misma venta y
--  tampoco descuenta stock, porque el POS ya cobró.
--
--  Construir una tabla aparte sería duplicar los cinco sitios que ya saben
--  tratar un apartado —inventario, cortes, comparación, attach y las etiquetas—
--  y garantizar que uno se quede atrás. Se distingue con un campo.
--
--  ------------------------------------------------------------
--  Y LA PREVENTA DE LA PURA 90S SE ACABÓ
--  ------------------------------------------------------------
--  Los equipos llegaron: 24 piezas en piso. Se vende desde Precios como
--  cualquier producto. Lo que queda son 9 entregas pendientes, que ahora viven
--  en la misma lista que los traspasos porque para quien entrega son lo mismo.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Qué clase de apartado es, y sus datos propios ───────
-- `tipo` por defecto 'preventa': los 10 que ya existen lo son, y así no hay que
-- rellenarlos a mano.
ALTER TABLE public.apartados
  ADD COLUMN IF NOT EXISTS tipo    text NOT NULL DEFAULT 'preventa',
  -- De qué tienda viene el equipo. Solo para traspasos; en una preventa el
  -- equipo llega del CD y no hay a quién llamar.
  ADD COLUMN IF NOT EXISTS origen  text,
  -- Para cuándo se le prometió al cliente. Es el dato que convierte un retraso
  -- en un aviso: sin fecha no hay forma de saber que algo se pasó.
  ADD COLUMN IF NOT EXISTS promesa date;

ALTER TABLE public.apartados DROP CONSTRAINT IF EXISTS apartados_tipo_valido;
ALTER TABLE public.apartados ADD CONSTRAINT apartados_tipo_valido
  CHECK (tipo IN ('preventa','traspaso'));

COMMENT ON COLUMN public.apartados.promesa IS
  'Fecha prometida al cliente. Si pasa y el apartado sigue sin entregar, el '
  'tablero lo sube arriba y avisa: un cliente esperando sin noticias es lo '
  'unico de este flujo que se convierte en queja.';


-- ── 2 · Guardar, ahora también traspasos ────────────────────
-- Los parámetros nuevos van AL FINAL y con DEFAULT: PostgREST resuelve por
-- nombre, así que una app vieja que no los mande sigue guardando preventas.
DROP FUNCTION IF EXISTS public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text);
DROP FUNCTION IF EXISTS public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date);

CREATE FUNCTION public.apartado_guardar(
  p_store       text,
  p_token       text,
  p_sku         text,
  p_color       text    DEFAULT NULL,   -- producto entero, ver MAPA cadena 2-bis
  p_cliente     text    DEFAULT NULL,
  p_telefono    text    DEFAULT NULL,
  p_precio      numeric DEFAULT NULL,
  p_seguro      boolean DEFAULT false,
  p_vendedor    text    DEFAULT NULL,
  p_transaccion text    DEFAULT NULL,   -- ticket del POS: el enlace con la venta
  p_tipo        text    DEFAULT 'preventa',
  p_origen      text    DEFAULT NULL,   -- de qué tienda viene (solo traspaso)
  p_promesa     date    DEFAULT NULL    -- para cuándo se prometió
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE nuevo bigint; v_tipo text;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;
  IF coalesce(trim(p_cliente),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin cliente');
  END IF;
  IF coalesce(trim(p_sku),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin sku');
  END IF;
  -- Sin vendedor el apartado no cuenta para el attach de nadie ni se sabe quién
  -- lo hizo. El tablero lo toma de la sesión, así que llegar vacío es señal de
  -- que algo va mal, no algo que se deba guardar igual.
  IF coalesce(trim(p_vendedor),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin vendedor');
  END IF;

  v_tipo := CASE WHEN p_tipo = 'traspaso' THEN 'traspaso' ELSE 'preventa' END;

  INSERT INTO public.apartados
    (store_id, sku, color, cliente, telefono, precio, con_seguro,
     vendedor, transaccion, piezas, estatus, tipo, origen, promesa)
  VALUES
    (p_store, trim(p_sku), nullif(trim(coalesce(p_color,'')),''),
     trim(p_cliente), nullif(trim(coalesce(p_telefono,'')),''), p_precio,
     coalesce(p_seguro, false), trim(p_vendedor),
     nullif(trim(coalesce(p_transaccion,'')),''), 1, 'Apartado',
     v_tipo, nullif(trim(coalesce(p_origen,'')),''), p_promesa)
  RETURNING id INTO nuevo;

  RETURN jsonb_build_object('ok', true, 'id', nuevo, 'tipo', v_tipo);

EXCEPTION
  -- El trigger apartado_cabe lanza esto cuando un SKU de preventa llegó a su
  -- cupo. Los traspasos no tienen cupo, así que ni lo miran.
  WHEN raise_exception THEN
    RETURN jsonb_build_object('ok', false, 'error', left(SQLERRM, 140));
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;


-- ── 3 · La lectura devuelve lo nuevo ────────────────────────
DROP FUNCTION IF EXISTS public.apartados_lista(text);

CREATE FUNCTION public.apartados_lista(p_store text)
RETURNS TABLE (id bigint, sku text, cliente text, telefono text,
               piezas integer, con_seguro boolean, estatus text,
               vendedor text, creado_en timestamptz,
               color text, precio numeric, transaccion text,
               serie text, asignado_en timestamptz, entregado_en timestamptz,
               entregado_por text, venta_id bigint,
               tipo text, origen text, promesa date, dias_tarde integer,
               cupo integer, apartadas integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT a.id, a.sku, a.cliente, a.telefono, a.piezas, a.con_seguro,
         a.estatus, a.vendedor, a.creado_en,
         a.color, a.precio, a.transaccion,
         a.serie, a.asignado_en, a.entregado_en, a.entregado_por, a.venta_id,
         a.tipo, a.origen, a.promesa,
         -- Días de retraso, calculados aquí y no en el navegador: el celular
         -- puede tener la fecha mal y esto decide a qué cliente hay que llamar.
         -- Negativo o nulo = todavía no vence.
         CASE WHEN a.promesa IS NOT NULL AND a.estatus NOT IN ('Entregado','Cancelado')
              THEN ((now() AT TIME ZONE 'America/Mexico_City')::date - a.promesa)::int
              ELSE NULL END AS dias_tarde,
         pc.cupo,
         (SELECT coalesce(sum(x.piezas), 0)::int
            FROM public.apartados x
           WHERE x.store_id = a.store_id AND x.sku = a.sku
             AND x.estatus <> 'Cancelado') AS apartadas
  FROM public.apartados a
  LEFT JOIN public.preventa_cupo pc
         ON pc.store_id = a.store_id AND pc.sku = a.sku
  WHERE a.store_id = p_store
  ORDER BY a.creado_en DESC;
$$;


-- ── 4 · Permisos ────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.apartados_lista(text) FROM public;
REVOKE ALL ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.apartados_lista(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apartado_guardar(text,text,text,text,text,text,numeric,boolean,text,text,text,text,date) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Token:  select gas_token from public.tiendas where store_id='1217';
--
--  1) Los 10 que ya existen quedaron como 'preventa':
--       select tipo, count(*) from public.apartados
--        where store_id='1217' group by tipo;
--     -> preventa 10
--
--  2) La lectura trae lo nuevo SIN perder lo viejo:
--       select cliente, transaccion, serie, tipo, origen, promesa, dias_tarde
--         from public.apartados_lista('1217') limit 3;
--     -> `transaccion` y `serie` NO pueden venir vacías.
--
--  3) Sin vendedor se rechaza (antes se guardaba huérfano):
--       select public.apartado_guardar('1217','<TOKEN>','100270542','X','Cliente',
--              null, 8999, false, '', null, 'traspaso');
--     -> {"ok": false, "error": "sin vendedor"}
--
--  4) Un traspaso de prueba, con todo:
--       select public.apartado_guardar('1217','<TOKEN>','100270542',
--              'MatePad 11.5 8/128GB +Teclado','PRUEBA BORRAR','2220000000',
--              8999, false, 'Prueba', '999999', 'traspaso', 'Parque Puebla',
--              current_date - 1);
--     -> ok:true, tipo traspaso
--       select cliente, tipo, origen, promesa, dias_tarde
--         from public.apartados_lista('1217') where cliente='PRUEBA BORRAR';
--     -> dias_tarde = 1  (se prometió ayer y sigue sin entregar)
--
--  5) Y que cuente para el attach de hoy:
--       select * from public.ventas_hoy('1217');
--     -> aparece "Prueba" con sin_seguro = 1
--
--  6) Borrar la prueba:
--       delete from public.apartados where cliente = 'PRUEBA BORRAR';
-- ============================================================


-- ========== supabase_attach_preventa.sql ==========

-- ============================================================
--  El Assurant del día no cuenta las entregas de preventa
--  8-ago-2026
-- ============================================================
--
--  Detectado en piso el mismo día de la primera entrega: sin haber vendido nada,
--  el tablero ya marcaba «1 venta sin seguro» y el attach del día caía a 0 %.
--
--  La causa es la misma que la del inventario: **una entrega de preventa no es
--  una venta de hoy**. El cliente pagó en julio, y con ella se le vendió —o no—
--  su seguro. Ese attach ya contó el día del apartado, en el reporte de julio.
--  Volver a contarlo hoy es medir dos veces la misma operación.
--
--  Y hace daño en las dos direcciones:
--    · una entrega SIN seguro hunde el attach de un día en el que quizá no se
--      ha vendido nada más — con 9 apartados pendientes, nueve golpes gratis
--    · una entrega CON seguro lo infla igual de falsamente
--
--  El attach es el KPI que se reporta a Demetrio con meta del 25 %. Un número
--  que se mueve por entregas de mercancía vieja no sirve para decidir nada.
--
--  Mismo filtro que `inventario_vivo` y `cargar_cortes`: fuera las ventas que
--  son la entrega de un apartado.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================

CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT v.vendedor,
         count(*) FILTER (WHERE v.con_seguro)         AS con_seguro,
         count(*) FILTER (WHERE NOT v.con_seguro)     AS sin_seguro
  FROM public.ventas v
  WHERE v.store_id = p_store
    AND v.con_seguro IS NOT NULL
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
        = (now() AT TIME ZONE 'America/Mexico_City')::date
    -- Las entregas de preventa NO son ventas de hoy: se cobraron el día del
    -- apartado y su seguro ya contó entonces. Mismo criterio que el inventario.
    AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
  GROUP BY v.vendedor;
$$;

REVOKE ALL ON FUNCTION public.ventas_hoy(text) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--  Hoy hay una entrega (Mayra hizamar, sin seguro) y ninguna venta normal:
--
--    select * from public.ventas_hoy('1217');
--      -> 0 filas.  Antes devolvía a "Maria" con sin_seguro = 1.
--
--  Que la venta SIGUE existiendo, solo que no cuenta para el attach del día:
--
--    select v.serie, v.vendedor, v.con_seguro, a.cliente
--      from public.ventas v join public.apartados a on a.venta_id = v.id
--     where v.store_id = '1217';
--      -> la venta de la entrega, con su serie y su vendedor.
--
--  Y que una venta normal SÍ cuenta: capturar una en la app y volver a mirar.
-- ============================================================


-- ========== supabase_attach_apartados.sql ==========

-- ============================================================
--  Un apartado cuenta para el attach del día en que se paga
--  8-ago-2026
-- ============================================================
--
--  UNA PREVENTA ES UNA VENTA COBRADA. Lo que pasa es que el día del cobro no hay
--  equipo, ni serie, ni caja — así que no se captura en la app. Y como no se
--  captura, el Assurant del tablero nunca la vio: ni ese día ni ninguno.
--
--  Medido sobre los 10 apartados vivos: 10 ventas, 3 con seguro, repartidas en
--  nueve días. Ninguna contó. El 31-jul se vendió un equipo de $22.999 CON
--  seguro y el tablero de ese día lo ignoró; en Sonar sí aparece.
--
--  Así que el attach del tablero venía quedándose corto justo los días de
--  preventa, que son los de venta más grande.
--
--  Esto NO contradice lo de `supabase_attach_preventa.sql`, lo completa:
--    · el día del APARTADO   -> cuenta (es cuando se cobra y se vende el seguro)
--    · el día de la ENTREGA  -> no cuenta (el equipo solo cambia de manos)
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · Los nombres viejos, a su forma oficial ──────────────
-- Hasta hoy el vendedor del apartado se tecleaba a mano y quedaron nombres
-- sueltos —"Maria", "Jorge"—, mientras las ventas guardan el completo desde la
-- sesión. Sumar unos con otros pondría a la misma persona dos veces en el
-- leaderboard, como si fueran dos.
--
-- Desde v149 el tablero lo toma de la sesión y ya no se puede teclear, así que
-- esto es solo para los que ya existen. Se casa por PRIMER NOMBRE contra la
-- tabla de empleados, que es la lista oficial.
UPDATE public.apartados a
   SET vendedor = e.nombre
  FROM public.empleados e
 WHERE a.store_id = e.store_id
   AND a.vendedor IS NOT NULL
   AND a.vendedor <> e.nombre
   -- primer nombre igual, sin acentos ni mayúsculas de por medio
   AND lower(split_part(trim(a.vendedor), ' ', 1)) = lower(split_part(trim(e.nombre), ' ', 1))
   -- y que no haya dos empleados con ese mismo primer nombre: si los hubiera,
   -- adivinar cuál es peor que dejarlo como está
   AND (SELECT count(*) FROM public.empleados e2
         WHERE e2.store_id = a.store_id
           AND lower(split_part(trim(e2.nombre), ' ', 1))
             = lower(split_part(trim(a.vendedor), ' ', 1))) = 1;


-- ── 2 · El attach del día suma las ventas Y los apartados ───
CREATE OR REPLACE FUNCTION public.ventas_hoy(p_store text)
RETURNS TABLE (vendedor text, con_seguro bigint, sin_seguro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH hoy AS (
    -- Ventas capturadas en la app, menos las entregas de preventa: ésas se
    -- cobraron semanas antes y ya contaron el día de su apartado.
    SELECT v.vendedor, v.con_seguro
    FROM public.ventas v
    WHERE v.store_id = p_store
      AND v.con_seguro IS NOT NULL
      AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date
          = (now() AT TIME ZONE 'America/Mexico_City')::date
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)

    UNION ALL

    -- Y los apartados pagados HOY: son ventas cobradas aunque el equipo no
    -- exista todavía, con su seguro o sin él. Los cancelados no cuentan: esa
    -- venta se deshizo.
    SELECT a.vendedor, a.con_seguro
    FROM public.apartados a
    WHERE a.store_id = p_store
      AND a.estatus <> 'Cancelado'
      AND a.vendedor IS NOT NULL
      AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date
          = (now() AT TIME ZONE 'America/Mexico_City')::date
  )
  SELECT h.vendedor,
         count(*) FILTER (WHERE h.con_seguro)     AS con_seguro,
         count(*) FILTER (WHERE NOT h.con_seguro) AS sin_seguro
  FROM hoy h
  GROUP BY h.vendedor;
$$;

REVOKE ALL ON FUNCTION public.ventas_hoy(text) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_hoy(text) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Los nombres quedaron completos:
--       select distinct vendedor from public.apartados where store_id='1217';
--     -> nombres completos. Si queda alguno corto, es que ese empleado no está
--        en la tabla `empleados` o hay dos con el mismo primer nombre.
--
--  2) Hoy solo hay una entrega y ninguna venta ni apartado nuevo:
--       select * from public.ventas_hoy('1217');
--     -> 0 filas. La entrega sigue sin contar.
--
--  3) La prueba de verdad — apartar algo hoy desde el tablero y volver a mirar:
--     debe aparecer tu nombre con su con_seguro / sin_seguro, y el Assurant del
--     día debe moverse.
--
--  4) Que un apartado cancelado NO cuente:
--       cancelarlo desde el tablero y comprobar que desaparece de ventas_hoy.
-- ============================================================


-- ========== supabase_puesto_en_sesion.sql ==========

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


--------------------------------------------------------------
--  ETAPA: Lo ultimo de agosto
--------------------------------------------------------------


-- ========== supabase_venta_editar.sql ==========

-- ============================================================
--  CORREGIR UNA VENTA CAPTURADA
--  17-ago-2026
-- ============================================================
--
--  Lo último que se hacía en la hoja y desde el 17-ago no se hacía en ningún
--  lado: corregir una captura equivocada. La hoja dejó de recibir ventas (fase
--  6) y con ella se fue la única forma de arreglar un seguro mal marcado o un
--  SKU mal tecleado.
--
--  ------------------------------------------------------------
--  LO QUE MUEVE CADA CAMPO — leer antes de tocar esto
--  ------------------------------------------------------------
--    seguro       -> el Assurant del día (el KPI con meta del 25 %)
--    vendedor     -> comisiones y leaderboard
--    precio       -> comisiones
--    descripcion  -> nada, es cosmético
--    serie        -> choca con UNIQUE (store_id, serie, dia_venta) si se repite
--    fecha        -> el día de la venta. NO mueve stock: `inventario_vivo`
--                    cuenta todas las ventas del SKU sin filtrar por fecha
--    sku          -> EL STOCK DE DOS PRODUCTOS. Ver abajo.
--
--  ------------------------------------------------------------
--  POR QUÉ CAMBIAR EL SKU NECESITA TOCAR EL CORTE
--  ------------------------------------------------------------
--  El stock se despeja así:
--
--      stock = onhand − (ventas totales del SKU − ventas contadas en el corte)
--
--  `inventario_corte` es una FOTO de cuántas ventas había por SKU cuando se
--  subió el informe. Si una venta ya estaba en esa foto con el SKU equivocado y
--  se le cambia el SKU sin más:
--
--    · el SKU correcto resta una pieza que el On Hand del informe YA había
--      descontado (el POS sabía la verdad) -> muestra una de menos
--    · el SKU equivocado queda con total < corte. `greatest(0,…)` lo esconde,
--      así que no se ve nada raro — hasta que se venda otra pieza de verdad,
--      que entonces NO se descontará
--
--  Ninguno de los dos da error. Es el mismo error que las entregas de preventa
--  del 7-ago: restar dos veces la misma pieza.
--
--  El arreglo es mover la unidad EN EL CORTE junto con la venta: −1 al corte
--  del SKU viejo y +1 al del nuevo, en la misma transacción. Así `total − corte`
--  queda intacto para los dos, que es lo correcto: corregir una etiqueta no
--  cambia cuántas cajas hay en bodega.
--
--  Se hace para los DOS cortes (onhand y exhibicion): los dos cuentan ventas.
--
--  ⚠️ Límite conocido: se decide con `vendida_en < tomado_en`. Una venta
--  capturada tarde con fecha vieja no estaba en la foto aunque su fecha lo
--  parezca. Es raro y el desvío es de una pieza hasta el informe siguiente,
--  que reemplaza el On Hand completo (ver cadena 5 del MAPA: el error no se
--  acumula entre días).
--
--  ------------------------------------------------------------
--  QUÉ IMPONE ESTO Y QUÉ NO — sin adornos
--  ------------------------------------------------------------
--  `escritura_ok_` valida el TOKEN DE TIENDA, que es el mismo para todos los
--  que entran. O sea que por sí solo no distingue un gerente de un asesor.
--
--  Por eso se pide `p_quien` (el número de empleado) y se comprueba su puesto
--  contra la tabla. Eso SÍ es una barrera de servidor... salvo en un caso: el
--  gerente dueño entra con el correo de la tienda y NO tiene ficha de empleado
--  (ver cadena 1-bis del MAPA), así que `p_quien` vacío tiene que seguir
--  pasando. Quien manipule la llamada a mano puede mandarlo vacío.
--
--  No se disimula: es el mismo nivel de barrera que Resurtir —se le esconde al
--  asesor, no se le impide— y lo que de verdad protege aquí es que TODA edición
--  queda registrada en `ventas_ediciones` con el antes y el después. Una
--  corrección mal hecha se puede ver y deshacer; eso es lo que no había cuando
--  esto se hacía a mano en la hoja.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · El rastro de quién corrigió qué ─────────────────────
-- Editar una venta reescribe historia y mueve dinero (comisiones). Sin esto,
-- una corrección equivocada es indistinguible de la realidad.
CREATE TABLE IF NOT EXISTS public.ventas_ediciones (
  id         bigserial   PRIMARY KEY,
  store_id   text        NOT NULL REFERENCES public.tiendas(store_id) ON DELETE CASCADE,
  venta_id   bigint,
  captura_id text,
  quien      text,                    -- empno, o vacío si fue por sesión de gerente
  editado_en timestamptz NOT NULL DEFAULT now(),
  antes      jsonb       NOT NULL,
  despues    jsonb       NOT NULL
);

ALTER TABLE public.ventas_ediciones ENABLE ROW LEVEL SECURITY;
-- Sin políticas: no se llega por REST. Solo escribe la función, que es DEFINER.

CREATE INDEX IF NOT EXISTS ventas_ediciones_dia
  ON public.ventas_ediciones (store_id, editado_en DESC);

COMMENT ON TABLE public.ventas_ediciones IS
  'Auditoria de correcciones de ventas. Una fila por edicion, con el antes y el '
  'despues completos. Es lo que permite deshacer una correccion equivocada.';


-- ── 2 · ¿Esta persona lleva la tienda? ──────────────────────
-- Mismo criterio que `PUESTOS_GESTION` en tablero.html: gerente y subgerente.
-- Vive aquí y no repetido en cada función para que no haya dos ideas de "quién
-- manda" que puedan separarse.
CREATE OR REPLACE FUNCTION public.puede_gestionar_(p_store text, p_empno text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.empleados e
     WHERE e.store_id = p_store
       AND e.empno    = p_empno
       AND e.activo   = true
       AND (lower(coalesce(e.puesto,'')) LIKE 'gerente%'
         OR lower(coalesce(e.puesto,'')) LIKE 'subgerente%')
  );
$$;

REVOKE ALL ON FUNCTION public.puede_gestionar_(text,text) FROM public, anon, authenticated;


-- ── 3 · Corregir la venta ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.venta_editar(
  p_store      text,
  p_token      text,
  p_captura_id text,
  p_serie      text,
  p_sku        text,
  p_desc       text,
  p_precio     numeric,
  p_vendedor   text,
  p_seguro     boolean,
  p_fecha      date,
  p_quien      text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v      public.ventas%ROWTYPE;
  antes  jsonb;
  despues jsonb;
  v_hora time;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no_autorizado');
  END IF;

  -- Con número de empleado se comprueba el puesto; sin él es la sesión del
  -- gerente dueño, que no tiene ficha (cadena 1-bis del MAPA).
  IF coalesce(trim(p_quien),'') <> '' AND NOT public.puede_gestionar_(p_store, trim(p_quien)) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'solo el gerente o el subgerente pueden corregir una venta');
  END IF;

  IF coalesce(trim(p_captura_id),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin id');
  END IF;
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'la serie no puede quedar vacía');
  END IF;

  SELECT * INTO v FROM public.ventas
   WHERE store_id = p_store AND captura_id = trim(p_captura_id);

  IF NOT FOUND THEN
    -- Puede pasar de verdad: la captura quedó en la cola del teléfono y todavía
    -- no ha subido. Decirlo, en vez de "no se pudo guardar".
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta todavía no ha llegado a la nube: espera a que suba y vuelve a intentarlo');
  END IF;

  -- Igual que en `venta_eliminar`: una entrega de preventa no se toca por aquí.
  -- Su venta la creó `apartado_entregar` y el apartado la sigue apuntando.
  IF EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id) THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'esa venta es la entrega de un apartado: corrígela desde Preventa');
  END IF;

  antes := jsonb_build_object('serie', v.serie, 'sku', v.sku,
             'descripcion', v.descripcion, 'precio', v.precio,
             'vendedor', v.vendedor, 'con_seguro', v.con_seguro,
             'dia_venta', v.dia_venta, 'de_exhibicion', v.de_exhibicion);

  /* EL CORTE, ANTES DEL UPDATE. Ver la cabecera: si esta venta ya estaba
     contada en la foto del informe con el SKU viejo, hay que mover esa unidad
     también, o el stock de los dos productos queda mal sin avisar. */
  IF trim(coalesce(p_sku,'')) IS DISTINCT FROM coalesce(v.sku,'') THEN
    UPDATE public.inventario_corte
       SET vendidas = greatest(0, vendidas - 1)
     WHERE store_id = p_store AND sku = v.sku
       AND v.vendida_en < tomado_en;

    UPDATE public.inventario_corte
       SET vendidas = vendidas + 1
     WHERE store_id = p_store AND sku = trim(p_sku)
       AND v.vendida_en < tomado_en;
  END IF;

  -- La hora se conserva: solo se mueve el día. Cambiar la hora sin querer
  -- movería la venta de lado respecto a un corte.
  v_hora := (v.vendida_en AT TIME ZONE 'America/Mexico_City')::time;

  BEGIN
    UPDATE public.ventas
       SET serie       = trim(p_serie),
           sku         = trim(coalesce(p_sku, sku)),
           descripcion = nullif(trim(coalesce(p_desc,'')), ''),
           precio      = p_precio,
           vendedor    = coalesce(nullif(trim(coalesce(p_vendedor,'')),''), vendedor),
           con_seguro  = p_seguro,
           vendida_en  = CASE
                           WHEN p_fecha IS NULL OR p_fecha = v.dia_venta THEN vendida_en
                           -- se rearma en hora de México y se guarda como timestamptz
                           ELSE ((p_fecha + v_hora) AT TIME ZONE 'America/Mexico_City')
                         END
     WHERE id = v.id;
  EXCEPTION WHEN unique_violation THEN
    /* Esa serie ya está vendida ese día. NO es un fallo técnico que haya que
       traducir: casi siempre significa que la venta se capturó dos veces, que
       es justo lo que la restricción existe para impedir. */
    RETURN jsonb_build_object('ok', false,
      'error', 'ya hay otra venta con esa serie ese mismo día');
  END;

  SELECT * INTO v FROM public.ventas WHERE id = v.id;
  despues := jsonb_build_object('serie', v.serie, 'sku', v.sku,
               'descripcion', v.descripcion, 'precio', v.precio,
               'vendedor', v.vendedor, 'con_seguro', v.con_seguro,
               'dia_venta', v.dia_venta, 'de_exhibicion', v.de_exhibicion);

  INSERT INTO public.ventas_ediciones
    (store_id, venta_id, captura_id, quien, antes, despues)
  VALUES (p_store, v.id, trim(p_captura_id), nullif(trim(coalesce(p_quien,'')),''),
          antes, despues);

  RETURN jsonb_build_object('ok', true, 'antes', antes, 'despues', despues,
                            'cambio_sku', (antes->>'sku') IS DISTINCT FROM (despues->>'sku'));
END $fn$;

/* NO se puede cambiar `de_exhibicion` desde aqui, y es deliberado.
   Moverla de bodega a aparador (o al reves) cambia de que contador descuenta la
   pieza, asi que habria que mover tambien la unidad en LOS DOS cortes — igual
   que se hace arriba con el SKU. Sin ese ajuste, corregir la procedencia
   descuadraria el stock en silencio, que es justo lo que este archivo evita.

   El valor SI se guarda en la auditoria (antes/despues), asi que si una venta
   se marco mal se ve. Corregirla hoy es borrar la captura y volver a hacerla
   con la casilla correcta: la app deshace las dos cosas bien.

   Si algun dia hace falta, es el mismo patron que el bloque del SKU. */
REVOKE ALL ON FUNCTION public.venta_editar(text,text,text,text,text,text,numeric,text,boolean,date,text)
  FROM public;
GRANT EXECUTE ON FUNCTION public.venta_editar(text,text,text,text,text,text,numeric,text,boolean,date,text)
  TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Que la tabla de auditoría existe y está vacía:
--       select count(*) from public.ventas_ediciones;
--
--  2) Que el puesto se lee bien (tiene que dar true para el subgerente):
--       select public.puede_gestionar_('1217','<empno-subgerente>');
--
--  3) El caso que importa, con una venta de prueba: capturar una en la app con
--     un SKU equivocado, anotar el stock de los DOS productos en el tablero,
--     corregir el SKU y comprobar que el stock de los dos queda como estaba
--     antes de la captura. Si el corte no se ajustara, uno mostraría una pieza
--     de menos.
--
--  4) Ver las correcciones hechas:
--       select editado_en, quien, captura_id, antes, despues
--         from public.ventas_ediciones
--        where store_id = '1217' order by editado_en desc limit 20;
--
--  5) Deshacer una corrección equivocada: la fila de arriba trae el `antes`
--     completo, así que se vuelve a llamar a venta_editar con esos valores.
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================


-- ========== supabase_venta_exhibicion.sql ==========

-- ============================================================
--  VENDER LA PIEZA DE EXHIBICIÓN DE UN EOL
--  17-ago-2026
-- ============================================================
--
--  ------------------------------------------------------------
--  EL HUECO
--  ------------------------------------------------------------
--  `eol_precio_venta` exige `stock = 0`, así que el 50 % solo aparece cuando ya
--  NO queda nada en bodega. Un producto EOL con dos cajas nuevas más la de
--  aparador se cobra entero — incluida la de aparador, que es la que va al 50 %.
--
--  Y hay una segunda mitad que no se ve. `inventario_vivo` imputa TODA venta a
--  bodega, y solo el excedente a exhibición. Vender la de aparador teniendo
--  cajas nuevas dejaba esto:
--
--      bodega       2 cajas intactas   ->  el tablero decía 1
--      exhibición   vacía, ya se fue   ->  el tablero decía 1
--
--  Se equivoca en los dos sentidos a la vez y no da error. El de bodega se
--  corrige solo con el informe del día siguiente (cadena 5: el error no se
--  acumula). **El de exhibición no**: la exhibición se sube solo de vez en
--  cuando, así que ese "1 en piso" puede quedarse semanas — y es justo el que
--  hace que el tablero ofrezca al 50 % una pieza que ya no existe.
--
--  ------------------------------------------------------------
--  CÓMO SE ARREGLA
--  ------------------------------------------------------------
--  Una venta puede decir de dónde salió la pieza: `ventas.de_exhibicion`.
--  Las de bodega descuentan del On Hand; las de exhibición, del aparador.
--
--  TODO EL HISTÓRICO QUEDA EN `false`, y es correcto: hasta hoy no se podía
--  marcar, así que ninguna venta vieja era declaradamente de exhibición.
--
--  ------------------------------------------------------------
--  LO QUE NO SE PUEDE PERDER AL CAMBIARLO
--  ------------------------------------------------------------
--  El modelo viejo NO era arbitrario: decía que las ventas por encima del On
--  Hand se habían comido la exhibición. Eso sigue siendo cierto para las ventas
--  no marcadas, y si se tirara, el tablero volvería a ofrecer al 50 % piezas de
--  piso ya vendidas — una regresión silenciosa sobre datos reales.
--
--  Por eso `exh_vendida` suma las DOS cosas:
--
--      las marcadas de exhibición   +   el excedente sobre el On Hand
--      (lo nuevo)                       (lo que ya hacía, conservado)
--
--  ------------------------------------------------------------
--  Y LOS CORTES SE SEPARAN
--  ------------------------------------------------------------
--  El corte de On Hand pasa a contar solo ventas de bodega, y el de exhibición
--  solo las de exhibición. Los cortes YA GUARDADOS se tomaron con el total, y
--  siguen siendo correctos para On Hand porque todo el histórico es de bodega.
--
--  ------------------------------------------------------------
--  CÓMO SE APLICA — son DOS archivos, en este orden
--  ------------------------------------------------------------
--    1) ESTE archivo (define `corte_tomar_`, que el otro necesita)
--    2) `supabase_cargas_admin.sql` completo, otra vez: ahí viven
--       `carga_catalogo` y `carga_exhibicion`, ya cambiadas para usarlo
--
--  Al revés falla: el segundo llamaría a una función que aún no existe.
--
--  Los dos son idempotentes. Antes de empezar, guardar la foto del inventario
--  para poder comprobar que nada se movió (punto 2 de COMPROBAR, al final).
-- ============================================================


-- ── 1 · De dónde salió la pieza ─────────────────────────────
ALTER TABLE public.ventas
  ADD COLUMN IF NOT EXISTS de_exhibicion boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.ventas.de_exhibicion IS
  'true = se vendio la pieza del aparador (EOL al 50%). Descuenta de exhibicion '
  'y NO del On Hand. Todo lo anterior al 17-ago-2026 es false: no se podia marcar.';


-- ── 2 · El inventario, con las dos procedencias ─────────────
CREATE OR REPLACE FUNCTION public.inventario_vivo(p_store text)
RETURNS TABLE (
  sku text, descripcion text, precio numeric,
  onhand integer, vendido integer, stock integer,
  exhibicion integer, exh_vendida integer
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH bodega AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND NOT v.de_exhibicion
      -- Las entregas de preventa NO cuentan: el POS ya descontó esas piezas el
      -- día que el cliente pagó el apartado. Mismo filtro que en los cortes,
      -- en `comparar_ventas` y en `ventas_hoy` — si se toca, se tocan los cuatro.
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ),
  aparador AS (
    SELECT v.sku, count(*)::int AS total
    FROM public.ventas v
    WHERE v.store_id = p_store AND v.sku IS NOT NULL AND v.sku <> ''
      AND v.de_exhibicion
      AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
    GROUP BY v.sku
  ),
  base AS (
    SELECT
      c.sku, c.descripcion, c.precio,
      coalesce(i.onhand, 0)     AS onhand,
      coalesce(i.exhibicion, 0) AS exhibicion,
      greatest(0, coalesce(b.total,0) - coalesce(co.vendidas,0))::int AS vendido,
      greatest(0, coalesce(a.total,0) - coalesce(ce.vendidas,0))::int AS exh_marcada
    FROM public.catalogo c
    LEFT JOIN public.inventario i ON i.store_id = c.store_id AND i.sku = c.sku
    LEFT JOIN bodega   b  ON b.sku  = c.sku
    LEFT JOIN aparador a  ON a.sku  = c.sku
    LEFT JOIN public.inventario_corte co
           ON co.store_id = c.store_id AND co.sku = c.sku AND co.tipo = 'onhand'
    LEFT JOIN public.inventario_corte ce
           ON ce.store_id = c.store_id AND ce.sku = c.sku AND ce.tipo = 'exhibicion'
    WHERE c.store_id = p_store
  )
  SELECT
    sku, descripcion, precio,
    onhand,
    vendido,
    -- stock vendible = solo almacén. La exhibición NO se suma ni se resta.
    greatest(0, onhand - vendido)::int AS stock,
    exhibicion,
    /* Las marcadas de exhibición MÁS el excedente sobre el On Hand. Lo segundo
       es lo que ya hacía el modelo viejo y se conserva a propósito: sin ello,
       las ventas que se comieron una pieza de piso ANTES de que existiera la
       marca volverían a aparecer como piezas disponibles. */
    (exh_marcada + greatest(0, vendido - onhand))::int AS exh_vendida
  FROM base;
$$;


-- ── 3 · Los cortes, cada uno con lo suyo ────────────────────
-- El de On Hand cuenta ventas de BODEGA; el de exhibición, las del APARADOR.
-- Sin esto, el corte de exhibición seguiría guardando el total y `exh_vendida`
-- daría siempre cero: el aparador se vería lleno para siempre.
CREATE OR REPLACE FUNCTION public.corte_tomar_(p_store text, p_tipo text, p_sku text)
RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT count(*)::int FROM public.ventas v
   WHERE v.store_id = p_store AND v.sku = p_sku
     AND v.de_exhibicion = (p_tipo = 'exhibicion')
     AND NOT EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id);
$$;

REVOKE ALL ON FUNCTION public.corte_tomar_(text,text,text) FROM public, anon, authenticated;

COMMENT ON FUNCTION public.corte_tomar_(text,text,text) IS
  'El conteo que va al corte, segun el tipo. Existe para que carga_catalogo y '
  'carga_exhibicion no tengan cada una su propia idea de que ventas contar.';


-- ── 3-bis · Que las cargas tomen el corte que les toca ──────
--
-- ESTO ES LO QUE HACE QUE LO DEMÁS FUNCIONE, y era fácil de olvidar. Las dos
-- cargas cuentan hoy TODAS las ventas del SKU. Si se quedan así, el corte de
-- exhibición seguiría guardando el total, `exh_marcada` daría siempre cero por
-- el `greatest(0, …)` y **el aparador no bajaría nunca**: la marca nueva no
-- serviría de nada, sin dar un solo error.
--
-- Y el de On Hand al revés: si contara también las ventas de aparador, quedaría
-- alto y la siguiente venta de bodega no descontaría stock.
--
-- LAS DOS CARGAS SE ARREGLAN EN SU PROPIO ARCHIVO, no aquí.
-- `carga_catalogo` y `carga_exhibicion` viven en `supabase_cargas_admin.sql` y
-- ya quedaron cambiadas ahí para usar `corte_tomar_`. Copiarlas a este archivo
-- habría dejado dos versiones de la carga más delicada del sistema, y una se
-- quedaría atrás: es justo el fallo que este archivo viene a evitar en el
-- inventario. POR ESO HAY QUE PEGAR LOS DOS ARCHIVOS — ver "CÓMO SE APLICA".

-- Los cortes de EXHIBICIÓN ya guardados traen el total de ventas, que con el
-- modelo nuevo dejaría `exh_marcada` clavado en cero hasta la siguiente subida
-- de piso. Se recalculan una vez, aquí: hoy todas las ventas son de bodega, así
-- que quedan en cero — que es la verdad, no ha habido ventas de aparador.
UPDATE public.inventario_corte c
   SET vendidas = public.corte_tomar_(c.store_id, 'exhibicion', c.sku)
 WHERE c.tipo = 'exhibicion';


-- ── 4 · El precio de la pieza de piso ───────────────────────
--
-- Cambia la FORMA: ahora dice además si el 50 % se aplica solo o si hace falta
-- que el asesor marque que está vendiendo la de exhibición.
--
--   solo_exhibicion = true   -> no queda bodega: es la única pieza que hay, y
--                               el precio se pone automático (lo de siempre)
--   solo_exhibicion = false  -> hay cajas nuevas Y una de piso. El 50 % SOLO si
--                               el asesor lo marca; si no, precio normal
--
-- Quitar el filtro de stock sin este campo habría puesto al 50 % todos los EOL
-- con bodega, o sea regalando producto nuevo.
DROP FUNCTION IF EXISTS public.eol_precio_venta(text);

CREATE OR REPLACE FUNCTION public.eol_precio_venta(p_store text)
RETURNS TABLE (sku text, precio50 numeric, solo_exhibicion boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT iv.sku,
         round(coalesce(nullif(e.precio, 0), iv.precio) / 2.0, 2) AS precio50,
         (iv.stock = 0)                                           AS solo_exhibicion
  FROM public.inventario_vivo(p_store) iv
  JOIN public.eol e ON e.store_id = p_store AND e.sku = iv.sku AND NOT e.pausado
  -- Que quede pieza de piso de verdad. Sin esto se ofrecería al 50% un aparador
  -- vacío, que es mandar al asesor a buscar una caja que no está.
  WHERE greatest(0, iv.exhibicion - iv.exh_vendida) > 0
    AND coalesce(nullif(e.precio, 0), iv.precio) > 0;
$$;

REVOKE ALL ON FUNCTION public.eol_precio_venta(text) FROM public;
GRANT EXECUTE ON FUNCTION public.eol_precio_venta(text) TO anon, authenticated;


-- ── 5 · Guardar la venta sabiendo de dónde salió ────────────
-- La firma cambia, así que DROP explícito: `CREATE OR REPLACE` dejaría las dos
-- y PostgREST respondería PGRST203 — o sea, dejaría de guardar ventas. Ya pasó
-- con esta misma función.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text);
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,
  p_hora       text    DEFAULT NULL,
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL,
  -- Con DEFAULT para que una app que aún no se ha actualizado siga guardando.
  p_de_exhibicion boolean DEFAULT false
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  -- La fecha llega como d/M/yyyy (así la escribía la hoja y así la manda la app).
  m := regexp_match(coalesce(p_fecha,''), '^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$');
  IF m IS NOT NULL THEN
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    m := regexp_match(coalesce(p_hora,''), '^\s*(\d{1,2}):(\d{2})\s*([ap])');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF lower(m[3]) = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF lower(m[3]) = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := make_timestamp(v_a, v_m, v_d, v_h, v_min, 0) AT TIME ZONE 'America/Mexico_City';
  ELSE
    v_cuando := now();
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id, de_exhibicion)
  VALUES (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
          nullif(trim(coalesce(p_desc,'')),''), p_precio,
          coalesce(nullif(trim(coalesce(p_vendedor,'')),''), '(sin nombre)'),
          p_seguro, nullif(trim(coalesce(p_foto_url,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          coalesce(p_de_exhibicion, false))
  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING
  RETURNING id INTO nuevo;

  IF nuevo IS NULL THEN
    -- Reintentar es seguro: la misma serie el mismo día ya está guardada.
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  END IF;

  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean)
  TO anon, authenticated;


-- ============================================================
--  COMPROBAR — el punto 3 es el que de verdad importa
-- ============================================================
--
--  1) La columna existe y todo el histórico es de bodega:
--       select de_exhibicion, count(*) from public.ventas
--        where store_id='1217' group by 1;
--     Esperado: una sola fila, false.
--
--  2) El inventario NO cambió al aplicar esto. Con cero ventas marcadas, la
--     fórmula nueva tiene que dar exactamente lo mismo que la vieja. Antes de
--     pegar el archivo, guardar una foto:
--       create table _inv_antes as select * from public.inventario_vivo('1217');
--     y después comparar:
--       select * from public.inventario_vivo('1217') n
--         join _inv_antes a using (sku)
--        where n.stock <> a.stock or n.exh_vendida <> a.exh_vendida;
--     Esperado: CERO filas. Si sale alguna, no seguir.
--       drop table _inv_antes;   -- al terminar
--
--  3) La prueba de verdad, en piso, con un EOL que tenga bodega Y aparador:
--       · anotar stock y exhibición en el tablero
--       · capturar la venta marcando «es la pieza de exhibición»
--       · el stock de bodega tiene que quedar IGUAL
--       · la exhibición tiene que bajar una
--     Sin la marca, la venta descuenta de bodega, como siempre.
--
--  4) Qué SKU ofrecen hoy pieza de piso, y cuáles automáticamente:
--       select * from public.eol_precio_venta('1217');
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================


-- ========== supabase_ventas_detalle_entrega.sql ==========

-- ============================================================
--  DISTINGUIR LAS ENTREGAS EN «VENTAS DEL DÍA»
--  17-ago-2026  ·  ampliado con `cobrado_en` y con los COBROS del dia
-- ============================================================
--
--  En la lista de Ventas del día, una entrega de preventa o de traspaso se ve
--  hoy exactamente igual que una venta normal. Y no lo es:
--
--    · el cliente PAGÓ semanas antes — el ticket del POS es de otro día, y a
--      menudo de otro MES (ya está en el MAPA, cadena 6-ter)
--    · NO cuenta para el Assurant del día ni descuenta stock, porque ambas
--      cosas ya pasaron el día del apartado
--    · NO se puede corregir con el ✏️: la venta la creó `apartado_entregar` y
--      el apartado la sigue apuntando
--
--  O sea que quien cuadra la caja contra el POS ve renglones que no va a
--  encontrar, sin ninguna pista de por qué. La distinción no es decorativa: es
--  la explicación de las tres cosas de arriba.
--
--  Se añade `entrega` a `ventas_detalle`: NULL para una venta normal,
--  'preventa' o 'traspaso' para las que salen de un apartado.
--
--  ------------------------------------------------------------
--  Y LOS APARTADOS COBRADOS ESE DÍA, QUE FALTABAN
--  ------------------------------------------------------------
--  Esto no es una comodidad: es un descuadre que ya existía. `ventas_hoy` —el
--  Assurant del día— SÍ cuenta los apartados pagados hoy, porque un apartado es
--  una venta cobrada aunque el equipo no exista todavía. Pero la lista de
--  Ventas del día no los enseñaba.
--
--  O sea que el día que se cobra un apartado, el porcentaje sube y las filas de
--  abajo no lo explican. Es exactamente lo que se arregló el 8-ago-2026 con el
--  attach manual: la suma de las filas tiene que dar el total, y poder
--  comprobarse de un vistazo.
--
--  `clase` dice qué es cada renglón:
--
--    'venta'    capturada en la app, con su equipo y su serie
--    'entrega'  sale de un apartado: se cobró otro día (ver `cobrado_en`)
--    'cobro'    apartado pagado ESE día. Todavía no hay equipo ni serie.
--
--  Los cancelados no salen: esa venta se deshizo. Mismo criterio que
--  `ventas_hoy`, para que las dos cuenten lo mismo.
--
--  ------------------------------------------------------------
--  POR QUÉ HAY QUE DROPEAR
--  ------------------------------------------------------------
--  Cambia el RETURNS TABLE, y Postgres no deja reemplazar el tipo de retorno de
--  una función con `CREATE OR REPLACE`. Sin el DROP, el pegado falla con
--  "cannot change return type of existing function" — que al menos avisa; lo
--  peligroso sería una firma distinta, que crearía una sobrecarga y PostgREST
--  respondería PGRST203.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean,
               -- NULL = venta normal. 'preventa' / 'traspaso' = sale de un apartado.
               entrega text,
               -- Cuando se COBRO el apartado. NULL en una venta normal, porque
               -- ahi cobro y entrega son el mismo momento y ya lo dice vendida_en.
               cobrado_en timestamptz,
               -- 'venta' | 'entrega' | 'cobro'. Ver la cabecera.
               clase text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH dia AS (
    SELECT coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date) AS d
  )
  -- 1 · Lo que pasó por la app, y las entregas de apartado
  SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
         v.vendida_en, v.captura_id,
         EXISTS (SELECT 1 FROM public.venta_fotos f
                  WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id),
         /* El tipo del apartado que generó esta venta, si lo hay. Es el MISMO
            vínculo que usan `inventario_vivo`, `ventas_hoy`, `cargar_cortes` y
            `comparar_ventas` para excluirlas: `a.venta_id = v.id`. Aquí no se
            excluye nada — se enseña, que es justo lo que faltaba. */
         (SELECT a.tipo      FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1),
         /* La fecha del cobro. Es la que dice en QUE CORTE esta el ticket: el
            cliente pago semanas antes, a veces en otro mes, asi que buscarlo en
            el de hoy es no encontrarlo. Sale del apartado, no de la venta —
            `vendida_en` es el dia de la ENTREGA. */
         (SELECT a.creado_en FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1),
         CASE WHEN EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
              THEN 'entrega' ELSE 'venta' END
  FROM public.ventas v
  CROSS JOIN dia
  WHERE v.store_id = p_store
    AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

  UNION ALL

  /* 2 · Los apartados COBRADOS ese día. No hay fila en `ventas` hasta que se
     entregan, pero el dinero entró hoy y el Assurant ya los cuenta.

     Sin serie ni `captura_id` a propósito: no hay caja que ligar todavía, y sin
     `captura_id` la app no ofrece el ✏️ ni el borrado — que es lo correcto,
     porque un apartado se corrige desde Preventa, no desde aquí. */
  SELECT a.serie,                      -- normalmente NULL; si ya se asignó, se ve
         a.sku,
         coalesce(c.descripcion, a.color),
         a.precio, a.vendedor, a.con_seguro,
         a.creado_en,                  -- para ordenar por la hora del cobro
         NULL::text,                   -- captura_id: no se toca desde Captura
         false,                        -- tiene_foto
         a.tipo,
         a.creado_en,
         'cobro'
  FROM public.apartados a
  LEFT JOIN public.catalogo c ON c.store_id = a.store_id AND c.sku = a.sku
  CROSS JOIN dia
  WHERE a.store_id = p_store
    AND a.estatus <> 'Cancelado'       -- mismo criterio que ventas_hoy
    AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

  ORDER BY 7;                          -- por hora, todo mezclado como pasó
$$;

REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;

COMMENT ON FUNCTION public.ventas_detalle(text,date) IS
  'Las ventas de un dia para el panel de Captura. `entrega` distingue las que '
  'salen de un apartado (preventa/traspaso): esas se cobraron semanas antes, no '
  'cuentan para el Assurant del dia ni descuentan stock, y no se pueden corregir '
  'con el lapiz. `clase` = venta | entrega | cobro; los cobros son apartados '
  'pagados ese dia, que el Assurant ya cuenta y la lista no ensenaba.';


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) Un día con entregas y cobros — mira la columna `clase`:
--       select clase, serie, vendedor, entrega, cobrado_en
--         from public.ventas_detalle('1217','2026-08-16');
--
--  1-bis) LO QUE IMPORTA: que la lista cuadre con el Assurant del día. Contando
--     solo lo que cuenta para el KPI —o sea, sin las entregas— los totales
--     tienen que coincidir:
--       select count(*) filter (where con_seguro) as con,
--              count(*) filter (where not con_seguro) as sin
--         from public.ventas_detalle('1217')
--        where clase <> 'entrega' and con_seguro is not null;
--       select sum(con_seguro) as con, sum(sin_seguro) as sin
--         from public.ventas_hoy('1217');
--
--  2) Que cuadre con los apartados entregados de ese día:
--       select a.tipo, count(*) from public.apartados a
--         join public.ventas v on v.id = a.venta_id
--        where a.store_id = '1217'
--          and (v.vendida_en at time zone 'America/Mexico_City')::date = '2026-08-16'
--        group by a.tipo;
--
--     Los totales por tipo tienen que coincidir con lo que devuelve la 1.
--
-- ============================================================
--  Odemás · Grupo Gigante — uso interno HES 1217
-- ============================================================


-- ========== supabase_venta_grupo.sql ==========

-- ============================================================
--  AGRUPAR LOS ARTICULOS DE UNA MISMA VENTA
--  20-ago-2026
-- ============================================================
--
--  Hoy cada captura es un articulo suelto. Un cliente que se lleva un telefono
--  y un reloj sale como dos ventas, y al revisar el dia no hay forma de saber
--  que fue una sola compra.
--
--  Ahora el asesor cierra la venta a mano: lo que capture antes de cerrarla
--  queda junto.
--
--  ------------------------------------------------------------
--  LO QUE NO CAMBIA, Y ES LO IMPORTANTE
--  ------------------------------------------------------------
--  El ASSURANT se cuenta por ARTICULO, y el INVENTARIO descuenta por ARTICULO.
--  La agrupacion es SOLO de presentacion.
--
--  Esto no es un detalle: la regla de combos de la tienda dice «2 articulos =
--  1 con seguro, 4 articulos = 2 minimo». Si alguien «simplificara» contando
--  una venta con seguro en vez de dos articulos con uno, el attach cambiaria
--  solo —el KPI que se reporta con meta del 25 %— y nadie lo ataria a este
--  cambio meses despues.
--
--  Por eso `venta_guardar` es la UNICA funcion que toca el grupo, y ni
--  `inventario_vivo`, ni `ventas_hoy`, ni `cargar_cortes` lo miran siquiera.
--
--  ------------------------------------------------------------
--  EL NUMERO DE VENTA NO SE GUARDA: SE CALCULA AL LEER
--  ------------------------------------------------------------
--  La app manda un identificador de grupo, y el numero legible («venta 3») sale
--  de un `dense_rank` por dia al consultar.
--
--  Guardar el consecutivo obligaria a que alguien lo asignara, y dos telefonos
--  capturando a la vez pedirian el mismo numero. Calculado al leer no hay
--  carrera posible y el resultado es siempre coherente.
--
--  LAS VENTAS YA GUARDADAS no se reinterpretan: sin grupo, cada una es la suya
--  y se ve igual que hoy.
--
--  Se pega completo en el SQL Editor. Es idempotente.
-- ============================================================


-- ── 1 · El grupo ────────────────────────────────────────────
ALTER TABLE public.ventas ADD COLUMN IF NOT EXISTS grupo text;

COMMENT ON COLUMN public.ventas.grupo IS
  'Articulos de una misma venta. Lo genera la app y lo cierra el asesor a mano. '
  'Solo agrupa para verlo: el Assurant y el inventario siguen contando por '
  'articulo. NULL en las ventas anteriores al 20-ago-2026.';

CREATE INDEX IF NOT EXISTS ventas_grupo ON public.ventas (store_id, grupo);


-- ── 2 · Guardar la venta con su grupo ───────────────────────
-- La firma cambia (entra `p_grupo`): DROP de la anterior ANTES del CREATE, o
-- Postgres deja las dos y PostgREST responde PGRST203 — o sea, DEJA DE GUARDAR
-- VENTAS. Ya paso con esta misma funcion.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean);
-- 1-sep-2026 · Y la de la firma sin `p_token`, que es la que quedo en las bases
-- montadas antes de que esta funcion pidiera la clave de escritura.
DROP FUNCTION IF EXISTS public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text);

CREATE OR REPLACE FUNCTION public.venta_guardar(
  p_store      text,
  p_serie      text,
  p_sku        text    DEFAULT NULL,
  p_desc       text    DEFAULT NULL,
  p_precio     numeric DEFAULT NULL,
  p_vendedor   text    DEFAULT NULL,
  p_seguro     boolean DEFAULT NULL,
  p_fecha      text    DEFAULT NULL,
  p_hora       text    DEFAULT NULL,
  p_foto_url   text    DEFAULT NULL,
  p_captura_id text    DEFAULT NULL,
  p_de_exhibicion boolean DEFAULT false,
  -- Con DEFAULT: una app en cache que aun no lo mande sigue guardando bien, y
  -- esa venta simplemente queda sin agrupar.
  p_grupo      text    DEFAULT NULL,

  /* LA CLAVE DE ESCRITURA (1-sep-2026). Esta era la unica escritura que no la
     pedia: las otras 14 pasan por `escritura_ok_` desde el 4-ago. Sin ella,
     cualquiera con la clave publicable —que va escrita en el HTML, que es
     publico— podia insertar ventas en CUALQUIER tienda: descontar stock ajeno
     y acreditarle comisiones a quien quisiera. En una tienda sola se notaba
     poco; en una copia donde cada tienda tiene su `store_id`, es la puerta de
     al lado.

     Lleva DEFAULT NULL a proposito, y NO para dejar pasar a quien no lo manda:
     sin DEFAULT, una app vieja en cache recibe un 404 de PostgREST («no
     matches were found in the schema cache»), que se lee como «se cayo
     Supabase». Con DEFAULT llega hasta el IF de abajo y le contesta que no
     tiene permiso, que es lo que de verdad le pasa. */
  p_token      text    DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE
  v_cuando timestamptz;
  v_d int; v_m int; v_a int; v_h int := 12; v_min int := 0;
  m text[];
  nuevo bigint;
BEGIN
  -- Antes que nada: quien no trae la clave de la tienda, no escribe en ella.
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin permiso de escritura');
  END IF;

  IF coalesce(trim(p_serie),'') = '' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin serie');
  END IF;

  m := regexp_match(coalesce(p_fecha,''), '^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s*$');
  IF m IS NOT NULL THEN
    v_d := m[1]::int; v_m := m[2]::int; v_a := m[3]::int;
    m := regexp_match(coalesce(p_hora,''), '^\s*(\d{1,2}):(\d{2})\s*([ap])');
    IF m IS NOT NULL THEN
      v_h := m[1]::int; v_min := m[2]::int;
      IF lower(m[3]) = 'p' AND v_h < 12 THEN v_h := v_h + 12; END IF;
      IF lower(m[3]) = 'a' AND v_h = 12 THEN v_h := 0; END IF;
    END IF;
    v_cuando := make_timestamp(v_a, v_m, v_d, v_h, v_min, 0) AT TIME ZONE 'America/Mexico_City';
  ELSE
    v_cuando := now();
  END IF;

  INSERT INTO public.ventas
    (store_id, vendida_en, serie, sku, descripcion, precio, vendedor, con_seguro,
     foto_url, captura_id, de_exhibicion, grupo)
  VALUES (p_store, v_cuando, trim(p_serie), nullif(trim(coalesce(p_sku,'')),''),
          nullif(trim(coalesce(p_desc,'')),''), p_precio,
          coalesce(nullif(trim(coalesce(p_vendedor,'')),''), '(sin nombre)'),
          p_seguro, nullif(trim(coalesce(p_foto_url,'')),''),
          nullif(trim(coalesce(p_captura_id,'')),''),
          coalesce(p_de_exhibicion, false),
          nullif(trim(coalesce(p_grupo,'')),''))
  ON CONFLICT (store_id, serie, dia_venta) DO NOTHING
  RETURNING id INTO nuevo;

  IF nuevo IS NULL THEN
    RETURN jsonb_build_object('ok', true, 'duplicada', true);
  END IF;
  RETURN jsonb_build_object('ok', true, 'id', nuevo);
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', SQLSTATE || ': ' || left(SQLERRM, 140));
END $fn$;

REVOKE ALL ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.venta_guardar(text,text,text,text,numeric,text,boolean,text,text,text,text,boolean,text,text)
  TO anon, authenticated;


-- ── 3 · La lista, con el numero de venta ────────────────────
DROP FUNCTION IF EXISTS public.ventas_detalle(text, date);

CREATE FUNCTION public.ventas_detalle(p_store text, p_fecha date DEFAULT NULL)
RETURNS TABLE (serie text, sku text, descripcion text, precio numeric,
               vendedor text, con_seguro boolean, vendida_en timestamptz,
               captura_id text, tiene_foto boolean,
               entrega text, cobrado_en timestamptz, clase text,
               -- El numero legible del dia: 1, 2, 3… Calculado, no guardado.
               venta_num integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  WITH dia AS (
    SELECT coalesce(p_fecha, (now() AT TIME ZONE 'America/Mexico_City')::date) AS d
  ),
  todo AS (
    SELECT v.serie, v.sku, v.descripcion, v.precio, v.vendedor, v.con_seguro,
           v.vendida_en, v.captura_id,
           EXISTS (SELECT 1 FROM public.venta_fotos f
                    WHERE f.store_id = v.store_id AND f.captura_id = v.captura_id) AS tiene_foto,
           (SELECT a.tipo      FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1) AS entrega,
           (SELECT a.creado_en FROM public.apartados a WHERE a.venta_id = v.id LIMIT 1) AS cobrado_en,
           CASE WHEN EXISTS (SELECT 1 FROM public.apartados a WHERE a.venta_id = v.id)
                THEN 'entrega' ELSE 'venta' END AS clase,
           -- Sin grupo, cada venta es la suya: el historico se ve igual que hoy.
           coalesce(v.grupo, 'v' || v.id::text) AS g
    FROM public.ventas v
    CROSS JOIN dia
    WHERE v.store_id = p_store
      AND (v.vendida_en AT TIME ZONE 'America/Mexico_City')::date = dia.d

    UNION ALL

    /* Los apartados COBRADOS ese dia. Cada uno va suelto: no son articulos de
       una venta capturada en la app, sino cobros sin equipo todavia. */
    SELECT a.serie, a.sku, coalesce(c.descripcion, a.color), a.precio, a.vendedor,
           a.con_seguro, a.creado_en, NULL::text, false, a.tipo, a.creado_en, 'cobro',
           'a' || a.id::text
    FROM public.apartados a
    LEFT JOIN public.catalogo c ON c.store_id = a.store_id AND c.sku = a.sku
    CROSS JOIN dia
    WHERE a.store_id = p_store
      AND a.estatus <> 'Cancelado'
      AND (a.creado_en AT TIME ZONE 'America/Mexico_City')::date = dia.d
  ),
  /* El numero sale del ORDEN en que empezo cada grupo, no del id: asi «venta 1»
     es siempre la primera del dia aunque sus articulos se hayan guardado
     salteados por la cola de reintentos. */
  orden AS (
    SELECT g, min(vendida_en) AS ini FROM todo GROUP BY g
  )
  SELECT t.serie, t.sku, t.descripcion, t.precio, t.vendedor, t.con_seguro,
         t.vendida_en, t.captura_id, t.tiene_foto, t.entrega, t.cobrado_en, t.clase,
         dense_rank() OVER (ORDER BY o.ini, o.g)::int
  FROM todo t
  JOIN orden o ON o.g = t.g
  ORDER BY o.ini, o.g, t.vendida_en;
$$;

REVOKE ALL ON FUNCTION public.ventas_detalle(text,date) FROM public;
GRANT EXECUTE ON FUNCTION public.ventas_detalle(text,date) TO anon, authenticated;


-- ============================================================
--  COMPROBAR
-- ============================================================
--
--  1) La columna existe y el historico esta sin agrupar:
--       select count(*) filter (where grupo is null) as sin_grupo,
--              count(*) filter (where grupo is not null) as agrupadas
--         from public.ventas where store_id='1217';
--
--  2) La lista trae el numero de venta:
--       select venta_num, serie, descripcion, precio, clase
--         from public.ventas_detalle('1217','2026-08-16') order by venta_num;
--     Cada venta vieja tiene que salir con SU PROPIO numero: sin grupo, no se
--     agrupan entre si.
--
--  3) LO QUE DE VERDAD HAY QUE COMPROBAR — que agrupar no mueve nada.
--     Antes y despues de capturar dos articulos en una misma venta, estos dos
--     tienen que dar lo mismo que si se capturaran sueltos:
--       select * from public.ventas_hoy('1217');
--       select sku, stock from public.inventario_vivo('1217') where sku = '<el sku>';
--     El Assurant cuenta por ARTICULO: dos articulos con un seguro son 1 con y
--     1 sin, no «una venta con seguro».
--
-- ============================================================
--  Odemas · Grupo Gigante — uso interno HES 1217
-- ============================================================


-- ========== supabase_equipo_por_numero.sql ==========

-- ============================================================
--  EL EQUIPO SE VE Y SE ADMINISTRA CON EL NUMERO DE EMPLEADO
--  ...y el responsable de las ventas deja de escribirse a mano
-- ============================================================
--
--  DOS COSAS QUE SALIERON DE LA MISMA PANTALLA (2-sep-2026)
--
--  1 · Admin -> Equipo se veia VACIA para quien entra con su numero, aunque
--      tuviera el permiso puesto. La lista se leia directo de `empleados`, y su
--      RLS pide `auth.uid()`: sin sesion de correo devuelve cero filas. No es
--      un caso raro —es el subgerente, que no tiene el correo de la tienda— y
--      lo que veia era «no hay nadie dado de alta» con tres personas dentro.
--
--  2 · La pestaña Config se quedo con UN campo: el nombre de quien puede abrir
--      «Ventas del dia», escrito a mano y comparado letra por letra contra la
--      lista del equipo. El mismo defecto que se acaba de quitar de los
--      vendedores, en pequeño: una tilde y esa persona no ve el boton, sin que
--      nada avise. Aqui pasa a ser una marca en su ficha.
--
--  Va DESPUES de supabase_hoja_auth.sql: recrea los dos logins.


-- ── 1 · La marca, en la ficha de la persona ─────────────────
ALTER TABLE public.empleados
  ADD COLUMN IF NOT EXISTS ventas_dia boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.empleados.ventas_dia IS
  'Puede abrir «Ventas del dia» en Captura de Series. Gerente y subgerente '
  'entran siempre por su puesto, sin necesidad de esta marca.';


/* De donde sale `hoja_auth` a partir de ahora.

   `tiendas.hoja_auth` se queda como PUENTE, igual que `tiendas.vendedores`: si
   nadie tiene la marca, se usa el texto de antes. Sin eso, la tienda que ya lo
   tenia configurado se queda sin ese boton el dia que se pegue esto. */
CREATE OR REPLACE FUNCTION public.hoja_auth_de_(p_store text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT coalesce(
    (SELECT e.nombre FROM public.empleados e
      WHERE e.store_id = p_store AND e.activo = true AND e.ventas_dia = true
      ORDER BY e.nombre LIMIT 1),
    (SELECT t.hoja_auth FROM public.tiendas t WHERE t.store_id = p_store));
$$;

REVOKE ALL ON FUNCTION public.hoja_auth_de_(text) FROM public, anon, authenticated;


-- ── 2 · Los logins, con la marca en vez del texto ───────────
-- No cambia lo que devuelven —los mismos campos, en el mismo orden—, solo de
-- donde sale `hoja_auth`. Por eso basta CREATE OR REPLACE.
CREATE OR REPLACE FUNCTION public.login_asesor(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb, gas_token text,
               hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id), t.gas_token,
         public.hoja_auth_de_(t.store_id)
  FROM public.tiendas t
  WHERE coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND p_pin = coalesce(nullif(t.asesor_pin, ''), t.store_id)
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.login_empleado(p_pin text)
RETURNS TABLE (store_id text, nombre text, ciudad text,
               vendedores jsonb,
               emp_no text, emp_nombre text, emp_puesto text, emp_admin boolean,
               gas_token text, hoja_auth text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT t.store_id, t.nombre, t.ciudad,
         public.vendedores_de_(t.store_id),
         e.empno, e.nombre, e.puesto, e.admin,
         t.gas_token, public.hoja_auth_de_(t.store_id)
  FROM public.empleados e
  JOIN public.tiendas  t ON t.store_id = e.store_id
  WHERE e.activo = true
    AND coalesce(t.activo, true) = true
    AND length(coalesce(p_pin,'')) >= 4
    AND e.empno = p_pin
  LIMIT 1;
$$;

GRANT EXECUTE ON FUNCTION public.login_asesor(text)   TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.login_empleado(text) TO anon, authenticated;


-- ── 3 · Ver el equipo con el numero ─────────────────────────
/* Dos llaves, no una: el token de la tienda (que solo entrega el login) Y que
   quien pregunta tenga el permiso de Admin. Con una sola bastaria adivinar un
   numero de empleado —son cortos y casi consecutivos— para leerse la lista
   entera con los numeros de todos, que son las llaves de entrada.

   NO devuelve `email` ni `user_id`: eso es de la administracion de cuentas, que
   sigue pidiendo sesion de gerente. Aqui se ve quien es quien y sus permisos. */
CREATE OR REPLACE FUNCTION public.equipo_lista(p_store text, p_token text, p_quien text)
RETURNS TABLE (id bigint, empno text, nombre text, puesto text,
               activo boolean, admin boolean, ventas_dia boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT e.id, e.empno, e.nombre, e.puesto, e.activo, e.admin, e.ventas_dia
    FROM public.empleados e
   WHERE e.store_id = p_store
     AND public.escritura_ok_(p_store, p_token)
     -- POR NOMBRE, no por posicion: la firma real es (p_store_id, p_empno) y
     -- llamarla al reves NO da error —devuelve false— o sea que el permiso se
     -- niega en silencio y la lista sale vacia como si no hubiera nadie. Paso
     -- el 2-sep-2026 y costo media hora de buscar en el sitio equivocado.
     AND public.puede_admin(p_store_id => p_store, p_empno => p_quien)
   ORDER BY e.activo DESC, e.nombre;
$$;

REVOKE ALL ON FUNCTION public.equipo_lista(text,text,text) FROM public;
GRANT EXECUTE ON FUNCTION public.equipo_lista(text,text,text) TO anon, authenticated;


-- ── 4 · Marcar permisos con el numero ───────────────────────
/* Cambia UNA marca de UNA persona. Los tres campos que admite son los tres que
   se pueden repartir sin crear una llave nueva: `admin`, `ventas_dia` y
   `activo`. Dar de ALTA a alguien sigue pidiendo sesion de gerente, y es a
   proposito: un alta es un numero nuevo que abre la app, no un permiso sobre
   alguien que ya esta dentro.

   Las dos reglas que no pueden vivir solo en la pantalla, porque ahi se saltan
   con la consola abierta:
     · no quitarse el ultimo acceso a Admin —la tienda se quedaria sin quien
       reparta permisos, y arreglarlo necesitaria SQL—;
     · no darse a uno mismo, que es como un permiso se convierte en todos. */
CREATE OR REPLACE FUNCTION public.empleado_permiso(
  p_store text, p_token text, p_quien text,
  p_id bigint, p_campo text, p_valor boolean
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
DECLARE v_obj record; v_admins int;
BEGIN
  IF NOT public.escritura_ok_(p_store, p_token) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'sin permiso de escritura');
  END IF;
  -- Por nombre, por lo mismo que en `equipo_lista`: al reves niega en silencio.
  IF NOT public.puede_admin(p_store_id => p_store, p_empno => p_quien) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'no administras esta tienda');
  END IF;
  IF p_campo NOT IN ('admin', 'ventas_dia', 'activo') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'campo no permitido: ' || coalesce(p_campo,'(vacío)'));
  END IF;

  SELECT * INTO v_obj FROM public.empleados
   WHERE id = p_id AND store_id = p_store;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'esa persona no es de esta tienda');
  END IF;

  IF v_obj.empno = p_quien AND p_campo IN ('admin','activo') AND p_valor = false THEN
    RETURN jsonb_build_object('ok', false,
      'error', 'no puedes quitarte a ti mismo ese acceso; que lo haga otra persona con Admin');
  END IF;

  IF p_campo IN ('admin','activo') AND p_valor = false THEN
    SELECT count(*) INTO v_admins FROM public.empleados
     WHERE store_id = p_store AND admin = true AND activo = true;
    IF v_admins <= 1 AND v_obj.admin AND v_obj.activo THEN
      RETURN jsonb_build_object('ok', false,
        'error', 'es el último acceso a Admin de la tienda: da Admin a alguien más antes de quitárselo');
    END IF;
  END IF;

  IF    p_campo = 'admin'      THEN UPDATE public.empleados SET admin      = p_valor WHERE id = p_id;
  ELSIF p_campo = 'ventas_dia' THEN UPDATE public.empleados SET ventas_dia = p_valor WHERE id = p_id;
  ELSE                              UPDATE public.empleados SET activo     = p_valor WHERE id = p_id;
  END IF;

  RETURN jsonb_build_object('ok', true, 'campo', p_campo, 'valor', p_valor,
                            'quien', v_obj.nombre);
END $fn$;

REVOKE ALL ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.empleado_permiso(text,text,text,bigint,text,boolean)
  TO anon, authenticated;


-- ── 5 · El que ya estaba escrito a mano, a su ficha ─────────
/* Una sola vez: quien figure en `tiendas.hoja_auth` y este en el equipo, se
   queda con la marca. Asi la tienda que ya lo tenia configurado no pierde el
   boton, y a partir de aqui se administra desde la ficha. Si el nombre no casa
   letra por letra —que es justo el problema que esto viene a quitar— no marca a
   nadie y el puente de `hoja_auth_de_` lo sigue cubriendo. */
UPDATE public.empleados e
   SET ventas_dia = true
  FROM public.tiendas t
 WHERE t.store_id = e.store_id
   AND coalesce(t.hoja_auth,'') <> ''
   AND e.nombre = t.hoja_auth
   AND e.activo = true
   AND e.ventas_dia = false;


-- ── 6 · Comprobar ───────────────────────────────────────────
-- Quien puede abrir «Ventas del día» en cada tienda, y de dónde sale el dato.
SELECT t.store_id,
       public.hoja_auth_de_(t.store_id) AS responsable,
       EXISTS (SELECT 1 FROM public.empleados e
                WHERE e.store_id = t.store_id AND e.activo AND e.ventas_dia)
         AS ya_sale_de_su_ficha
  FROM public.tiendas t ORDER BY t.store_id;

-- `ya_sale_de_su_ficha` en false significa que esa tienda sigue con el texto
-- viejo: nadie tiene la marca. Se arregla desde Admin → Equipo, no aquí.


-- ========== supabase_token_alta.sql ==========

-- ════════════════════════════════════════════════════════════
--  Una tienda nueva nace con su clave de escritura
--  Correr DESPUES de supabase_acceso.sql y supabase_preventa_series.sql
-- ════════════════════════════════════════════════════════════
--
-- `escritura_ok_` (supabase_preventa_series.sql) compara lo que manda la app
-- contra `tiendas.gas_token`, y 36 funciones la exigen: guardar una venta,
-- apartar una pieza, marcar una entrega, dar de alta a alguien. Sin token, la
-- tienda puede MIRAR y no puede guardar NADA.
--
-- Hasta ahora esa columna se llenaba a mano, porque solo habia una tienda. En
-- cuanto el alta esta abierta, cada gerente que se registra se queda con una
-- app que consulta bien y no vende: no da error de permisos, cada guardado
-- responde `no_autorizado` y la venta se pierde. Por eso lo pone la base.
--
-- El nombre `gas_token` es herencia del Apps Script, que en esta copia no
-- existe. Se conserva porque renombrarlo obliga a tocar las 36 funciones y el
-- front a la vez, y hacerlo a medias deja a las tiendas sin poder escribir.


-- ── 1 · El valor por defecto ────────────────────────────────
-- 32 hex = 128 bits. `escritura_ok_` pide 8 caracteres como minimo; ese minimo
-- es para no rechazar lo que ya existe, no una recomendacion.
--
-- gen_random_uuid() viene con pgcrypto, que Supabase ya trae habilitado. Se usa
-- eso y no md5(random()) porque `random()` no es criptografico: quien vea unos
-- cuantos tokens puede predecir el siguiente, y aqui el token ES el permiso.
ALTER TABLE public.tiendas
  ALTER COLUMN gas_token SET DEFAULT replace(gen_random_uuid()::text, '-', '');


-- ── 2 · Las que ya estan dadas de alta sin token ────────────
-- Solo las vacias. Un UPDATE sin este WHERE le cambiaria la clave a las tiendas
-- que ya trabajan, y todas dejarian de poder guardar en el mismo instante
-- —sin error visible: la app diria `no_autorizado` venta por venta.
UPDATE public.tiendas
   SET gas_token = replace(gen_random_uuid()::text, '-', '')
 WHERE coalesce(gas_token, '') = ''
    OR length(gas_token) < 8;


-- ── 3 · Que no se pueda volver a quedar vacia ───────────────
-- NOT VALID a proposito: valida lo que entre a partir de ahora sin revisar las
-- filas viejas. El UPDATE de arriba ya las dejo bien, pero si alguna se hubiera
-- escapado, la restriccion fallaria al crearse y este archivo no se aplicaria
-- entero — quedando la mitad puesta y la otra no.
ALTER TABLE public.tiendas
  DROP CONSTRAINT IF EXISTS tiendas_token_util;
ALTER TABLE public.tiendas
  ADD CONSTRAINT tiendas_token_util
  CHECK (gas_token IS NULL OR length(gas_token) >= 8) NOT VALID;


-- ── 4 · Comprobacion ────────────────────────────────────────
-- Tiene que devolver CERO filas. Cada fila que salga es una tienda que se abre
-- la app, la ve entera, y pierde en silencio todo lo que capture.
SELECT store_id, nombre, 'sin clave de escritura' AS problema
  FROM public.tiendas
 WHERE coalesce(gas_token, '') = '' OR length(gas_token) < 8;
