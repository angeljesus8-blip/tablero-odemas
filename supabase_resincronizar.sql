-- ============================================================
-- resincronizar() · volver a traer TODO de la hoja, en el orden correcto
-- 4-ago-2026
-- ============================================================
--
-- Por qué hacía falta
-- -------------------
-- La carga ya era repetible: las seis `cargar_*` son idempotentes y Postgres
-- llama al Apps Script él mismo con la extensión `http`. Lo que no había era
-- una forma **segura** de ejecutarlas, y el orden importa de verdad:
--
--   · `cargar_cortes` DESPUÉS de `cargar_ventas`. El GAS no guarda el corte,
--     guarda cuántas ventas había cuando se tomó, así que aquí se despeja como
--     (total de ventas − vendido desde el corte). Sin ventas cargadas el total
--     es cero, todos los cortes salen en cero, y entonces el tablero enseña
--     como "vendido" TODO el histórico y el stock en cero. En piso eso es
--     dejar de vender lo que sí hay.
--   · `cargar_resto` después de `cargar_catalogo`: el inventario solo entra
--     para SKUs que ya existan en el catálogo.
--
-- Ese orden estaba escrito en un comentario. Esta sesión ha dejado claro que un
-- comentario no basta: aquí el orden vive en el código y no se puede invertir.
--
-- **Y si un paso falla, se para.** Es lo que impide el desastre de arriba: sin
-- esto, un `cargar_ventas` que fallara —la nube que no contesta, un timeout—
-- dejaría correr `cargar_cortes` igual, y el resultado no sería un error a la
-- vista sino un tablero mintiendo sobre el stock.
--
-- Cuándo se usa
-- -------------
-- Antes de comparar contra el Apps Script, siempre. La comparación de paridad
-- caduca: vale para el instante en que se hace. El 4-ago se comparó con datos
-- del 2 y cinco lecturas salieron "distintas" sin que nada estuviera mal.
--
-- También sirve de red mientras exista el GAS: si Supabase se queda atrás, esto
-- lo pone al día en un paso.
--
-- Lo que NO puede recuperar: combos y avisos ya vencidos. `modo=todo` los
-- entrega filtrados por vigencia y el Apps Script no los expone de otra forma.
-- ============================================================

CREATE OR REPLACE FUNCTION public.resincronizar(p_store text)
RETURNS TABLE (paso int, que text, resultado text)
LANGUAGE plpgsql
AS $fn$
DECLARE
  r     text;
  fallo boolean := false;
  -- El orden es la parte que importa. No reordenar sin leer la cabecera.
  pasos text[] := ARRAY['cargar_catalogo',
                        'cargar_resto',
                        'rescatar_sin_upc',
                        'cargar_ventas',
                        'cargar_cortes',                 -- ← nunca antes de ventas
                        'cargar_apartados_comisiones'];
  i int;
BEGIN
  -- La extensión http corta a los 5 s y `modo=todo` tarda más. No se guarda
  -- entre sesiones, así que se pone aquí y no en un paso aparte que se olvide.
  PERFORM extensions.http_set_curlopt('CURLOPT_TIMEOUT', '60');

  FOR i IN 1 .. array_length(pasos, 1) LOOP
    IF fallo THEN
      paso := i; que := pasos[i];
      resultado := 'NO SE EJECUTO — fallo un paso anterior';
      RETURN NEXT;
      CONTINUE;
    END IF;

    EXECUTE format('SELECT public.%I($1)', pasos[i]) INTO r USING p_store;

    -- Las cargar_* no lanzan: devuelven el problema como texto. Hay que mirarlo,
    -- o "no lanzó" se confundiría con "salió bien".
    IF r IS NULL OR r ~* '^\s*(ERROR|la nube no)' THEN
      fallo := true;
    END IF;

    paso := i; que := pasos[i]; resultado := coalesce(r, '(sin respuesta)');
    RETURN NEXT;
  END LOOP;
END $fn$;

REVOKE ALL ON FUNCTION public.resincronizar(text) FROM public;
-- A propósito NO se concede a anon: esto reescribe el catálogo entero de una
-- tienda. Se corre desde el editor SQL, con cuenta de dueño.

COMMENT ON FUNCTION public.resincronizar(text) IS
  'Vuelve a traer todo de la hoja en el orden correcto y se detiene si un paso '
  'falla. Correr SIEMPRE antes de comparar contra el Apps Script: la paridad '
  'caduca en cuanto se sube el Excel del día.';

-- ------------------------------------------------------------
-- Cómo se corre
-- ------------------------------------------------------------
--   SELECT * FROM public.resincronizar('1217');
--
-- Devuelve una fila por paso. Los seis tienen que traer un conteo; si alguno
-- dice ERROR o "NO SE EJECUTO", **no comparar todavía** — los datos quedaron a
-- medias y las diferencias que salgan no significarán nada.

-- ------------------------------------------------------------
-- Primera ejecución, 4-ago-2026: la parada valió la pena de inmediato
-- ------------------------------------------------------------
--   1 cargar_catalogo              215 SKUs cargados
--   2 cargar_resto                 inventario=215 promos=117 eol=133
--   3 rescatar_sin_upc             faltaban 0 · insertados 0
--   4 cargar_ventas                ERROR 42P10: no unique constraint matching
--                                  the ON CONFLICT specification
--   5 cargar_cortes                NO SE EJECUTO
--   6 cargar_apartados_comisiones  NO SE EJECUTO
--
-- El fallo lo causó el cambio de la regla de la serie unas horas antes:
-- `cargar_ventas` tenía `ON CONFLICT (store_id, serie)` y esa restricción ya no
-- existe. Se revisó qué LEE la restricción y no qué ESCRIBE contra ella.
--
-- Y ahí se vio para qué sirve pararse: `cargar_cortes` habría corrido detrás
-- con las ventas a medias, y eso no da error — da cortes en cero, o sea un
-- tablero enseñando stock cero sobre mercancía que está en la bodega.
--
-- Lo arregla `supabase_cargar_ventas_fix.sql`. Hasta entonces Supabase queda a
-- medias: catálogo, inventario, promos y eol al día; ventas, cortes, apartados
-- y comisiones del 2-ago. No afecta a la tienda —nadie lee de Supabase
-- todavía— pero **cualquier comparación hecha en este estado no significa nada**.
-- ============================================================
