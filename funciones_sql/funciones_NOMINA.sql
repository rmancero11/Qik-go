-- FUNCIÓN QUE CALCULA precio_hora EN LA TABLA sueldos_por_pais
CREATE OR REPLACE FUNCTION actualizar_precio_hora()
RETURNS TRIGGER AS $$
DECLARE
    horas INT;
BEGIN
    -- Obtener nro_horas_mensuales del país asociado
    SELECT nro_horas_mensuales
    INTO horas
    FROM paises
    WHERE id_pais = NEW.id_pais;

    -- Calcular precio_hora
    IF horas IS NOT NULL AND horas > 0 THEN
        NEW.precio_hora := NEW.sueldo_bruto / horas;
    ELSE
        NEW.precio_hora := NULL;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_actualizar_precio_hora ON sueldo_por_pais;
-- TRIGGER QUE HACE QUE LA FUNCIÓN ANTERIOR SE ACTIVE SOLO CUANDO SE RELLENA LA COLUMNA sueldo_bruto EN LA TABLA sueldos_por_pais
CREATE TRIGGER trg_actualizar_precio_hora
BEFORE INSERT OR UPDATE OF sueldo_bruto ON sueldo_por_pais
FOR EACH ROW
EXECUTE FUNCTION actualizar_precio_hora();

-- --------------------------------------------------------------------------------------------------

-- FUNCIONES PARA CADA COLUMNA DE LA TABLA registro_horas
-- 1. Calcular horas_extras
CREATE OR REPLACE FUNCTION calcular_horas_extras(p_hora_salida TIME, p_id_turno INT)
RETURNS TIME AS $$
DECLARE
    hora_fin TIME;
    resultado TIME;
BEGIN
    -- Si no hay hora_salida, devolver cero
    IF p_hora_salida IS NULL THEN
        RETURN TIME '00:00:00';
    END IF;

    -- Obtener hora_fin con alias
    SELECT t.hora_fin
    INTO hora_fin
    FROM turnos_trabajo t
    WHERE t.id_turno = p_id_turno;

    IF p_hora_salida > hora_fin THEN
        resultado := p_hora_salida - hora_fin;
    ELSE
        resultado := TIME '00:00:00';
    END IF;

    RETURN resultado;
END;
$$ LANGUAGE plpgsql;

-- 2. Calcular minutos_tardanza
CREATE OR REPLACE FUNCTION calcular_minutos_tardanza(p_hora_entrada TIME, p_id_turno INT)
RETURNS TIME AS $$
DECLARE
    hora_inicio TIME;
    resultado TIME;
BEGIN
    -- Si no hay hora_entrada, devolver cero
    IF p_hora_entrada IS NULL THEN
        RETURN TIME '00:00:00';
    END IF;

    SELECT t.hora_inicio
    INTO hora_inicio
    FROM turnos_trabajo t
    WHERE t.id_turno = p_id_turno;

    IF p_hora_entrada > hora_inicio THEN
        resultado := p_hora_entrada - hora_inicio;
    ELSE
        resultado := TIME '00:00:00';
    END IF;

    RETURN resultado;
END;
$$ LANGUAGE plpgsql;

-- 3. Calcular dia_feriado
CREATE OR REPLACE FUNCTION es_feriado(p_fecha DATE, p_id_local INT)
RETURNS BOOLEAN AS $$
DECLARE
    v_id_pais INT;
    existe BOOLEAN;
BEGIN
    SELECT id_pais INTO v_id_pais
    FROM locales
    WHERE id_local = p_id_local;

    SELECT EXISTS (
        SELECT 1
        FROM feriados_paises
        WHERE id_pais = v_id_pais
        AND EXTRACT(MONTH FROM fecha) = EXTRACT(MONTH FROM p_fecha)
        AND EXTRACT(DAY FROM fecha) = EXTRACT(DAY FROM p_fecha)
    ) INTO existe;

    RETURN existe;
END;
$$ LANGUAGE plpgsql;

