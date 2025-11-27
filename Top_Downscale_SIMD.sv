// ======================================================
// Top_Downscale_SIMD.sv
// Aqui se integra: memoria SIMD + downscale SIMD + control
// Similar a Top_Downscale_Secuencial pero con procesamiento paralelo
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

    // Formato Q8.8 para punto fijo
    localparam int FRAC       = 8;
    localparam int X_RATIO_FP = ((SRC_W - 1) << FRAC) / (DST_W - 1);
    localparam int Y_RATIO_FP = ((SRC_H - 1) << FRAC) / (DST_H - 1);

    localparam int COORD_BITS = $clog2(SRC_W > SRC_H ? SRC_W : SRC_H) + 1;
    localparam int DST_BITS   = $clog2(DST_W > DST_H ? DST_W : DST_H) + 1;
    localparam int IDX_BITS   = $clog2(DST_DEPTH) + 1;

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
    // Top SIMD para procesamiento paralelo
    // ==================================================
    logic [7:0] I00_vec   [N];
    logic [7:0] I10_vec   [N];
    logic [7:0] I01_vec   [N];
    logic [7:0] I11_vec   [N];
    logic [7:0] alpha_vec [N];
    logic [7:0] beta_vec  [N];
    logic [7:0] pixel_out_vec [N];
    logic       simd_start;
    logic       simd_done;

    Top_SIMD #(.N(N)) u_simd (
        .clk          (clk),
        .rst          (rst),
        .start        (simd_start),
        .I00_vec      (I00_vec),
        .I10_vec      (I10_vec),
        .I01_vec      (I01_vec),
        .I11_vec      (I11_vec),
        .alpha_vec    (alpha_vec),
        .beta_vec     (beta_vec),
        .done         (simd_done),
        .pixel_out_vec(pixel_out_vec)
    );

    // ==================================================
    // FSM para control del downscale SIMD
    // ==================================================
    typedef enum logic [3:0] {
        S_IDLE,
        S_CALC_COORDS,
        S_REQ_I00,
        S_WAIT_I00,
        S_REQ_I10,
        S_WAIT_I10,
        S_REQ_I01,
        S_WAIT_I01,
        S_REQ_I11,
        S_WAIT_I11,
        S_START_SIMD,
        S_WAIT_SIMD,
        S_WRITE_RESULTS,
        S_DONE
    } state_t;

    state_t state;

    // Aqui se guarda el indice del primer pixel del batch actual
    logic [IDX_BITS-1:0] base_idx;

    // Aqui se guardan las coordenadas y datos por cada lane SIMD
    logic [IDX_BITS-1:0]   idx       [N];
    logic [DST_BITS-1:0]   i_dst     [N];
    logic [DST_BITS-1:0]   j_dst     [N];
    logic [15:0]           x_src_fp  [N];
    logic [15:0]           y_src_fp  [N];
    logic [COORD_BITS-1:0] x_l       [N];
    logic [COORD_BITS-1:0] y_l       [N];
    logic [COORD_BITS-1:0] x_h       [N];
    logic [COORD_BITS-1:0] y_h       [N];
    logic                  valid_lane[N];

    // Aqui se almacenan temporalmente los pixeles leidos de memoria
    logic [7:0] pixel_I00 [N];
    logic [7:0] pixel_I10 [N];
    logic [7:0] pixel_I01 [N];
    logic [7:0] pixel_I11 [N];

    // Aqui se guardan las direcciones de escritura de los resultados
    logic [ADDR_BITS-1:0] write_addr [N];

    // ==================================================
    // Calculo de coordenadas por lane (combinacional)
    // ==================================================
    genvar g;
    generate
        for (g = 0; g < N; g++) begin : gen_coords
            always_comb begin
                // Aqui se calcula el indice lineal del pixel
                idx[g] = base_idx + g;

                // Aqui se verifica si este lane esta activo
                valid_lane[g] = (idx[g] < DST_DEPTH);

                if (valid_lane[g]) begin
                    // Aqui se convierte indice lineal a coordenadas 2D de destino
                    i_dst[g] = idx[g] / DST_W;
                    j_dst[g] = idx[g] % DST_W;

                    // Aqui se calcula la posicion fuente en Q8.8
                    x_src_fp[g] = j_dst[g] * X_RATIO_FP;
                    y_src_fp[g] = i_dst[g] * Y_RATIO_FP;

                    // Aqui se obtiene el floor de las coordenadas
                    x_l[g] = x_src_fp[g][15:FRAC];
                    y_l[g] = y_src_fp[g][15:FRAC];

                    // Aqui se obtiene el ceil con saturacion en el borde
                    x_h[g] = (x_l[g] < (SRC_W-1)) ? (x_l[g] + 1) : x_l[g];
                    y_h[g] = (y_l[g] < (SRC_H-1)) ? (y_l[g] + 1) : y_l[g];

                    // Aqui se calcula la direccion de escritura (en la segunda mitad de la memoria)
                    write_addr[g] = SRC_DEPTH + idx[g];
                end else begin
                    // Aqui se colocan valores por defecto para lanes inactivos
                    i_dst[g]       = '0;
                    j_dst[g]       = '0;
                    x_src_fp[g]    = '0;
                    y_src_fp[g]    = '0;
                    x_l[g]         = '0;
                    y_l[g]         = '0;
                    x_h[g]         = '0;
                    y_h[g]         = '0;
                    write_addr[g]  = '0;
                end
            end
        end
    endgenerate

    // ==================================================
    // FSM principal
    // ==================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= S_IDLE;
            base_idx   <= '0;
            done       <= 1'b0;
            simd_start <= 1'b0;

            // Aqui se limpian las requests de memoria
            for (int k = 0; k < N; k++) begin
                mem_rd_req[k]  <= 1'b0;
                mem_rd_addr[k] <= '0;
                I00_vec[k]     <= 8'd0;
                I10_vec[k]     <= 8'd0;
                I01_vec[k]     <= 8'd0;
                I11_vec[k]     <= 8'd0;
                alpha_vec[k]   <= 8'd0;
                beta_vec[k]    <= 8'd0;
                pixel_I00[k]   <= 8'd0;
                pixel_I10[k]   <= 8'd0;
                pixel_I01[k]   <= 8'd0;
                pixel_I11[k]   <= 8'd0;
            end

        end else begin
            case (state)

                // ==================================
                // IDLE: Aqui se espera la señal start
                // ==================================
                S_IDLE: begin
                    done       <= 1'b0;
                    simd_start <= 1'b0;
                    base_idx   <= '0;

                    // Aqui se limpian las requests
                    for (int k = 0; k < N; k++) begin
                        mem_rd_req[k] <= 1'b0;
                    end

                    if (start_req)
                        state <= S_CALC_COORDS;
                end

                // ==================================
                // CALC_COORDS: Aqui se calculan coordenadas
                // (las coordenadas ya estan en logica combinacional)
                // ==================================
                S_CALC_COORDS: begin
                    state <= S_REQ_I00;
                end

                // ==================================
                // REQ_I00: Aqui se solicitan los pixeles I00
                // ==================================
                S_REQ_I00: begin
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            mem_rd_req[k]  <= 1'b1;
                            mem_rd_addr[k] <= y_l[k] * SRC_W + x_l[k];
                        end else begin
                            mem_rd_req[k] <= 1'b0;
                        end
                    end
                    state <= S_WAIT_I00;
                end

                // ==================================
                // WAIT_I00: Aqui se esperan los datos I00
                // ==================================
                S_WAIT_I00: begin
                    mem_rd_req[0] <= 1'b0;  // Aqui se bajan las requests
                    for (int k = 1; k < N; k++) begin
                        mem_rd_req[k] <= 1'b0;
                    end

                    // Aqui se verifica si todos los lanes activos tienen datos validos
                    if (mem_rd_valid[0] || !valid_lane[0]) begin
                        logic all_ready;
                        all_ready = 1'b1;
                        for (int k = 0; k < N; k++) begin
                            if (valid_lane[k] && !mem_rd_valid[k])
                                all_ready = 1'b0;
                        end

                        if (all_ready) begin
                            // Aqui se guardan los datos
                            for (int k = 0; k < N; k++) begin
                                if (valid_lane[k])
                                    pixel_I00[k] <= mem_rd_data[k];
                            end
                            state <= S_REQ_I10;
                        end
                    end
                end

                // ==================================
                // REQ_I10: Aqui se solicitan los pixeles I10
                // ==================================
                S_REQ_I10: begin
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            mem_rd_req[k]  <= 1'b1;
                            mem_rd_addr[k] <= y_l[k] * SRC_W + x_h[k];
                        end else begin
                            mem_rd_req[k] <= 1'b0;
                        end
                    end
                    state <= S_WAIT_I10;
                end

                // ==================================
                // WAIT_I10: Aqui se esperan los datos I10
                // ==================================
                S_WAIT_I10: begin
                    for (int k = 0; k < N; k++) begin
                        mem_rd_req[k] <= 1'b0;
                    end

                    if (mem_rd_valid[0] || !valid_lane[0]) begin
                        logic all_ready;
                        all_ready = 1'b1;
                        for (int k = 0; k < N; k++) begin
                            if (valid_lane[k] && !mem_rd_valid[k])
                                all_ready = 1'b0;
                        end

                        if (all_ready) begin
                            for (int k = 0; k < N; k++) begin
                                if (valid_lane[k])
                                    pixel_I10[k] <= mem_rd_data[k];
                            end
                            state <= S_REQ_I01;
                        end
                    end
                end

                // ==================================
                // REQ_I01: Aqui se solicitan los pixeles I01
                // ==================================
                S_REQ_I01: begin
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            mem_rd_req[k]  <= 1'b1;
                            mem_rd_addr[k] <= y_h[k] * SRC_W + x_l[k];
                        end else begin
                            mem_rd_req[k] <= 1'b0;
                        end
                    end
                    state <= S_WAIT_I01;
                end

                // ==================================
                // WAIT_I01: Aqui se esperan los datos I01
                // ==================================
                S_WAIT_I01: begin
                    for (int k = 0; k < N; k++) begin
                        mem_rd_req[k] <= 1'b0;
                    end

                    if (mem_rd_valid[0] || !valid_lane[0]) begin
                        logic all_ready;
                        all_ready = 1'b1;
                        for (int k = 0; k < N; k++) begin
                            if (valid_lane[k] && !mem_rd_valid[k])
                                all_ready = 1'b0;
                        end

                        if (all_ready) begin
                            for (int k = 0; k < N; k++) begin
                                if (valid_lane[k])
                                    pixel_I01[k] <= mem_rd_data[k];
                            end
                            state <= S_REQ_I11;
                        end
                    end
                end

                // ==================================
                // REQ_I11: Aqui se solicitan los pixeles I11
                // ==================================
                S_REQ_I11: begin
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            mem_rd_req[k]  <= 1'b1;
                            mem_rd_addr[k] <= y_h[k] * SRC_W + x_h[k];
                        end else begin
                            mem_rd_req[k] <= 1'b0;
                        end
                    end
                    state <= S_WAIT_I11;
                end

                // ==================================
                // WAIT_I11: Aqui se esperan los datos I11
                // ==================================
                S_WAIT_I11: begin
                    for (int k = 0; k < N; k++) begin
                        mem_rd_req[k] <= 1'b0;
                    end

                    if (mem_rd_valid[0] || !valid_lane[0]) begin
                        logic all_ready;
                        all_ready = 1'b1;
                        for (int k = 0; k < N; k++) begin
                            if (valid_lane[k] && !mem_rd_valid[k])
                                all_ready = 1'b0;
                        end

                        if (all_ready) begin
                            for (int k = 0; k < N; k++) begin
                                if (valid_lane[k])
                                    pixel_I11[k] <= mem_rd_data[k];
                            end
                            state <= S_START_SIMD;
                        end
                    end
                end

                // ==================================
                // START_SIMD: Aqui se inicia el procesamiento SIMD
                // ==================================
                S_START_SIMD: begin
                    // Aqui se cargan los datos al SIMD
                    for (int k = 0; k < N; k++) begin
                        I00_vec[k]   <= pixel_I00[k];
                        I10_vec[k]   <= pixel_I10[k];
                        I01_vec[k]   <= pixel_I01[k];
                        I11_vec[k]   <= pixel_I11[k];
                        alpha_vec[k] <= x_src_fp[k][FRAC-1:0];  // Aqui se extrae la parte fraccionaria
                        beta_vec[k]  <= y_src_fp[k][FRAC-1:0];
                    end

                    simd_start <= 1'b1;
                    state      <= S_WAIT_SIMD;
                end

                // ==================================
                // WAIT_SIMD: Aqui se espera que el SIMD termine
                // ==================================
                S_WAIT_SIMD: begin
                    simd_start <= 1'b0;

                    if (simd_done) begin
                        state <= S_WRITE_RESULTS;
                    end
                end

                // ==================================
                // WRITE_RESULTS: Aqui se escriben los resultados
                // (nota: en esta version simplificada no escribimos a memoria,
                //  solo avanzamos al siguiente batch)
                // ==================================
                S_WRITE_RESULTS: begin
                    // Aqui se verifica si se procesaron todos los pixeles
                    if (base_idx + N >= DST_DEPTH) begin
                        done  <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        // Aqui se avanza al siguiente batch
                        base_idx <= base_idx + N;
                        state    <= S_CALC_COORDS;
                    end
                end

                // ==================================
                // DONE: Aqui se mantiene done hasta que start baje
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
