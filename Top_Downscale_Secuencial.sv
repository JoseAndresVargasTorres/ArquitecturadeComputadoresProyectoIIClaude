// ======================================================
// Top_Downscale_Secuencial.sv
//  · Incluye: memoria + downscale secuencial + control
// ======================================================

module Top_Downscale_Secuencial #(
    parameter int SRC_W = 32,
    parameter int SRC_H = 32,
    parameter int DST_W = 16,
    parameter int DST_H = 16
)(
    input  logic clk,
    input  logic rst,

    // ======== interfaz tipo JTAG (simulada) ========
    input  logic        cfg_we,      // escribir en BRAM
    input  logic [15:0] cfg_addr,
    input  logic [7:0]  cfg_data,

    input  logic        start_req,   // iniciar procesamiento

    output logic        done,
    output logic [7:0]  dbg_data
);

    localparam int DEPTH = SRC_W * SRC_H;

    // ==================================================
    // Memoria BRAM
    // ==================================================
    logic bram_we;
    logic [7:0] bram_wr_data;
    logic [15:0] bram_addr;
    logic [7:0] bram_rd_data;

    ImageMemory #(
        .IMG_W(SRC_W),
        .IMG_H(SRC_H)
    ) mem (
        .clk(clk),
        .we(bram_we),
        .addr(bram_addr),
        .wr_data(bram_wr_data),
        .rd_data(bram_rd_data)
    );

    // ==================================================
    // Arreglos 2D para interfaz con Downscale_Secuencial
    // ==================================================
    logic [7:0] image_in  [0:SRC_H-1][0:SRC_W-1];
    logic [7:0] image_out [0:DST_H-1][0:DST_W-1];

    // ==================================================
    // Instancia de Downscale_Secuencial
    // ==================================================
    logic downscale_start;
    logic downscale_done;

    Downscale_Secuencial #(
        .SRC_W(SRC_W), .SRC_H(SRC_H),
        .DST_W(DST_W), .DST_H(DST_H)
    ) u_seq (
        .clk(clk),
        .rst(rst),
        .start(downscale_start),
        .image_in(image_in),
        .image_out(image_out),
        .done(downscale_done)
    );

    // ==================================================
    // FSM para control de carga y procesamiento
    // ==================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_LOAD_IMAGE,
        S_START_DOWNSCALE,
        S_WAIT_DOWNSCALE,
        S_DONE
    } state_t;

    state_t state;

    // Contador para carga secuencial
    logic [15:0] load_addr;
    logic [15:0] prev_addr;
    logic [$clog2(SRC_H):0] row;
    logic [$clog2(SRC_W):0] col;

    // ==================================================
    // FSM principal
    // ==================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_IDLE;
            done            <= 1'b0;
            downscale_start <= 1'b0;
            load_addr       <= '0;
            bram_we         <= 1'b0;
            bram_addr       <= '0;
            bram_wr_data    <= '0;

            // Limpiar arreglo de entrada
            for (int i = 0; i < SRC_H; i++)
                for (int j = 0; j < SRC_W; j++)
                    image_in[i][j] <= 8'd0;

        end else begin
            // Manejo de escritura desde JTAG (siempre activo)
            bram_we      <= cfg_we;
            bram_addr    <= cfg_we ? cfg_addr : load_addr;
            bram_wr_data <= cfg_data;

            case (state)

                // ==================================
                // IDLE: Espera start_req
                // ==================================
                S_IDLE: begin
                    done            <= 1'b0;
                    downscale_start <= 1'b0;
                    load_addr       <= '0;

                    if (start_req)
                        state <= S_LOAD_IMAGE;
                end

                // ==================================
                // LOAD_IMAGE: Leer BRAM y llenar image_in
                // ==================================
                S_LOAD_IMAGE: begin
                    if (load_addr < DEPTH) begin
                        // Esperar un ciclo para lectura sincrónica de BRAM
                        // El dato estara disponible en el siguiente ciclo
                        if (load_addr > 0) begin
                            // Almacenar dato leido en ciclo anterior
                            prev_addr = load_addr - 1;
                            row = prev_addr / SRC_W;
                            col = prev_addr % SRC_W;
                            image_in[row][col] <= bram_rd_data;
                        end

                        // Avanzar direccion de lectura
                        load_addr <= load_addr + 1;
                    end else begin
                        // Ultima lectura
                        if (load_addr == DEPTH) begin
                            row = (DEPTH-1) / SRC_W;
                            col = (DEPTH-1) % SRC_W;
                            image_in[row][col] <= bram_rd_data;
                            load_addr <= load_addr + 1;
                        end else begin
                            state <= S_START_DOWNSCALE;
                        end
                    end
                end

                // ==================================
                // START_DOWNSCALE: Iniciar procesamiento
                // ==================================
                S_START_DOWNSCALE: begin
                    downscale_start <= 1'b1;
                    state           <= S_WAIT_DOWNSCALE;
                end

                // ==================================
                // WAIT_DOWNSCALE: Esperar que termine
                // ==================================
                S_WAIT_DOWNSCALE: begin
                    downscale_start <= 1'b0;
                    if (downscale_done) begin
                        done  <= 1'b1;
                        state <= S_DONE;
                    end
                end

                // ==================================
                // DONE: Mantener done hasta que start baje
                // ==================================
                S_DONE: begin
                    if (!start_req)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

    assign dbg_data = bram_rd_data;

endmodule
