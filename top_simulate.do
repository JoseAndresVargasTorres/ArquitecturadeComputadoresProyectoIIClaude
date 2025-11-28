# ==============================================================================
# Script de simulacion para ModelSim/QuestaSim
# Proyecto: Image Downscaling con Secuencial y SIMD
# ==============================================================================

# Limpiar trabajo previo
if {[file exists work]} {
    vdel -all
}

# Crear biblioteca de trabajo
vlib work
vmap work work

# ==============================================================================
# COMPILACION DE MODULOS BASE
# ==============================================================================
puts "Compilando modulos base..."

# Memoria base
vlog -sv -work work ImageMemory.sv

# Modo Secuencial (interpolacion bilineal)
vlog -sv -work work ModoSecuencial.sv

# Downscale Secuencial
vlog -sv -work work Downscale_Secuencial.sv

# ==============================================================================
# COMPILACION DE MODULOS SIMD
# ==============================================================================
puts "Compilando modulos SIMD..."

# FSM y registros SIMD
vlog -sv -work work FSM_SIMD.sv
vlog -sv -work work SIMD_Registros.sv

# Modo SIMD (N interpoladores en paralelo)
vlog -sv -work work ModoSIMD.sv

# Top SIMD (FSM + registros + modo SIMD)
vlog -sv -work work Top_SIMD.sv

# Downscale SIMD
vlog -sv -work work Downscale_SIMD.sv

# ==============================================================================
# COMPILACION DE MODULOS DE MEMORIA
# ==============================================================================
puts "Compilando modulos de memoria..."

# Puerto de memoria SIMD con cache
vlog -sv -work work ImageMemory_SIMDPort.sv

# Puerto de memoria secuencial
vlog -sv -work work ImageMemory_SequentialPort.sv

# ==============================================================================
# COMPILACION DE TOPS
# ==============================================================================
puts "Compilando modulos top..."

# Top Downscale Secuencial
vlog -sv -work work Top_Downscale_Secuencial.sv

# Top Downscale SIMD
vlog -sv -work work Top_Downscale_SIMD.sv

# JTAG Interface
vlog -sv -work work JTAG_Interface.sv

# Top General (integra secuencial y SIMD)
vlog -sv -work work Top_General.sv

# ==============================================================================
# COMPILACION DE TESTBENCHES
# ==============================================================================
puts "Compilando testbenches..."

# Testbenches de modulos individuales
vlog -sv -work work tb_Downscale_Secuencial.sv
vlog -sv -work work tb_Downscale_SIMD.sv
vlog -sv -work work tb_ImageMemory_SIMDPort.sv
vlog -sv -work work tb_downscale_Secuencial_Proceso.sv
vlog -sv -work work tb_downscale_SIMD_Proceso.sv

# Testbenches de tops
vlog -sv -work work tb_Top_Downscale_Secuencial.sv
vlog -sv -work work tb_Top_Downscale_SIMD.sv

puts "Compilacion completada exitosamente!"

# ==============================================================================
# PROCEDIMIENTOS DE SIMULACION
# ==============================================================================

proc sim_top_secuencial {} {
    puts "=========================================="
    puts "Ejecutando: tb_Top_Downscale_Secuencial"
    puts "=========================================="

    vsim -voptargs=+acc work.tb_Top_Downscale_Secuencial

    # Agregar señales al visor de ondas
    add wave -divider "Clock y Reset"
    add wave sim:/tb_Top_Downscale_Secuencial/clk
    add wave sim:/tb_Top_Downscale_Secuencial/rst

    add wave -divider "Interfaz JTAG"
    add wave sim:/tb_Top_Downscale_Secuencial/cfg_we
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/cfg_addr
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/cfg_data
    add wave sim:/tb_Top_Downscale_Secuencial/start_req
    add wave sim:/tb_Top_Downscale_Secuencial/done
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/dbg_data

    add wave -divider "FSM Interna"
    add wave sim:/tb_Top_Downscale_Secuencial/dut/state
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/dut/load_addr
    add wave sim:/tb_Top_Downscale_Secuencial/dut/downscale_start
    add wave sim:/tb_Top_Downscale_Secuencial/dut/downscale_done

    add wave -divider "Downscale Secuencial"
    add wave sim:/tb_Top_Downscale_Secuencial/dut/u_seq/state
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/dut/u_seq/i_dst
    add wave -radix unsigned sim:/tb_Top_Downscale_Secuencial/dut/u_seq/j_dst

    # Ejecutar simulacion
    run -all
}

