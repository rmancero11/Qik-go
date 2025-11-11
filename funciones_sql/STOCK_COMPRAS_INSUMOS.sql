-- Función que incerta un lote a la tabla lotes_stock y actualice el stock en stock_locales 
CREATE OR REPLACE FUNCTION insertar_lote_y_actualizar_stock()
RETURNS TRIGGER AS $$
DECLARE
  v_cod_stock BIGINT;
  v_id_local INT;
  v_fecha_entrada DATE;
  v_cantidad_total DECIMAL;
BEGIN
  -- Buscar cod_stock en insumo_proveedor
  SELECT cod_stock INTO v_cod_stock
  FROM insumo_proveedor
  WHERE id_insumo = NEW.id_insumo
    AND id_proveedor = (
      SELECT id_proveedor
      FROM pagos_insumos
      WHERE id_pedido = NEW.id_pedido
    );

  -- Buscar local y fecha de entrada del pedido
  SELECT id_local, fecha_entrada
  INTO v_id_local, v_fecha_entrada
  FROM pagos_insumos
  WHERE id_pedido = NEW.id_pedido;

  -- Calcular cantidad total del lote
  v_cantidad_total := NEW.cantidad_packs * NEW.unidades_por_pack;

  -- Insertar lote en lotes_stock
  INSERT INTO lotes_stock (
    cod_stock, id_local, lote, fecha_compra, fecha_vencimiento, cantidad_unidades
  )
  VALUES (
    v_cod_stock, v_id_local,
    CONCAT(NEW.id_pedido, '-', NEW.id_insumo), -- nombre del lote
    v_fecha_entrada, NEW.fecha_vencimiento,
    v_cantidad_total
  );

  -- Actualizar stock_locales
  INSERT INTO stock_locales (
    id_insumo, id_local, cantidad_minima, cantidad_unidades
  )
  VALUES (
    NEW.id_insumo, v_id_local, 0, v_cantidad_total
  )
  ON CONFLICT (id_insumo, id_local)
  DO UPDATE SET
    cantidad_unidades = stock_locales.cantidad_unidades + EXCLUDED.cantidad_unidades,
    updated_at = CURRENT_TIMESTAMP;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;
 
-- TRIGGER: se activa luego de insertar en pedidos_insumos
DROP TRIGGER IF EXISTS trg_insertar_lote_y_stock ON pedidos_insumos;

CREATE TRIGGER trg_insertar_lote_y_stock
AFTER INSERT ON pedidos_insumos
FOR EACH ROW
EXECUTE FUNCTION insertar_lote_y_actualizar_stock();
---------------------------------------------------------------------
-- Función para la tabla perdidas 
CREATE OR REPLACE FUNCTION fn_procesar_perdida_manual(p_id_perdida INT)
RETURNS VOID AS $$
DECLARE
    r RECORD;
    v_id_local INT;
    v_id_pais INT;
    v_id_moneda_local INT;
    v_conversion_local NUMERIC;
    v_total NUMERIC := 0;
    v_cod_stock INT;
    v_id_moneda_insumo INT;
    v_precio_unitario NUMERIC;
    v_conversion_insumo NUMERIC;
    v_delta NUMERIC;
BEGIN
    -- 1. Obtener el id_local a partir de la tabla perdidas
    SELECT id_local INTO v_id_local
    FROM perdidas
    WHERE id_perdida = p_id_perdida;

    -- 2. Obtener el id_pais y su moneda y conversión
    SELECT l.id_pais, p.id_moneda, m.conversion_USD
    INTO v_id_pais, v_id_moneda_local, v_conversion_local
    FROM locales l
    JOIN paises p ON l.id_pais = p.id_pais
    JOIN monedas m ON p.id_moneda = m.id_moneda
    WHERE l.id_local = v_id_local;

    -- 3. Iterar sobre los insumos perdidos
    FOR r IN
        SELECT id_insumo, cantidad_unidades
        FROM detalle_perdida
        WHERE id_perdida = p_id_perdida
    LOOP
        -- 3.1. Buscar el cod_stock con la fecha_compra más reciente
        SELECT ip.cod_stock
        INTO v_cod_stock
        FROM insumo_proveedor ip
        JOIN lotes_stock ls ON ip.cod_stock = ls.cod_stock
        WHERE ip.id_insumo = r.id_insumo AND ls.id_local = v_id_local
        ORDER BY ls.fecha_compra DESC
        LIMIT 1;

        -- 3.2. Obtener precio y moneda del proveedor
        SELECT ip.id_moneda, ip.precio_unitario, m.conversion_USD
        INTO v_id_moneda_insumo, v_precio_unitario, v_conversion_insumo
        FROM insumo_proveedor ip
        JOIN monedas m ON ip.id_moneda = m.id_moneda
        WHERE ip.cod_stock = v_cod_stock;

        -- 3.3. Calcular factor de conversión
        v_delta := v_conversion_insumo / v_conversion_local;

        -- 3.4. Actualizar detalle_perdida con id_moneda y monto
        UPDATE detalle_perdida
        SET id_moneda = v_id_moneda_local,
            monto = ROUND(r.cantidad_unidades * v_precio_unitario * v_delta, 2)
        WHERE id_perdida = p_id_perdida AND id_insumo = r.id_insumo;

        -- 3.5. Sumar al total
        v_total := v_total + ROUND(r.cantidad_unidades * v_precio_unitario * v_delta, 2);
    END LOOP;

    -- 4. Actualizar la tabla perdidas con id_moneda y monto_total
    UPDATE perdidas
    SET id_moneda = v_id_moneda_local,
        monto_total = v_total
    WHERE id_perdida = p_id_perdida;
END;
$$ LANGUAGE plpgsql;

-- FUNCIÓN que será ejecutada por el trigger
CREATE OR REPLACE FUNCTION trg_detalle_perdida_procesar()
RETURNS TRIGGER AS $$
BEGIN
    -- Ejecutar el procesamiento solo si todavía no fue completado
    IF (SELECT id_moneda FROM perdidas WHERE id_perdida = NEW.id_perdida) IS NULL THEN
        PERFORM fn_procesar_perdida_manual(NEW.id_perdida);
    END IF;

    RETURN NULL; -- porque es un trigger AFTER
END;
$$ LANGUAGE plpgsql;

-- TRIGGER que se ejecuta después de insertar en detalle_perdida
DROP TRIGGER IF EXISTS after_insert_detalle_perdida ON detalle_perdida;

CREATE TRIGGER after_insert_detalle_perdida
AFTER INSERT ON detalle_perdida
FOR EACH ROW
EXECUTE FUNCTION trg_detalle_perdida_procesar();
-------------------------------------------------------------
