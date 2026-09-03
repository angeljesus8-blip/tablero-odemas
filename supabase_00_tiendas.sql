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