-- 4. Calcular dia_vacacional
CREATE OR REPLACE FUNCTION esta_en_vacaciones(p_fecha DATE, p_id_empleado INT)
RETURNS BOOLEAN AS $$
DECLARE
    existe BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM vacaciones_empleado
        WHERE id_empleado = p_id_empleado
        AND EXTRACT(YEAR FROM fecha_inicio) = EXTRACT(YEAR FROM p_fecha)
        AND p_fecha BETWEEN fecha_inicio AND fecha_fin
    ) INTO existe;

    RETURN existe;
END;
$$ LANGUAGE plpgsql;

-- 5. Obtener moneda
CREATE OR REPLACE FUNCTION obtener_id_moneda(p_id_local INT)
RETURNS INT AS $$
DECLARE
    v_id_pais INT;
    v_id_moneda INT;
BEGIN
    SELECT id_pais INTO v_id_pais FROM locales WHERE id_local = p_id_local;
    SELECT id_moneda INTO v_id_moneda FROM paises WHERE id_pais = v_id_pais;

    RETURN v_id_moneda;
END;
$$ LANGUAGE plpgsql;

-- 6. Obtener precio_hora
CREATE OR REPLACE FUNCTION obtener_precio_hora(p_id_empleado INT)
RETURNS DECIMAL AS $$
DECLARE
    v_id_pais INT;
    v_id_area INT;
    v_id_puesto INT;
    v_precio DECIMAL;
BEGIN
    SELECT e.id_pais, e.id_area, e.id_puesto
    INTO v_id_pais, v_id_area, v_id_puesto
    FROM empleados e
    WHERE e.id_empleado = p_id_empleado;

    SELECT precio_hora INTO v_precio
    FROM sueldo_por_pais
    WHERE id_pais = v_id_pais AND id_area = v_id_area AND id_puesto = v_id_puesto;

    RETURN v_precio;
END;
$$ LANGUAGE plpgsql;

-- 7. Calcular sueldo_bruto_diario
CREATE OR REPLACE FUNCTION calcular_sueldo_bruto_diario(
    p_id_empleado INT,
    p_id_turno INT,
    p_fecha DATE,
    p_id_local INT,
    p_dia_feriado BOOLEAN,
    p_dia_vacacional BOOLEAN,
    p_ausencia BOOLEAN,
    p_justificacion TEXT,
    p_mintos_tardanza TIME,
    p_horas_extras TIME
)
RETURNS DECIMAL AS $$
DECLARE
    hora_inicio TIME;
    hora_fin TIME;
    horas_normales NUMERIC;
    horas_extra NUMERIC;
    precio_hora DECIMAL;
    total NUMERIC;
    mult_feriado DECIMAL;
    mult_vacaciones DECIMAL;
    umbral_tardanza INT;
    minutos_tardanza INT;
BEGIN
    -- Obtener hora inicio y fin del turno
    SELECT t.hora_inicio, t.hora_fin
    INTO hora_inicio, hora_fin
    FROM turnos_trabajo t
    WHERE t.id_turno = p_id_turno;

    -- Calcular horas normales
    horas_normales := EXTRACT(EPOCH FROM (hora_fin - hora_inicio)) / 3600.0;

    -- Calcular horas extra
    IF p_horas_extras IS NOT NULL THEN
        horas_extra := EXTRACT(EPOCH FROM p_horas_extras) / 3600.0;
    ELSE
        horas_extra := 0.0;
    END IF;

    -- Obtener umbral de tardanza
    SELECT valor_parámetro
    INTO umbral_tardanza
    FROM parametros
    WHERE parametro = 'tardanzas mayor o igual a 15';

    -- Extraer minutos de tardanza
    IF p_mintos_tardanza IS NOT NULL THEN
        minutos_tardanza := EXTRACT(MINUTE FROM p_mintos_tardanza);
    ELSE
        minutos_tardanza := 0;
    END IF;

    -- Obtener multiplicadores
    SELECT p1.monto_multiplicador, p2.monto_multiplicador
    INTO mult_feriado, mult_vacaciones
    FROM parametros p1, parametros p2
    WHERE p1.parametro = 'feriado'
      AND p2.parametro = 'vacaciones_trabajadas';

    -- Obtener precio por hora
    precio_hora := obtener_precio_hora(p_id_empleado);

    -- Lógica de cálculo según condiciones
    IF minutos_tardanza >= umbral_tardanza THEN
        IF p_dia_vacacional = TRUE THEN
            total := mult_vacaciones * horas_normales * precio_hora;
        ELSE
            total := 0.0;
        END IF;
    ELSE
        IF p_ausencia = TRUE THEN
            IF p_justificacion IS NULL THEN
                total := 0.0;
            ELSE 
                total := horas_normales * precio_hora;
            END IF;
        ELSE
            IF p_dia_feriado = TRUE AND p_dia_vacacional = TRUE THEN
                total := (mult_feriado * (horas_normales + horas_extra) + mult_vacaciones * horas_normales) * precio_hora;
            ELSIF p_dia_feriado = TRUE AND p_dia_vacacional = FALSE THEN
                total := (mult_feriado * (horas_normales + horas_extra)) * precio_hora;
            ELSIF p_dia_feriado = FALSE AND p_dia_vacacional = TRUE THEN
                total := ((horas_normales + horas_extra) + mult_vacaciones * horas_normales) * precio_hora;
            ELSE
                total := (horas_normales + horas_extra) * precio_hora;
            END IF;
        END IF;
    END IF;

    RETURN total;
