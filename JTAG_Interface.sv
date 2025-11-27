// ======================================================
// JTAG_Interface.sv
// Aqui se maneja la interfaz JTAG usando Avalon-MM
// Basado en GuiaJtag para comunicacion FPGA-PC
// ======================================================

module JTAG_Interface (
    input  logic clk,
    input  logic rst,

    // Aqui estan las señales de control para el sistema
    output logic        start,
    output logic        step,
    output logic        mode,           // 0=Secuencial, 1=SIMD
    output logic [31:0] param_x_ratio,
    output logic [31:0] param_y_ratio,

    // Aqui se escriben datos a la memoria de imagen
    output logic [31:0] img_write_addr,
    output logic [31:0] img_write_data,

    // Aqui se leen datos desde el sistema
    input  logic [31:0] img_read_data,
    input  logic        done_flag,
    input  logic [31:0] perf_counter,

    // Aqui esta la interfaz Avalon-MM (JTAG)
    input  logic        avs_read,
    input  logic        avs_write,
    input  logic [7:0]  avs_address,
    input  logic [31:0] avs_writedata,
    output logic [31:0] avs_readdata
);

    // ====================================================
    // Mapa de registros
    // ====================================================
    // 0x00: Control (bit 0: start, bit 1: step, bit 2: mode)
    // 0x01: param_x_ratio
    // 0x02: param_y_ratio
    // 0x03: img_write_addr
    // 0x04: img_write_data
    // 0x05: img_read_data (read-only)
    // 0x06: status (bit 0: done_flag) (read-only)
    // 0x07: perf_counter (read-only)

    // Aqui se definen los registros internos
    logic [31:0] reg_control;
    logic [31:0] reg_x_ratio;
    logic [31:0] reg_y_ratio;
    logic [31:0] reg_write_addr;
    logic [31:0] reg_write_data;

    // ====================================================
    // Escritura de registros
    // ====================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_control    <= 32'h0;
            reg_x_ratio    <= 32'h0;
            reg_y_ratio    <= 32'h0;
            reg_write_addr <= 32'h0;
            reg_write_data <= 32'h0;
        end else if (avs_write) begin
            case (avs_address)
                8'h00: reg_control    <= avs_writedata;
                8'h01: reg_x_ratio    <= avs_writedata;
                8'h02: reg_y_ratio    <= avs_writedata;
                8'h03: reg_write_addr <= avs_writedata;
                8'h04: reg_write_data <= avs_writedata;
                // Aqui los registros read-only no se escriben
                default: ;
            endcase
        end
    end

    // ====================================================
    // Lectura de registros
    // ====================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            avs_readdata <= 32'h0;
        end else if (avs_read) begin
            case (avs_address)
                8'h00: avs_readdata <= reg_control;
                8'h01: avs_readdata <= reg_x_ratio;
                8'h02: avs_readdata <= reg_y_ratio;
                8'h03: avs_readdata <= reg_write_addr;
                8'h04: avs_readdata <= reg_write_data;
                8'h05: avs_readdata <= img_read_data;       // Aqui se lee dato de imagen
                8'h06: avs_readdata <= {31'h0, done_flag};  // Aqui se lee el estado
                8'h07: avs_readdata <= perf_counter;        // Aqui se lee el contador
                default: avs_readdata <= 32'h0;
            endcase
        end
    end

    // ====================================================
    // Asignacion de señales de salida
    // ====================================================
    assign start          = reg_control[0];
    assign step           = reg_control[1];
    assign mode           = reg_control[2];
    assign param_x_ratio  = reg_x_ratio;
    assign param_y_ratio  = reg_y_ratio;
    assign img_write_addr = reg_write_addr;
    assign img_write_data = reg_write_data;

endmodule
