-- ════════════════════════════════════════════════════════════
--  Una tienda nueva nace con su clave de escritura
--  Correr DESPUES de supabase_acceso.sql y supabase_preventa_series.sql
-- ════════════════════════════════════════════════════════════
--
-- `escritura_ok_` (supabase_preventa_series.sql) compara lo que manda la app
-- contra `tiendas.gas_token`, y 36 funciones la exigen: guardar una venta,
-- apartar una pieza, marcar una entrega, dar de alta un tecnico. Sin token, la
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