END;
$$ LANGUAGE plpgsql;

-- FUNCIÓN PARA COMPLETAR AUTOMÁTICAMENTE LA TABLA registro_horas
CREATE OR REPLACE FUNCTION completar_registro_horas()
RETURNS TRIGGER AS $$
BEGIN
  -- Calcular minutos de tardanza si hay hora_entrada
  IF NEW.hora_entrada IS NOT NULL THEN
    NEW.mintos_tardanza := calcular_minutos_tardanza(NEW.hora_entrada, NEW.id_turno);
  ELSE 
    NEW.mintos_tardanza := '00:00:00';
  END IF;

  -- Calcular horas extras si hay hora_salida
  IF NEW.hora_salida IS NOT NULL THEN
    NEW.horas_extras := calcular_horas_extras(NEW.hora_salida, NEW.id_turno);
  ELSE 
    NEW.horas_extras := '00:00:00';
  END IF;
  
  -- Si tiene hora_entrada, se considera que NO hubo ausencia
  IF NEW.hora_entrada IS NOT NULL THEN
    NEW.ausencia := FALSE;
  END IF;

  -- Marcar si es día feriado (requiere fecha + local)
  IF NEW.fecha IS NOT NULL AND NEW.id_local IS NOT NULL THEN
    NEW.dia_feriado := es_feriado(NEW.fecha, NEW.id_local);
  END IF;

  -- Verificar si está dentro de sus vacaciones
  IF NEW.fecha IS NOT NULL AND NEW.id_empleado IS NOT NULL THEN
    NEW.dia_vacional := esta_en_vacaciones(NEW.fecha, NEW.id_empleado);
  END IF;

  -- Obtener moneda asociada al local
  IF NEW.id_local IS NOT NULL THEN
    NEW.id_moneda := obtener_id_moneda(NEW.id_local);
  END IF;

  -- Si el día es vacacional y el empleado se ausenta, automáticamente se justifica su ausencia como 'vacaciones'
  IF NEW.dia_vacional = TRUE AND NEW.ausencia = TRUE THEN
    NEW.justificacion_valida := 'vacaciones';
  ELSE
    -- Si no aplica, se deja nulo (o respeta el valor que el usuario pasó)
    IF NEW.justificacion_valida IS NULL THEN
      NEW.justificacion_valida := NULL;
    END IF;
  END IF;

  -- Calcular sueldo bruto diario usando todos los valores ya asignados
  IF NEW.id_empleado IS NOT NULL AND NEW.id_turno IS NOT NULL THEN
    NEW.sueldo_bruto_diario := calcular_sueldo_bruto_diario(
      NEW.id_empleado,
      NEW.id_turno,
      NEW.fecha,
      NEW.id_local,
      NEW.dia_feriado,
      NEW.dia_vacional,
      NEW.ausencia,
      NEW.justificacion_valida,
      NEW.mintos_tardanza,
      NEW.horas_extras
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_completar_registro_horas ON sueldo_por_pais;
-- TRIGGER QUE EJECUTA LA FUNCIÓN ANTES DE INSERT o UPDATE
CREATE OR REPLACE TRIGGER trg_completar_registro_horas
BEFORE INSERT OR UPDATE ON registro_horas
FOR EACH ROW
EXECUTE FUNCTION completar_registro_horas();
-- --------------------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN QUE GENERA LAS BONIFICACIONES Y DESCUENTOS A PARTIR DE LA TABLA registro_horas
CREATE OR REPLACE FUNCTION descuentos_por_perdidas()
RETURNS void AS $$
DECLARE
    fecha_objetivo DATE := CURRENT_DATE - INTERVAL '1 day';
BEGIN
    -- Pérdidas del día
    INSERT INTO descuentos_empleado (fecha, id_empleado, tipo, id_moneda, monto)
    SELECT 
        p.fecha, 
        p.id_empleado_responable, 
        'pérdida', 
        pa.id_moneda, 
        p.monto_total
    FROM perdidas p
    JOIN locales l ON p.id_local = l.id_local
    JOIN paises pa ON l.id_pais = pa.id_pais
    WHERE p.fecha = fecha_objetivo;
END;
$$ LANGUAGE plpgsql;

-- JOB DARIO QUE EJECUTA LA FUNCION DE BONIFICACIONES Y DESCUENTOS TODOS LOS DIAS A LAS 2:00
SELECT cron.schedule(
  'perdidas_diarias',
  '0 2 * * *',  -- todos los días a las 2:00 AM
  $$SELECT descuentos_por_perdidas();$$
);

-- --------------------------------------------------------------------------------------------------------------------------------------------------
-- FUNCIÓN PARA GENERAR LA TABLA registro_mensual_empleados
CREATE OR REPLACE FUNCTION generar_registro_mensual_empleados()
RETURNS void AS $$
DECLARE
    fecha_actual DATE := CURRENT_DATE;
    mes_actual INT := EXTRACT(MONTH FROM fecha_actual);
    anio_actual INT := EXTRACT(YEAR FROM fecha_actual);
    --mes_objetivo INT := CASE WHEN mes_actual = 1 THEN 12 ELSE mes_actual - 1 END;
    --anio_objetivo INT := CASE WHEN mes_actual = 1 THEN anio_actual - 1 ELSE anio_actual END;
    mes_objetivo INT := 5;
    anio_objetivo INT := 2025;
    empleado_id INT;
BEGIN
    FOR empleado_id IN
        SELECT DISTINCT id_empleado
        FROM registro_horas
        WHERE EXTRACT(MONTH FROM fecha) = mes_objetivo
          AND EXTRACT(YEAR FROM fecha) = anio_objetivo
    LOOP
    INSERT INTO registro_mensual_empleados (
        mes, anio, id_empleado, id_local,
        horas_extras, dias_feriados, dias_vacacionales,
        tardanzas_penalizadas, ausencias_justificadas,
        ausencias_no_justificadas, perdidas, descripcion
    )
    SELECT
        mes_objetivo, anio_objetivo, rh.id_empleado,
        e.id_local,
        (make_interval(secs => SUM(EXTRACT(EPOCH FROM rh.horas_extras))))::time AS horas_extras,

        -- Días feriados trabajados
        SUM(CASE WHEN rh.dia_feriado = TRUE AND rh.ausencia = FALSE
            AND EXTRACT(MINUTE FROM rh.mintos_tardanza) < (
                SELECT valor_parámetro
                FROM parametros
                WHERE parametro = 'tardanzas mayor o igual a 15'
            )
        THEN 1 ELSE 0 END) AS dias_feriados,

        -- Días vacacionales trabajados
        SUM(CASE WHEN rh.dia_vacional = TRUE AND rh.ausencia = FALSE
        THEN 1 ELSE 0 END) AS dias_vacacionales,

        -- Tardanzas penalizables
        SUM(CASE WHEN EXTRACT(MINUTE FROM rh.mintos_tardanza) >= (
                SELECT valor_parámetro
                FROM parametros
                WHERE parametro = 'tardanzas mayor o igual a 15'
            )
        THEN 1 ELSE 0 END) AS tardanzas_penalizadas,

        -- Ausencias justificadas
        SUM(CASE WHEN rh.ausencia = TRUE AND rh.justificacion_valida IS NOT NULL THEN 1 ELSE 0 END) AS ausencias_justificadas,

        -- Ausencias no justificadas
        SUM(CASE WHEN rh.ausencia = TRUE AND rh.justificacion_valida IS NULL THEN 1 ELSE 0 END) AS ausencias_no_justificadas,

        -- Pérdidas
        (SELECT COUNT(*)
        FROM perdidas p
        WHERE p.id_empleado_responable = rh.id_empleado
            AND EXTRACT(MONTH FROM p.fecha) = mes_objetivo
            AND EXTRACT(YEAR FROM p.fecha) = anio_objetivo) AS perdidas,
        NULL AS descripcion
        FROM registro_horas rh
        JOIN empleados e ON e.id_empleado = rh.id_empleado
        WHERE EXTRACT(MONTH FROM rh.fecha) = mes_objetivo
            AND EXTRACT(YEAR FROM rh.fecha) = anio_objetivo
            AND rh.id_empleado = empleado_id
        GROUP BY rh.id_empleado, e.id_local;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- PROGRAMAR EJECUCIÓN MENSUAL EN EL DIA 1 A LAS 03:00
SELECT cron.schedule(
  'registro_mensual_empleados',
  '0 3 1 * *',  -- a las 03:00 del día 1 de cada mes
  $$SELECT generar_registro_mensual_empleados();$$
);

-- --------------------------------------------------------------------------------------------------------------------------------------------------
-- FUNCION PARA GENERAR LA TABLA calculo_sueldo_neto
CREATE OR REPLACE FUNCTION calcular_sueldo_neto_mensual()
RETURNS void AS $$
DECLARE
    fecha_actual DATE := CURRENT_DATE;
    mes_actual INT := EXTRACT(MONTH FROM fecha_actual);
    anio_actual INT := EXTRACT(YEAR FROM fecha_actual);
    mes_objetivo INT := CASE WHEN mes_actual = 1 THEN 12 ELSE mes_actual - 1 END;
    anio_objetivo INT := CASE WHEN mes_actual = 1 THEN anio_actual - 1 ELSE anio_actual END;
    --mes_objetivo INT := 5;
    --anio_objetivo INT := 2025;    
    empleado_id INT;
    local_id INT;
    id_moneda INT;
    aporte_tasa DECIMAL;
    aporte_valor DECIMAL;
    aporte_empleador DECIMAL;
    total_bono DECIMAL;
    total_desc DECIMAL;
    sueldo_bruto DECIMAL;
    decimo_tercero DECIMAL := 0;
    decimo_cuarto DECIMAL := 0;
    mensualiza_13 BOOLEAN;
    mensualiza_14 BOOLEAN;
    mes_pago_13 INT;
    mes_pago_14 INT;
    sueldo_neto_final DECIMAL;
    costo_total_para_empleador DECIMAL;
    v_id_pais INT;
BEGIN
    FOR empleado_id IN
        SELECT DISTINCT id_empleado
        FROM registro_horas
        WHERE EXTRACT(MONTH FROM fecha) = mes_objetivo
          AND EXTRACT(YEAR FROM fecha) = anio_objetivo
    LOOP
        -- Obtener datos del empleado
        SELECT e.id_local, e.mensualizacion_decimo_tercero, e.mensualizacion_decimo_cuarto,
               e.id_pais
        INTO local_id, mensualiza_13, mensualiza_14,
             v_id_pais
        FROM empleados e
        WHERE e.id_empleado = empleado_id;

        -- Obtener datos del país (incluye id_moneda)
        SELECT p.id_moneda, p.aporte_seguridad_social_empleado, p.aporte_seguridad_social_empleador,
               p.mes_pago_decimo_tercero, p.mes_pago_decimo_cuarto
        INTO id_moneda, aporte_tasa, aporte_empleador,
             mes_pago_13, mes_pago_14
        FROM paises p
        WHERE p.id_pais = v_id_pais;

        -- Obtener sueldo bruto mensual sumando registro_horas
        SELECT COALESCE(SUM(rh.sueldo_bruto_diario),0)
        INTO sueldo_bruto
        FROM registro_horas rh
        WHERE rh.id_empleado = empleado_id
          AND EXTRACT(MONTH FROM rh.fecha) = mes_objetivo
          AND EXTRACT(YEAR FROM rh.fecha) = anio_objetivo;

        -- Calcular bonificaciones y descuentos
        SELECT COALESCE(SUM(b.monto), 0) INTO total_bono
        FROM bonificaciones_empleado b
        WHERE b.id_empleado = empleado_id
          AND EXTRACT(MONTH FROM b.fecha) = mes_objetivo
          AND EXTRACT(YEAR FROM b.fecha) = anio_objetivo;

        SELECT COALESCE(SUM(d.monto), 0) INTO total_desc
        FROM descuentos_empleado d
        WHERE d.id_empleado = empleado_id
          AND EXTRACT(MONTH FROM d.fecha) = mes_objetivo
          AND EXTRACT(YEAR FROM d.fecha) = anio_objetivo;

        -- Calcular aporte del empleado
        IF (SELECT e.empleado_informal FROM empleados e WHERE e.id_empleado = empleado_id) THEN
            aporte_valor := 0.0;
        ELSE
            aporte_valor := sueldo_bruto * aporte_tasa;
        END IF;

        -- Cálculo de décimos
        IF mensualiza_13 THEN
            decimo_tercero := sueldo_bruto / 12;
        ELSIF mes_pago_13 = mes_objetivo THEN
            decimo_tercero := sueldo_bruto;
        ELSE
            decimo_tercero := 0.0;
        END IF;

        IF mensualiza_14 THEN
            decimo_cuarto := sueldo_bruto / 12;
        ELSIF mes_pago_14 = mes_objetivo THEN
            decimo_cuarto := sueldo_bruto;
        ELSE
            decimo_cuarto := 0.0;
        END IF;

        -- Calcular sueldo neto final
        sueldo_neto_final := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto - total_desc - aporte_valor;

        -- Calcular costo total para el empleador
        IF (SELECT e.empleado_informal FROM empleados e WHERE e.id_empleado = empleado_id) THEN
            costo_total_para_empleador := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto;
        ELSE
            costo_total_para_empleador := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto + (sueldo_bruto * aporte_empleador);
        END IF;

        -- Insertar en tabla
        INSERT INTO calculo_sueldo_neto (
            mes, anio, id_empleado, id_local, id_moneda,
            sueldo_bruto, total_bonificaciones, total_descuentos,
            aporte_empleado, decimo_tercero, decimo_cuarto,
            sueldo_neto, costo_total_para_empleador, pendiente
        )
        VALUES (
            mes_objetivo, anio_objetivo, empleado_id, local_id, id_moneda,
            sueldo_bruto, total_bono, total_desc,
            aporte_valor, decimo_tercero, decimo_cuarto,
            sueldo_neto_final, costo_total_para_empleador, TRUE
        );
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- PROGRAMAR LA EJECUCIÓN MENSUAL EL DIA 1 A LAS 04:00
SELECT cron.schedule(
  'calculo_sueldo_neto_mensual',
  '0 4 1 * *',  -- a las 04:00 del día 1 de cada mes
  $$SELECT calcular_sueldo_neto_mensual();$$
);

-------------------------------------------------------------------------------------------------
-- Funciones que hacen el registro de los empleados y el calculo del sueldo neto desde el comienzo del mes hasta la fecha que uno quiera (dia ingresado no incluido)
DROP FUNCTION calcular_sueldo_neto_hasta_fecha(date);
CREATE OR REPLACE FUNCTION calcular_sueldo_neto_hasta_fecha(p_fecha DATE)
RETURNS TABLE (
    mes INT,
    anio INT,
    id_empleado INT,
    id_local INT,
    id_moneda INT,
    sueldo_bruto DECIMAL,
    total_bonificaciones DECIMAL,
    total_descuentos DECIMAL,
    aporte_empleado DECIMAL,
    decimo_tercero DECIMAL,
    decimo_cuarto DECIMAL,
    sueldo_neto DECIMAL,
    costo_total_para_empleador DECIMAL
) AS $$
DECLARE
    fecha_limite DATE;
    mes_objetivo INT;
    anio_objetivo INT;
    v_empleado_id INT;
    local_id INT;
    id_moneda INT;
    aporte_tasa DECIMAL;
    aporte_empleador DECIMAL;
    aporte_valor DECIMAL;
    total_bono DECIMAL;
    total_desc DECIMAL;
    sueldo_bruto DECIMAL;
    decimo_tercero DECIMAL := 0;
    decimo_cuarto DECIMAL := 0;
    mensualiza_13 BOOLEAN;
    mensualiza_14 BOOLEAN;
    mes_pago_13 INT;
    mes_pago_14 INT;
    sueldo_neto_final DECIMAL;
    costo_total_para_empleador DECIMAL;
    v_id_pais INT;
BEGIN
    -- Validar que la fecha no sea futura
    IF p_fecha > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha ingresada no puede ser posterior al día de hoy';
    END IF;

    -- Determinar la fecha límite
    IF p_fecha = CURRENT_DATE THEN
        fecha_limite := p_fecha - INTERVAL '1 day';
    ELSE
        fecha_limite := p_fecha;
    END IF;

    mes_objetivo := EXTRACT(MONTH FROM fecha_limite);
    anio_objetivo := EXTRACT(YEAR FROM fecha_limite);

    -- Iterar sobre empleados con registros en ese rango
    FOR v_empleado_id IN
        SELECT DISTINCT rh.id_empleado
        FROM registro_horas rh
        WHERE rh.fecha >= DATE_TRUNC('month', fecha_limite)
          AND rh.fecha <= fecha_limite
    LOOP
        -- Datos del empleado
        SELECT e.id_local, e.mensualizacion_decimo_tercero, e.mensualizacion_decimo_cuarto,
               e.id_pais
        INTO local_id, mensualiza_13, mensualiza_14,
             v_id_pais
        FROM empleados e
        WHERE e.id_empleado = v_empleado_id;

        -- Datos del país
        SELECT p.id_moneda, p.aporte_seguridad_social_empleado, p.aporte_seguridad_social_empleador,
               p.mes_pago_decimo_tercero, p.mes_pago_decimo_cuarto
        INTO id_moneda, aporte_tasa, aporte_empleador,
             mes_pago_13, mes_pago_14
        FROM paises p
        WHERE p.id_pais = v_id_pais;

        -- Sumar sueldo bruto diario
        SELECT COALESCE(SUM(rh.sueldo_bruto_diario),0)
        INTO sueldo_bruto
        FROM registro_horas rh
        WHERE rh.id_empleado = v_empleado_id
          AND rh.fecha >= DATE_TRUNC('month', fecha_limite)
          AND rh.fecha <= fecha_limite;

        -- Bonificaciones
        SELECT COALESCE(SUM(b.monto),0)
        INTO total_bono
        FROM bonificaciones_empleado b
        WHERE b.id_empleado = v_empleado_id
          AND b.fecha >= DATE_TRUNC('month', fecha_limite)
          AND b.fecha <= fecha_limite;

        -- Descuentos
        SELECT COALESCE(SUM(d.monto),0)
        INTO total_desc
        FROM descuentos_empleado d
        WHERE d.id_empleado = v_empleado_id
          AND d.fecha >= DATE_TRUNC('month', fecha_limite)
          AND d.fecha <= fecha_limite;

        -- Aporte empleado
        IF (SELECT e.empleado_informal FROM empleados e WHERE e.id_empleado = v_empleado_id) THEN
            aporte_valor := 0.0;
        ELSE
            aporte_valor := sueldo_bruto * aporte_tasa;
        END IF;

        -- Décimo tercero
        IF mensualiza_13 THEN
            decimo_tercero := sueldo_bruto / 12;
        ELSIF mes_pago_13 = mes_objetivo THEN
            decimo_tercero := sueldo_bruto;
        ELSE
            decimo_tercero := 0.0;
        END IF;

        -- Décimo cuarto
        IF mensualiza_14 THEN
            decimo_cuarto := sueldo_bruto / 12;
        ELSIF mes_pago_14 = mes_objetivo THEN
            decimo_cuarto := sueldo_bruto;
        ELSE
            decimo_cuarto := 0.0;
        END IF;

        -- Sueldo neto
        sueldo_neto_final := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto - total_desc - aporte_valor;

        -- Costo total empleador
        IF (SELECT e.empleado_informal FROM empleados e WHERE e.id_empleado = v_empleado_id) THEN
            costo_total_para_empleador := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto;
        ELSE
            costo_total_para_empleador := sueldo_bruto + total_bono + decimo_tercero + decimo_cuarto + (sueldo_bruto * aporte_empleador);
        END IF;

        -- Devolver
        RETURN QUERY
        SELECT
            mes_objetivo,
            anio_objetivo,
            v_empleado_id,
            local_id,
            id_moneda,
            ROUND(sueldo_bruto,2),
            ROUND(total_bono,2),
            ROUND(total_desc,2),
            ROUND(aporte_valor,2),
            ROUND(decimo_tercero,2),
            ROUND(decimo_cuarto,2),
            ROUND(sueldo_neto_final,2),
            ROUND(costo_total_para_empleador,2);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

--------------------------------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION generar_registro_mensual_hasta_fecha(p_fecha DATE)
RETURNS TABLE (
    mes INT,
    anio INT,
    id_empleado INT,
    id_local INT,
    horas_extras TIME,
    dias_feriados INT,
    dias_vacacionales INT,
    tardanzas_penalizadas INT,
    ausencias_justificadas INT,
    ausencias_no_justificadas INT,
    perdidas INT,
    descripcion TEXT
) AS $$
DECLARE
    fecha_limite DATE;
    mes_objetivo INT;
    anio_objetivo INT;
    v_empleado_id INT;
BEGIN
    IF p_fecha > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha ingresada no puede ser posterior al día de hoy';
    END IF;

    IF p_fecha = CURRENT_DATE THEN
        fecha_limite := p_fecha - INTERVAL '1 day';
    ELSE
        fecha_limite := p_fecha;
    END IF;

    mes_objetivo := EXTRACT(MONTH FROM fecha_limite);
    anio_objetivo := EXTRACT(YEAR FROM fecha_limite);

    FOR v_empleado_id IN
        SELECT DISTINCT rh.id_empleado
        FROM registro_horas rh
        WHERE rh.fecha >= DATE_TRUNC('month', fecha_limite)
          AND rh.fecha <= fecha_limite
    LOOP
        RETURN QUERY
        SELECT
            mes_objetivo,
            anio_objetivo,
            rh.id_empleado,
            e.id_local,
            make_interval(secs => COALESCE(SUM(EXTRACT(EPOCH FROM rh.horas_extras)),0))::time,
            -- Conversión explícita a integer
            SUM(CASE WHEN rh.dia_feriado = TRUE AND rh.ausencia = FALSE THEN 1 ELSE 0 END)::integer,
            SUM(CASE WHEN rh.dia_vacional = TRUE AND rh.ausencia = FALSE THEN 1 ELSE 0 END)::integer,
            SUM(CASE WHEN EXTRACT(MINUTE FROM rh.mintos_tardanza) >= (
                SELECT valor_parámetro FROM parametros WHERE parametro = 'tardanzas mayor o igual a 15'
            ) THEN 1 ELSE 0 END)::integer,
            SUM(CASE WHEN rh.ausencia = TRUE AND rh.justificacion_valida IS NOT NULL THEN 1 ELSE 0 END)::integer,
            SUM(CASE WHEN rh.ausencia = TRUE AND rh.justificacion_valida IS NULL THEN 1 ELSE 0 END)::integer,
            (
                SELECT COUNT(*)::integer FROM perdidas p
                WHERE p.id_empleado_responable = rh.id_empleado
                  AND p.fecha >= DATE_TRUNC('month', fecha_limite)
                  AND p.fecha <= fecha_limite
            ),
            NULL AS descripcion
        FROM registro_horas rh
        JOIN empleados e ON e.id_empleado = rh.id_empleado
        WHERE rh.fecha >= DATE_TRUNC('month', fecha_limite)
          AND rh.fecha <= fecha_limite
          AND rh.id_empleado = v_empleado_id
        GROUP BY rh.id_empleado, e.id_local;
    END LOOP;
END;
$$ LANGUAGE plpgsql;