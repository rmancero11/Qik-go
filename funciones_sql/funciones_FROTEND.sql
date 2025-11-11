CREATE OR REPLACE FUNCTION registrar_pago_proveedor(
    p_id_pedido INT,
    p_id_local INT,
    p_id_proveedor INT,
    p_id_forma_pago INT,
    p_id_moneda INT,
    p_monto_pedido DECIMAL(10,2),
    p_monto_transporte DECIMAL(10,2) DEFAULT 0.0,
    p_nro_factura VARCHAR(50),
    p_fecha_entrada DATE DEFAULT NULL,
    p_fecha_pago TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
RETURNS JSON AS $$
DECLARE
    v_pago_id BIGINT;
    v_monto_total DECIMAL(10,2);
    v_result JSON;
    v_items RECORD;
    v_fecha_actual DATE := CURRENT_DATE;
BEGIN
    -- Validaciones básicas
    IF p_monto_pedido <= 0 THEN
        RETURN json_build_object('error', 'El monto del pedido debe ser positivo');
    END IF;
    
    IF p_monto_transporte < 0 THEN
        RETURN json_build_object('error', 'El monto de transporte no puede ser negativo');
    END IF;
    
    -- Calcular monto total
    v_monto_total := p_monto_pedido + p_monto_transporte;
    
    -- Registrar el pago en pagos_insumos
    INSERT INTO pagos_insumos (
        id_local, id_proveedor, id_forma_pago, id_moneda,
        monto_pedido, monto_transporte, monto_total,
        nro_factura, fecha_entrada, fecha_pago
    ) VALUES (
        p_id_local, p_id_proveedor, p_id_forma_pago, p_id_moneda,
        p_monto_pedido, p_monto_transporte, v_monto_total,
        p_nro_factura, p_fecha_entrada, p_fecha_pago
    ) RETURNING id_pedido INTO v_pago_id;
    
    -- Si la fecha de entrada es nula o es hoy o anterior, actualizar stock inmediatamente
    IF p_fecha_entrada IS NULL OR p_fecha_entrada <= v_fecha_actual THEN
        -- Actualizar stock para cada ítem del pedido
        FOR v_items IN SELECT * FROM pedidos_insumos WHERE id_pedido = p_id_pedido
        LOOP
            -- Calcular cantidad total de unidades (packs * unidades por pack)
            DECLARE
                v_cantidad_total DECIMAL(10,2) := v_items.cantidad_packs * v_items.unidades_por_pack;
            BEGIN
                -- Actualizar stock local (insertar o sumar si ya existe)
                INSERT INTO stock_locales (id_insumo, id_local, cantidad_unidades)
                VALUES (v_items.id_insumo, p_id_local, v_cantidad_total)
                ON CONFLICT (id_insumo, id_local)
                DO UPDATE SET 
                    cantidad_unidades = stock_locales.cantidad_unidades + EXCLUDED.cantidad_unidades,
                    updated_at = CURRENT_TIMESTAMP;
            END;
        END LOOP;
        
        -- Eliminar el pedido una vez procesado
        DELETE FROM pedidos_insumos WHERE id_pedido = p_id_pedido;
    ELSE
        -- Si la fecha es posterior, crear un evento programado (usando pg_cron o similar)
        -- Esto es un placeholder - necesitarías implementar tu sistema de eventos programados
        RAISE NOTICE 'El stock se actualizará automáticamente el %', p_fecha_entrada;
    END IF;
    
    -- Obtener los datos del pago registrado
    SELECT row_to_json(t) INTO v_result
    FROM (
        SELECT * FROM pagos_insumos WHERE id_pedido = v_pago_id
    ) t;
    
    RETURN json_build_object(
        'success', TRUE,
        'message', 'Pago registrado exitosamente',
        'id_pago', v_pago_id,
        'data', v_result,
        'stock_actualizado', CASE WHEN p_fecha_entrada IS NULL OR p_fecha_entrada <= v_fecha_actual THEN TRUE ELSE FALSE END
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object(
            'error', SQLERRM,
            'detail', 'Error al registrar el pago al proveedor'
        );
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION registrar_venta(
    p_id_local INTEGER,
    p_id_cliente INTEGER,
    p_id_empleado INTEGER,
    p_id_forma_pago INTEGER,
    p_monto NUMERIC,
    p_detalles JSONB,
    p_moneda VARCHAR(3) DEFAULT 'USD',
    p_propina NUMERIC DEFAULT 0,
    p_nro_personas INTEGER DEFAULT 1,
    p_mesa VARCHAR(50) DEFAULT '',
    p_id_turno INTEGER DEFAULT NULL,
    p_servicio_mesa NUMERIC DEFAULT 0,
    p_tipo_venta VARCHAR(50) DEFAULT 'consumo en local',
    p_estado VARCHAR(20) DEFAULT 'completada',
    p_satisfaccion INTEGER DEFAULT NULL,
    p_comentario TEXT DEFAULT ''
)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
    v_venta_id INTEGER;
    v_movimiento_id INTEGER;
    v_cuenta_ingreso INTEGER;
    v_cuenta_salida INTEGER;
    v_detalle JSONB;
    v_producto_id INTEGER;
    v_cantidad INTEGER;
BEGIN
    -- Validaciones básicas
    IF p_monto <= 0 THEN
        RETURN json_build_object('error', 'Monto debe ser un número positivo');
    END IF;
    
    IF p_propina < 0 THEN
        RETURN json_build_object('error', 'Propina debe ser un número positivo o cero');
    END IF;
    
    -- Obtener cuenta propia para ingresos
    SELECT nro_cuenta INTO v_cuenta_ingreso 
    FROM cuentas_propias 
    WHERE id_local = p_id_local AND activa = 1 
    LIMIT 1;
    
    IF v_cuenta_ingreso IS NULL THEN
        RETURN json_build_object('error', 'No se encontró cuenta activa para el local');
    END IF;
    
    -- Obtener cuenta del cliente (si aplica)
    SELECT nro_cuenta INTO v_cuenta_salida
    FROM cuentas
    JOIN entidades ON cuentas.id_entidad = entidades.id_entidad
    WHERE entidades.tipo_entidad = 'cliente' 
    AND entidades.referencia_id = p_id_cliente
    LIMIT 1;
    
    -- 1. Registrar el movimiento financiero
    INSERT INTO movimientos (
        fecha, id_local, id_empleado_entrada, id_clase,
        cuenta_salida, cuenta_ingreso, id_tipo_caja,
        id_forma_pago, id_moneda, monto, descripcion
    ) VALUES (
        NOW(), p_id_local, p_id_empleado,
        (SELECT id_clase FROM clase_movimiento WHERE clase = 'venta'),
        COALESCE(v_cuenta_salida, v_cuenta_ingreso), -- Para pagos en efectivo usa la misma cuenta
        v_cuenta_ingreso,
        CASE WHEN (SELECT forma_pago FROM formas_pago WHERE id_forma_pago = p_id_forma_pago) IN ('efectivo', 'debito') 
             THEN (SELECT id_tipo_caja FROM tipos_caja WHERE tipo_caja = 'caja chica')
             ELSE (SELECT id_tipo_caja FROM tipos_caja WHERE tipo_caja = 'banco') END,
        p_id_forma_pago, p_moneda, p_monto, 'Venta registrada'
    ) RETURNING id_movimiento INTO v_movimiento_id;
    
    -- 2. Registrar la venta principal
    INSERT INTO ventas (
        id_movimiento, fecha, id_local, id_turno,
        id_empleado, id_cliente, id_tipo_venta,
        mesa, nro_personas, servicio_mesa,
        id_forma_pago, id_moneda, monto,
        propina, estado, satisfaccion, comentario
    ) VALUES (
        v_movimiento_id, NOW(), p_id_local, p_id_turno,
        p_id_empleado, p_id_cliente, p_tipo_venta,
        p_mesa, p_nro_personas, p_servicio_mesa,
        p_id_forma_pago, p_moneda, p_monto,
        p_propina, p_estado, p_satisfaccion, p_comentario
    ) RETURNING id_venta INTO v_venta_id;
    
    -- 3. Registrar los detalles de la venta
    FOR v_detalle IN SELECT * FROM jsonb_array_elements(p_detalles)
    LOOP
        v_producto_id := (v_detalle->>'id_producto')::INTEGER;
        v_cantidad := (v_detalle->>'cantidad')::INTEGER;
        
        -- Validar que el producto existe
        IF NOT EXISTS (SELECT 1 FROM menu WHERE id_producto = v_producto_id) THEN
            CONTINUE;
        END IF;
        
        INSERT INTO detalle_ventas (
            id_venta, id_producto, cantidad, id_moneda, precio
        ) VALUES (
            v_venta_id, v_producto_id, v_cantidad, p_moneda,
            (SELECT monto FROM menu WHERE id_producto = v_producto_id)
        );
        
        -- 4. Actualizar stock (opcional)
        UPDATE stock_locales sl
        SET cantidad_unidades = cantidad_unidades - (
            SELECT COALESCE(SUM(ip.cantidad * v_cantidad), 0)
            FROM ingredientes_platos ip
            WHERE ip.id_producto = v_producto_id
            AND ip.id_insumo = sl.id_insumo
        )
        WHERE sl.id_local = p_id_local
        AND sl.id_insumo IN (
            SELECT id_insumo FROM ingredientes_platos WHERE id_producto = v_producto_id
        );
    END LOOP;
    
    -- Obtener los datos de la venta registrada
    SELECT json_build_object(
        'venta', v.*,
        'detalles', (
            SELECT jsonb_agg(row_to_json(d))
            FROM detalle_ventas d
            WHERE d.id_venta = v.id_venta
        )
    ) INTO v_result
    FROM ventas v
    WHERE v.id_venta = v_venta_id;
    
    RETURN json_build_object(
        'message', 'Venta registrada exitosamente',
        'id_venta', v_venta_id,
        'data', v_result
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('error', SQLERRM);
END;
$$ LANGUAGE plpgsql;