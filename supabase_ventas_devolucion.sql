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
