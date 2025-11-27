// =======================================================
// TOP GENERAL DEL PROYECTO — Basado en GuiaJtag
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
    // 2. Memoria BRAM única
    // ====================================================
    logic [$clog2(IMG_W*IMG_H)-1:0] bram_addr;
    logic [7:0] bram_rd_data;
    logic [7:0] bram_wr_data;
    logic       bram_we;

    ImageMemory #(.IMG_W(IMG_W), .IMG_H(IMG_H)) mem (
        .clk(clk),
        .we(bram_we),
        .addr(bram_addr),
        .wr_data(bram_wr_data),
        .rd_data(bram_rd_data)
    );

    // ====================================================
    // 3. Downscale (Secuencial o SIMD)
    // ====================================================
    logic fsm_mem_we;
    logic [$clog2(IMG_W*IMG_H)-1:0] fsm_mem_addr;
    logic [7:0] fsm_mem_wdata;
    logic start_fsm;
    logic done_fsm;

    Downscale_Secuencial u_down (
        .clk(clk),
        .rst(rst),

        .start(start),
        .done(done_fsm),

        .x_ratio(xratio_reg),
        .y_ratio(yratio_reg),

        .mem_read_data(bram_rd_data),
        .mem_read_addr(fsm_mem_addr),

        .mem_write_addr(fsm_mem_addr),
        .mem_write_data(fsm_mem_wdata),
        .mem_write_en(fsm_mem_we)
    );

    assign done_flag = done_fsm;

    // ====================================================
    // 4. Multiplexor BRAM según prioridad
    // ====================================================
    always_comb begin

        // Default
        bram_we      = 1'b0;
        bram_wr_data = 8'd0;
        bram_addr    = 0;

        if (avs_write) begin
            // JTAG escribe memoria
            bram_we      = 1'b1;
            bram_addr    = wr_addr_reg[$clog2(IMG_W*IMG_H)-1:0];
            bram_wr_data = wr_data_reg[7:0];  
        
        end else if (fsm_mem_we) begin
            // FSM escribe pixel procesado
            bram_we      = 1'b1;
            bram_addr    = fsm_mem_addr;
            bram_wr_data = fsm_mem_wdata;

        end else begin
            // FSM lee pixel
            bram_we      = 1'b0;
            bram_addr    = fsm_mem_addr;
        end
    end

    // Dato disponible para lectura JTAG
    assign rd_data_reg = {24'd0, bram_rd_data};

    // Counter de performance
    always_ff @(posedge clk or posedge rst) begin
        if (rst || start)
            perf_counter <= 0;
        else
            perf_counter <= perf_counter + 1;
    end

endmodule
