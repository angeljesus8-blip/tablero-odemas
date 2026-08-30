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
INSERT INTO public.preventa_cupo (store_id, sku, cupo) VALUES
  ('1217', '100307448', 4),   -- Graphite Black
  ('1217', '100307464', 5),   -- Blush Gold
  ('1217', '100307481', 2),   -- Blaze Purple
  ('1217', '100307499', 6),   -- Orange Ocean
  ('1217', '100307501', 3),   -- Coconut White
  ('1217', '100307510', 4),   -- Mulberry Black
  ('1217', '100307536', 2),   -- Guava Soda
  ('1217', '100307641', 4),   -- Orange Soda
  ('1217', '100307544', 2),   -- Mulberry Black
  ('1217', '100307561', 2),   -- Coconut White
  ('1217', '100307595', 2),   -- Orange Soda
  ('1217', '100307616', 1)   -- Guava Soda
ON CONFLICT (store_id, sku) DO UPDATE SET cupo = EXCLUDED.cupo;


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
