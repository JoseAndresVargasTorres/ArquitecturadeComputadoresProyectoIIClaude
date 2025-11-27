# Solución al Error de Compilación en ModelSim

## Problema Detectado

El testbench `tb_Downscale_Secuencial_con_Memoria` falló al simular con los siguientes errores:

```
Error: (vsim-3033) Instantiation of 'ImageMemory_SequentialPort' failed. The design unit was not found.
Error: (vsim-3033) Instantiation of 'Downscale_Secuencial' failed. The design unit was not found.
```

## Causa del Error

Los módulos `ImageMemory_SequentialPort.sv` y `Downscale_Secuencial.sv` NO fueron compilados antes de intentar simular el testbench, aunque estos archivos SÍ existen en el proyecto.

El script de compilación automático de ModelSim no incluyó estos módulos en la secuencia de compilación.

## Solución Aplicada

### 1. Actualización del Archivo de Proyecto Quartus (ModoSecuencial.qsf)

Se agregaron los siguientes testbenches al proyecto:
- `tb_Downscale_Secuencial_con_Memoria.sv`
- `tb_Downscale_SIMD_con_Memoria.sv`

Estos testbenches ahora están configurados como testbenches de simulación EDA.

### 2. Pasos para Resolver el Error en Windows

Debes regenerar los scripts de simulación desde Quartus:

#### Opción A: Regenerar Scripts Automáticamente (Recomendado)

1. Abre el proyecto `ModoSecuencial.qpf` en Quartus Prime
2. Ve a **Tools → Run Simulation Tool → RTL Simulation**
3. Esto regenerará automáticamente el archivo `.do` con TODOS los módulos necesarios
4. El nuevo script incluirá:
   - `ImageMemory_SequentialPort.sv`
   - `Downscale_Secuencial.sv`
   - Todos los demás módulos requeridos

#### Opción B: Modificar el Script Manualmente

Si prefieres modificar el script `.do` manualmente, agrega estas líneas ANTES de compilar el testbench:

```tcl
vlog -sv -work work +incdir+C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto {C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto/ImageMemory_SequentialPort.sv}
vlog -sv -work work +incdir+C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto {C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto/Downscale_Secuencial.sv}
```

### 3. Orden de Compilación Correcto

El orden debe ser:

1. **Módulos básicos** (ModoSecuencial, ModoSIMD, etc.)
2. **Módulos de memoria**:
   - `ImageMemory.sv`
   - `ImageMemory_SequentialPort.sv`
   - `ImageMemory_SIMDPort.sv`
3. **Módulos de procesamiento**:
   - `Downscale_Secuencial.sv`
   - `Downscale_SIMD.sv`
4. **Testbenches**:
   - `tb_Downscale_Secuencial_con_Memoria.sv`
   - `tb_Downscale_SIMD_con_Memoria.sv`

## Verificación

Después de aplicar la solución, la compilación debe mostrar:

```
-- Compiling module ImageMemory_SequentialPort
Top level modules:
    ImageMemory_SequentialPort
End time: ...
Errors: 0, Warnings: ...

-- Compiling module Downscale_Secuencial
Top level modules:
    Downscale_Secuencial
End time: ...
Errors: 0, Warnings: ...
```

Y la simulación debe iniciarse sin errores.

## Notas Adicionales

- Los archivos ya están agregados al proyecto Quartus (commit: 15c12fb)
- Solo necesitas regenerar los scripts de simulación
- Si sigues teniendo problemas, verifica que las rutas en el script `.do` coincidan con la ubicación de tus archivos

## Archivos Modificados

- `ModoSecuencial.qsf` - Proyecto Quartus actualizado con los nuevos testbenches