proc sim_top_simd {} {
    puts "=========================================="
    puts "Ejecutando: tb_Top_Downscale_SIMD"
    puts "=========================================="

    vsim -voptargs=+acc work.tb_Top_Downscale_SIMD

    # Agregar señales al visor de ondas
    add wave -divider "Clock y Reset"
    add wave sim:/tb_Top_Downscale_SIMD/clk
    add wave sim:/tb_Top_Downscale_SIMD/rst

    add wave -divider "Interfaz JTAG"
    add wave sim:/tb_Top_Downscale_SIMD/cfg_we
    add wave -radix unsigned sim:/tb_Top_Downscale_SIMD/cfg_addr
    add wave -radix unsigned sim:/tb_Top_Downscale_SIMD/cfg_data
    add wave sim:/tb_Top_Downscale_SIMD/start_req
    add wave sim:/tb_Top_Downscale_SIMD/done
    add wave -radix unsigned sim:/tb_Top_Downscale_SIMD/dbg_data

    add wave -divider "FSM Interna"
    add wave sim:/tb_Top_Downscale_SIMD/dut/state
    add wave -radix unsigned sim:/tb_Top_Downscale_SIMD/dut/load_addr
    add wave sim:/tb_Top_Downscale_SIMD/dut/downscale_start
    add wave sim:/tb_Top_Downscale_SIMD/dut/downscale_done

    add wave -divider "Downscale SIMD"
    add wave sim:/tb_Top_Downscale_SIMD/dut/u_downscale/state
    add wave -radix unsigned sim:/tb_Top_Downscale_SIMD/dut/u_downscale/base_idx

    # Ejecutar simulacion
    run -all
}

proc sim_downscale_secuencial {} {
    puts "=========================================="
    puts "Ejecutando: tb_Downscale_Secuencial"
    puts "=========================================="

    vsim -voptargs=+acc work.tb_Downscale_Secuencial

    add wave -divider "Testbench"
    add wave sim:/tb_Downscale_Secuencial/clk
    add wave sim:/tb_Downscale_Secuencial/rst
    add wave sim:/tb_Downscale_Secuencial/start
    add wave sim:/tb_Downscale_Secuencial/done

    add wave -divider "FSM"
    add wave sim:/tb_Downscale_Secuencial/dut/state
    add wave -radix unsigned sim:/tb_Downscale_Secuencial/dut/i_dst
    add wave -radix unsigned sim:/tb_Downscale_Secuencial/dut/j_dst

    run -all
}

proc sim_downscale_simd {} {
    puts "=========================================="
    puts "Ejecutando: tb_Downscale_SIMD"
    puts "=========================================="

    vsim -voptargs=+acc work.tb_Downscale_SIMD

    add wave -divider "Testbench"
    add wave sim:/tb_Downscale_SIMD/clk
    add wave sim:/tb_Downscale_SIMD/rst
    add wave sim:/tb_Downscale_SIMD/start
    add wave sim:/tb_Downscale_SIMD/done

    add wave -divider "FSM"
    add wave sim:/tb_Downscale_SIMD/dut/state
    add wave -radix unsigned sim:/tb_Downscale_SIMD/dut/base_idx

    run -all
}

proc sim_memory_simd {} {
    puts "=========================================="
    puts "Ejecutando: tb_ImageMemory_SIMDPort"
    puts "=========================================="

    vsim -voptargs=+acc work.tb_ImageMemory_SIMDPort

    add wave -divider "Testbench"
    add wave sim:/tb_ImageMemory_SIMDPort/clk
    add wave sim:/tb_ImageMemory_SIMDPort/rst

    add wave -divider "Requests"
    add wave sim:/tb_ImageMemory_SIMDPort/rd_req
    add wave -radix unsigned sim:/tb_ImageMemory_SIMDPort/rd_addr
    add wave sim:/tb_ImageMemory_SIMDPort/rd_valid
    add wave -radix unsigned sim:/tb_ImageMemory_SIMDPort/rd_data

    run -all
}

# ==============================================================================
# MENU DE OPCIONES
# ==============================================================================

puts ""
puts "=========================================="
puts "Script de Simulacion Cargado"
puts "=========================================="
puts "Comandos disponibles:"
puts "  sim_top_secuencial   - Simular Top Secuencial completo"
puts "  sim_top_simd         - Simular Top SIMD completo"
puts "  sim_downscale_secuencial - Simular modulo Downscale Secuencial"
puts "  sim_downscale_simd   - Simular modulo Downscale SIMD"
puts "  sim_memory_simd      - Simular memoria con puerto SIMD"
puts ""
puts "Ejemplo de uso:"
puts "  ModelSim> sim_top_secuencial"
puts "  ModelSim> sim_top_simd"
puts "=========================================="
puts ""

# Ejecutar simulacion por defecto (opcional)
# Descomentar la siguiente linea para ejecutar automaticamente
# sim_top_secuencial
