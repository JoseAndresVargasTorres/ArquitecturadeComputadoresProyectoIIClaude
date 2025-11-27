// =======================================================
// TOP GENERAL DEL PROYECTO — Basado en GuiaJtag
// Aqui se integran ambos modos: Secuencial y SIMD
// =======================================================
module Top_General #(
    parameter IMG_W = 512,
    parameter IMG_H = 512,
    parameter N     = 4
)(
    input  logic clk,
    input  logic rst,

    // Interfaz JTAG→Avalon-MM
    input  logic avs_read,
    input  logic avs_write,
    input  logic [7:0] avs_address,
    input  logic [31:0] avs_writedata,
    output logic [31:0] avs_readdata
);

    // ---------------------------------------------------
    // Señales desde JTAG Interface
    // ---------------------------------------------------
    logic start, step;
    logic [31:0] xratio_reg, yratio_reg;
    logic [31:0] wr_addr_reg, wr_data_reg;
    logic mode_reg;  // Aqui se selecciona el modo: 0=Secuencial, 1=SIMD

    logic [31:0] rd_data_reg;
    logic [31:0] perf_counter;
    logic done_flag;

    // ====================================================
    // 1. Banco de Registros Accesible por JTAG
    // ====================================================
    JTAG_Interface jtag (
        .clk(clk),
        .rst(rst),

        .start(start),
        .step(step),
        .mode(mode_reg),
        .param_x_ratio(xratio_reg),
        .param_y_ratio(yratio_reg),

        .img_write_addr(wr_addr_reg),
        .img_write_data(wr_data_reg),

        .img_read_data(rd_data_reg),
        .done_flag(done_flag),
        .perf_counter(perf_counter),

        .avs_read(avs_read),
        .avs_write(avs_write),
        .avs_address(avs_address),
        .avs_writedata(avs_writedata),
        .avs_readdata(avs_readdata)
    );

    // ====================================================
    // 2. Top Downscale Secuencial
    // ====================================================
    logic done_seq;
    logic [7:0] dbg_seq;

    Top_Downscale_Secuencial #(
        .SRC_W(IMG_W),
        .SRC_H(IMG_H),
        .DST_W(IMG_W/2),  // Factor de escala fijo para simplificar
        .DST_H(IMG_H/2)
    ) u_top_seq (
        .clk      (clk),
        .rst      (rst),
        .cfg_we   (avs_write && !mode_reg),  // Aqui se escribe solo si modo secuencial
        .cfg_addr (wr_addr_reg[15:0]),
        .cfg_data (wr_data_reg[7:0]),
        .start_req(start && !mode_reg),      // Aqui se inicia solo si modo secuencial
        .done     (done_seq),
        .dbg_data (dbg_seq)
    );

    // ====================================================
    // 3. Top Downscale SIMD
    // ====================================================
    logic done_simd;
    logic [7:0] dbg_simd;

    Top_Downscale_SIMD #(
        .SRC_W(IMG_W),
        .SRC_H(IMG_H),
        .DST_W(IMG_W/2),  // Factor de escala fijo para simplificar
        .DST_H(IMG_H/2),
        .N(N)
    ) u_top_simd (
        .clk      (clk),
        .rst      (rst),
        .cfg_we   (avs_write && mode_reg),  // Aqui se escribe solo si modo SIMD
        .cfg_addr (wr_addr_reg[15:0]),
        .cfg_data (wr_data_reg[7:0]),
        .start_req(start && mode_reg),      // Aqui se inicia solo si modo SIMD
        .done     (done_simd),
        .dbg_data (dbg_simd)
    );

    // ====================================================
    // 4. Multiplexado de señales de salida
    // ====================================================
    assign done_flag = mode_reg ? done_simd : done_seq;

    // Aqui se multiplexa el dato de debug segun el modo
    assign rd_data_reg = {24'd0, (mode_reg ? dbg_simd : dbg_seq)};

    // Aqui se cuenta el performance counter
    always_ff @(posedge clk or posedge rst) begin
        if (rst || start)
            perf_counter <= 0;
        else
            perf_counter <= perf_counter + 1;
    end

endmodule
