# Solución: Error "ImageMemory_SequentialPort not found" en ModelSim

## Problema
ModelSim no puede encontrar el módulo `ImageMemory_SequentialPort` porque el script de compilación `.do` está desactualizado.

## Causa
Los archivos `ImageMemory.sv` y `ImageMemory_SequentialPort.sv` están agregados al proyecto (.qsf líneas 80-81), pero el script de simulación no fue regenerado después de agregarlos.

## Solución: Regenerar Scripts de Simulación

### Opción 1: Desde Quartus GUI (Recomendado)

1. **Abrir el proyecto en Quartus Prime**
   - Abre `ModoSecuencial.qpf`

2. **Regenerar los scripts de simulación**
   - Ve a: `Processing > Start > Start Analysis & Elaboration`
   - O presiona el botón de "Analysis & Elaboration" en la barra de herramientas
   - Espera a que termine (puede tomar 1-2 minutos)

3. **Verificar que se regeneró el script**
   - Los archivos en `simulation/modelsim/` deberían actualizarse
   - Específicamente: `ModoSecuencial_run_msim_rtl_verilog.do`

4. **Volver a ejecutar la simulación**
   - Cierra ModelSim si está abierto
   - Ve a: `Tools > Run Simulation Tool > RTL Simulation`
   - O ejecuta desde línea de comandos:
     ```bash
     cd simulation/modelsim
     vsim -do ModoSecuencial_run_msim_rtl_verilog.do
     ```

### Opción 2: Desde Línea de Comandos

Si prefieres usar la línea de comandos de Quartus:

```bash
cd "C:\Users\josev\OneDrive\Documentos\Arqui2-Proyecto"
quartus_sh --flow compile ModoSecuencial -c ModoSecuencial
```

Esto ejecuta análisis y elaboración completo, regenerando los scripts.

### Opción 3: Compilación Manual en ModelSim (Temporal)

Si necesitas una solución rápida sin regenerar, puedes compilar manualmente en ModelSim:

1. Abre ModelSim
2. En la consola, ejecuta:
   ```tcl
   vlog -sv -work work +incdir+C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto ImageMemory.sv
   vlog -sv -work work +incdir+C:/Users/josev/OneDrive/Documentos/Arqui2-Proyecto ImageMemory_SequentialPort.sv
   ```
3. Luego ejecuta el testbench normalmente

**Nota:** Esta opción 3 es temporal y tendrás que repetirla cada vez que reinicies ModelSim.

## Verificación

Después de regenerar, el script `.do` debería incluir estas líneas:

```tcl
vlog -sv -work work +incdir+... ImageMemory.sv
vlog -sv -work work +incdir+... ImageMemory_SequentialPort.sv
```

Y la simulación debería ejecutarse sin el error "design unit was not found".

## Archivos Involucrados

- **Proyecto:** `ModoSecuencial.qpf` / `ModoSecuencial.qsf`
- **Script actual:** `simulation/modelsim/ModoSecuencial_run_msim_rtl_verilog.do`
- **Testbench:** `tb_Downscale_Secuencial_con_Memoria.sv`
- **Módulos requeridos:**
  - `ImageMemory.sv` (línea 80 del .qsf) ✓
  - `ImageMemory_SequentialPort.sv` (línea 81 del .qsf) ✓
  - `Downscale_Secuencial.sv` (línea 76 del .qsf) ✓
  - `ModoSecuencial.sv` (línea 71 del .qsf) ✓

## Resultado Esperado

Después de aplicar la solución, deberías ver:

```
# vlog -sv -work work +incdir+... ImageMemory.sv
# -- Compiling module ImageMemory
#
# vlog -sv -work work +incdir+... ImageMemory_SequentialPort.sv
# -- Compiling module ImageMemory_SequentialPort
#
# vsim ... tb_Downscale_Secuencial_con_Memoria
# Loading work.tb_Downscale_Secuencial_con_Memoria
# Loading work.ImageMemory_SequentialPort
# Loading work.ImageMemory
# Loading work.Downscale_Secuencial
# Loading work.ModoSecuencial
```

Y la simulación iniciará correctamente.
