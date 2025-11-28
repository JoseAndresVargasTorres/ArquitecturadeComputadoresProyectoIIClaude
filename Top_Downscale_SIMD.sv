// ======================================================
// Top_Downscale_SIMD.sv
// Integra: memoria SIMD + Downscale_SIMD + control
// Adaptacion entre BRAM y Downscale_SIMD
// ======================================================

module Top_Downscale_SIMD #(
    parameter int SRC_W = 32,
    parameter int SRC_H = 32,
    parameter int DST_W = 16,
    parameter int DST_H = 16,
    parameter int N     = 4          // Numero de pixeles procesados en paralelo
)(
    input  logic clk,
    input  logic rst,

    // ======== Interfaz tipo JTAG (simulada) ========
    input  logic        cfg_we,      // Aqui se escribe en BRAM
    input  logic [15:0] cfg_addr,
    input  logic [7:0]  cfg_data,

    input  logic        start_req,   // Aqui se inicia el procesamiento

    output logic        done,
    output logic [7:0]  dbg_data
);

    localparam int SRC_DEPTH = SRC_W * SRC_H;
    localparam int DST_DEPTH = DST_W * DST_H;
    localparam int ADDR_BITS = $clog2(SRC_DEPTH);

    // ==================================================
    // Memoria BRAM con puerto SIMD
    // ==================================================
    logic                   mem_rd_req   [N];
    logic [ADDR_BITS-1:0]   mem_rd_addr  [N];
    logic                   mem_rd_valid [N];
    logic [7:0]             mem_rd_data  [N];

    ImageMemory_SIMDPort #(
        .IMG_W(SRC_W),
        .IMG_H(SRC_H),
        .N(N)
    ) mem (
        .clk     (clk),
        .rst     (rst),
        .rd_req  (mem_rd_req),
        .rd_addr (mem_rd_addr),
        .rd_valid(mem_rd_valid),
        .rd_data (mem_rd_data),
        .we      (cfg_we),
        .wr_addr (cfg_addr[ADDR_BITS-1:0]),
        .wr_data (cfg_data)
    );

    // ==================================================
    // Arreglos 2D para interfaz con Downscale_SIMD
    // ==================================================
    logic [7:0] image_in  [0:SRC_H-1][0:SRC_W-1];
    logic [7:0] image_out [0:DST_H-1][0:DST_W-1];

    // ==================================================
    // Instancia de Downscale_SIMD
    // ==================================================
    logic downscale_start;
    logic downscale_done;

    Downscale_SIMD #(
        .SRC_H(SRC_H),
        .SRC_W(SRC_W),
        .DST_H(DST_H),
        .DST_W(DST_W),
        .N(N)
    ) u_downscale (
        .clk       (clk),
        .rst       (rst),
        .start     (downscale_start),
        .image_in  (image_in),
        .done      (downscale_done),
        .image_out (image_out)
    );

    // ==================================================
    // FSM para control
    // ==================================================
    typedef enum logic [2:0] {
        S_IDLE,
        S_LOAD_IMAGE,
        S_WAIT_LOAD,
        S_START_DOWNSCALE,
        S_WAIT_DOWNSCALE,
        S_WRITE_RESULTS,
        S_DONE
    } state_t;

    state_t state;

    // Contadores para carga y escritura
    logic [ADDR_BITS-1:0] load_addr;
    logic [ADDR_BITS-1:0] write_addr;
    logic [$clog2(SRC_H):0] load_row;
    logic [$clog2(SRC_W):0] load_col;
    logic [$clog2(DST_H):0] write_row;
    logic [$clog2(DST_W):0] write_col;

    // Variables temporales para calculo de coordenadas
    logic [$clog2(SRC_H):0] temp_row;
    logic [$clog2(SRC_W):0] temp_col;

    // ==================================================
    // FSM principal
    // ==================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= S_IDLE;
            done            <= 1'b0;
            downscale_start <= 1'b0;
            load_addr       <= '0;
            write_addr      <= '0;
            load_row        <= '0;
            load_col        <= '0;
            write_row       <= '0;
            write_col       <= '0;

            // Limpiar requests de memoria
            for (int k = 0; k < N; k++) begin
                mem_rd_req[k]  <= 1'b0;
                mem_rd_addr[k] <= '0;
            end

            // Limpiar arreglos
            for (int i = 0; i < SRC_H; i++)
                for (int j = 0; j < SRC_W; j++)
                    image_in[i][j] <= 8'd0;

        end else begin
            case (state)

                // ==================================
                // IDLE: Espera start
                // ==================================
                S_IDLE: begin
                    done            <= 1'b0;
                    downscale_start <= 1'b0;
                    load_addr       <= '0;
                    write_addr      <= SRC_DEPTH;  // Escribir en segunda mitad
                    load_row        <= '0;
                    load_col        <= '0;
                    write_row       <= '0;
                    write_col       <= '0;

                    for (int k = 0; k < N; k++)
                        mem_rd_req[k] <= 1'b0;

                    if (start_req)
                        state <= S_LOAD_IMAGE;
                end

                // ==================================
                // LOAD_IMAGE: Solicitar lectura de N pixeles
                // ==================================
                S_LOAD_IMAGE: begin
                    // Solicitar lectura de hasta N pixeles
                    for (int k = 0; k < N; k++) begin
                        if (load_addr + k < SRC_DEPTH) begin
                            mem_rd_req[k]  <= 1'b1;
                            mem_rd_addr[k] <= load_addr + k;
                        end else begin
                            mem_rd_req[k] <= 1'b0;
                        end
                    end
                    state <= S_WAIT_LOAD;
                end

                // ==================================
                // WAIT_LOAD: Esperar datos y almacenar
                // ==================================
                S_WAIT_LOAD: begin
                    // Bajar requests
                    for (int k = 0; k < N; k++)
                        mem_rd_req[k] <= 1'b0;

                    // Verificar si todos los datos validos llegaron
                    if (mem_rd_valid[0] || (load_addr >= SRC_DEPTH)) begin
                        logic all_ready;
                        all_ready = 1'b1;
                        for (int k = 0; k < N; k++) begin
                            if ((load_addr + k < SRC_DEPTH) && !mem_rd_valid[k])
                                all_ready = 1'b0;
                        end

                        if (all_ready) begin
                            // Almacenar datos en arreglo 2D
                            for (int k = 0; k < N; k++) begin
                                if (load_addr + k < SRC_DEPTH) begin
                                    temp_row = (load_addr + k) / SRC_W;
                                    temp_col = (load_addr + k) % SRC_W;
                                    image_in[temp_row][temp_col] <= mem_rd_data[k];
                                end
                            end

                            // Avanzar contador
                            load_addr <= load_addr + N;

                            // Verificar si terminamos de cargar
                            if (load_addr + N >= SRC_DEPTH)
                                state <= S_START_DOWNSCALE;
                            else
                                state <= S_LOAD_IMAGE;
                        end
                    end
                end

                // ==================================
                // START_DOWNSCALE: Iniciar Downscale_SIMD
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
                        write_row  <= '0;
                        write_col  <= '0;
                        write_addr <= SRC_DEPTH;
                        state      <= S_WRITE_RESULTS;
                    end
                end

                // ==================================
                // WRITE_RESULTS: Escribir resultados a BRAM
                // (Nota: en esta version simplificada no escribimos,
                //  solo marcamos como done)
                // ==================================
                S_WRITE_RESULTS: begin
                    // Por ahora solo marcamos como completado
                    // En una version completa, aqui escribiriamos
                    // los resultados de image_out a la memoria
                    done  <= 1'b1;
                    state <= S_DONE;
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

    // Aqui se asigna el dato de debug (primer pixel leido)
    assign dbg_data = mem_rd_data[0];

endmodule
