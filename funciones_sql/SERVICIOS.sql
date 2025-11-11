-- FUNCION PARA EL INGRESO DEL INFORMACIÓN EN LA TABLA registro_servicios
CREATE OR REPLACE FUNCTION fn_insertar_registro_servicio(
    p_servicio_nombre TEXT,
    p_proveedor_nombre TEXT,
    p_id_local INT,
    p_consumo DECIMAL,
    p_unidad_medida TEXT,
    p_fecha TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
RETURNS VOID AS $$
DECLARE
    v_id_servicio INT;
    v_id_proveedor INT;
    v_id_prov_serv INT;
BEGIN
    -- Buscar ID del servicio
    SELECT id_servicio INTO v_id_servicio
    FROM servicios
    WHERE fn_normalizar_str(servicio) = fn_normalizar_str(p_servicio_nombre);

    IF v_id_servicio IS NULL THEN
        RAISE EXCEPTION 'No se encontró el servicio: %', p_servicio_nombre;
    END IF;

    -- Buscar ID del proveedor
    SELECT id_proveedor INTO v_id_proveedor
    FROM proveedores
    WHERE fn_normalizar_str(nombre) = fn_normalizar_str(p_proveedor_nombre);

    IF v_id_proveedor IS NULL THEN
        RAISE EXCEPTION 'No se encontró el proveedor: %', p_proveedor_nombre;
    END IF;

    -- Buscar ID del par proveedor-servicio
    SELECT id_prov_serv INTO v_id_prov_serv
    FROM servicio_proveedor
    WHERE id_servicio = v_id_servicio AND id_proveedor = v_id_proveedor;

    IF v_id_prov_serv IS NULL THEN
        RAISE EXCEPTION 'No se encontró relación proveedor-servicio entre % y %', p_servicio_nombre, p_proveedor_nombre;
    END IF;

    -- Insertar en registro_servicios
    INSERT INTO registro_servicios (
        id_prov_serv,
        id_local,
        consumo,
        unidad_de_medida,
        fecha
    ) VALUES (
        v_id_prov_serv,
        p_id_local,
        p_consumo,
        p_unidad_medida,
        p_fecha
    );
END;
$$ LANGUAGE plpgsql;

-------------------------------------------
-- TRIGGER QUE REACCIONA AL INGRESO O ODIFICACIÓN DE LA INFORMACION DE LA TABLA registro_servicios
CREATE OR REPLACE FUNCTION completar_registro_servicio()
RETURNS TRIGGER AS $$
DECLARE
    v_precio_unitario DECIMAL;
    v_unidad_base DECIMAL;
BEGIN
    -- Obtener moneda y datos base del proveedor de servicio
    SELECT sp.precio_unitario, sp.unidad, sp.id_moneda
    INTO v_precio_unitario, v_unidad_base, NEW.id_moneda
    FROM servicio_proveedor sp
    WHERE sp.id_prov_serv = NEW.id_prov_serv;

    -- Calcular costo
    NEW.costo := (NEW.consumo / v_unidad_base) * v_precio_unitario;

    -- Fecha por defecto
    IF NEW.fecha IS NULL THEN
        NEW.fecha := CURRENT_TIMESTAMP;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_completar_registro_servicio ON registro_servicios;

CREATE TRIGGER trg_completar_registro_servicio
BEFORE INSERT OR UPDATE ON registro_servicios
FOR EACH ROW
EXECUTE FUNCTION completar_registro_servicio();

------------------------------------------------------------
-- FUNCIÓN QUE HACE UN RECUENTO DE LOS CONSUMOS Y COSTOS DE LOS SERVICIOS EN LO QUE VA DEL MES
DROP FUNCTION IF EXISTS resumen_mensual_servicio(text, date);
CREATE OR REPLACE FUNCTION resumen_mensual_servicio(p_servicio TEXT, p_fecha DATE)
RETURNS TABLE (
    servicio TEXT,
    proveedor TEXT,
    unidad_medida TEXT,
    consumo_total DECIMAL(10,2),
    costo_total DECIMAL(10,2),
    id_moneda INT
) AS $$
DECLARE
    v_id_servicio INT;
    v_mes INT := EXTRACT(MONTH FROM p_fecha);
    v_anio INT := EXTRACT(YEAR FROM p_fecha);
    v_id_local INT;
    v_id_pais INT;
    v_id_moneda_local INT;
BEGIN
    -- Validación de fecha
    IF p_fecha > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha ingresada no puede ser posterior al día de hoy';
    END IF;

    -- Buscar id_servicio
    SELECT s.id_servicio INTO v_id_servicio
    FROM servicios s
    WHERE fn_normalizar_str(s.servicio) = fn_normalizar_str(p_servicio);

    -- Obtener id_local para deducir moneda local
    SELECT DISTINCT rs.id_local INTO v_id_local
    FROM registro_servicios rs
    JOIN servicio_proveedor sp ON rs.id_prov_serv = sp.id_prov_serv
    WHERE EXTRACT(MONTH FROM rs.fecha) = v_mes
      AND EXTRACT(YEAR FROM rs.fecha) = v_anio
      AND sp.id_servicio = v_id_servicio
    LIMIT 1;

    SELECT l.id_pais INTO v_id_pais FROM locales l WHERE l.id_local = v_id_local;
    SELECT p.id_moneda INTO v_id_moneda_local FROM paises p WHERE p.id_pais = v_id_pais;

    -- Por proveedor
    RETURN QUERY
    SELECT 
        s.servicio::TEXT,
        pr.nombre::TEXT,
        rs.unidad_de_medida::TEXT,
        ROUND(SUM(rs.consumo),2),
        ROUND(SUM(rs.costo * (m_b.conversion_USD / m_a.conversion_USD)),2),
        v_id_moneda_local
    FROM registro_servicios rs
    JOIN servicio_proveedor sp ON rs.id_prov_serv = sp.id_prov_serv
    JOIN servicios s ON sp.id_servicio = s.id_servicio
    JOIN proveedores pr ON sp.id_proveedor = pr.id_proveedor
    JOIN monedas m_a ON sp.id_moneda = m_a.id_moneda
    JOIN monedas m_b ON m_b.id_moneda = v_id_moneda_local
    WHERE sp.id_servicio = v_id_servicio
      AND rs.fecha >= DATE_TRUNC('month', p_fecha)
      AND rs.fecha <= p_fecha
    GROUP BY s.servicio, pr.nombre, rs.unidad_de_medida;

    -- Fila total ALL
    RETURN QUERY
    SELECT 
        p_servicio::TEXT,
        'ALL',
        '',  -- unidad no se puede consolidar si hay múltiples unidades distintas
        0.00,
        ROUND(SUM(rs.costo * (m_b.conversion_USD / m_a.conversion_USD)),2),
        v_id_moneda_local
    FROM registro_servicios rs
    JOIN servicio_proveedor sp ON rs.id_prov_serv = sp.id_prov_serv
    JOIN monedas m_a ON sp.id_moneda = m_a.id_moneda
    JOIN monedas m_b ON m_b.id_moneda = v_id_moneda_local
    WHERE sp.id_servicio = v_id_servicio
      AND rs.fecha >= DATE_TRUNC('month', p_fecha)
      AND rs.fecha <= p_fecha;
END;
$$ LANGUAGE plpgsql;