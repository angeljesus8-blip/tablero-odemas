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

  -- El equipo, para los desplegables. Array de verdad y no "a,b,c": partir una
  -- cadena por comas rompe con los nombres compuestos.
  vendedores text[] NOT NULL DEFAULT '{}',

  -- Codigos con los que el POS cobra una reparacion, separados por coma. Los
  -- lee Captura de Series del ticket para saber sola si la linea es reparacion
  -- o accesorio. Vacio = el asesor lo elige a mano.
  sku_reparacion text,

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
