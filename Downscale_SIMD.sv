`timescale 1ns/1ps

module Downscale_SIMD #(
    parameter int SRC_H = 4,
    parameter int SRC_W = 4,
    parameter int DST_H = 3,
    parameter int DST_W = 3,
    parameter int N     = 4          // píxeles por batch SIMD
)(
    input  logic clk,
    input  logic rst,
    input  logic start,

    // Imagen de entrada HxW
    input  logic [7:0] image_in  [0:SRC_H-1][0:SRC_W-1],

    // Señal de fin y salida de imagen reducida
    output logic        done,
    output logic [7:0]  image_out[0:DST_H-1][0:DST_W-1]
);


    localparam int FRAC       = 8;
    localparam int X_RATIO_FP = ((SRC_W - 1) << FRAC) / (DST_W - 1);
    localparam int Y_RATIO_FP = ((SRC_H - 1) << FRAC) / (DST_H - 1);

    localparam int TOT_PIX    = DST_H * DST_W;
    localparam int IDX_BITS   = $clog2(TOT_PIX) + 1;
    localparam int COORD_BITS = $clog2(SRC_W > SRC_H ? SRC_W : SRC_H) + 1;
    localparam int DST_BITS   = $clog2(DST_W > DST_H ? DST_W : DST_H) + 1;


    // Señales hacia/desde Top_SIMD
    logic [7:0] I00_vec   [N];
    logic [7:0] I10_vec   [N];
    logic [7:0] I01_vec   [N];
    logic [7:0] I11_vec   [N];
    logic [7:0] alpha_vec [N];
    logic [7:0] beta_vec  [N];
    logic [7:0] pixel_out_vec [N];

    logic       top_start;
    logic       top_done;

    // Instancia del bloque SIMD
    Top_SIMD #(.N(N)) u_top_simd (
        .clk          (clk),
        .rst          (rst),
        .start        (top_start),
        .I00_vec      (I00_vec),
        .I10_vec      (I10_vec),
        .I01_vec      (I01_vec),
        .I11_vec      (I11_vec),
        .alpha_vec    (alpha_vec),
        .beta_vec     (beta_vec),
        .done         (top_done),
        .pixel_out_vec(pixel_out_vec)
    );


    // FSM
    typedef enum logic [2:0] {
        S_IDLE,
        S_PREP_BATCH,
        S_START_TOP,
        S_WAIT_TOP,
        S_WRITE_BATCH,
        S_DONE
    } state_t;

    state_t state;

    // Índice del primer píxel del batch actual
    logic [IDX_BITS-1:0] base_idx;


    // Para cada lane SIMD [0..N-1]
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


    genvar g;
    generate
        for (g = 0; g < N; g++) begin : gen_lanes
            always_comb begin
                // Índice lineal del píxel
                idx[g] = base_idx + g;
                
                // Verificar si este lane está activo
                valid_lane[g] = (idx[g] < TOT_PIX);

                if (valid_lane[g]) begin
                    // Convertir índice lineal a coordenadas 2D
                    // i_dst = idx / DST_W (división por constante)
                    // j_dst = idx % DST_W (módulo por constante)
                    i_dst[g] = idx[g] / DST_W;
                    j_dst[g] = idx[g] % DST_W;

                    // Calcular posición fuente en Q8.8
                    x_src_fp[g] = j_dst[g] * X_RATIO_FP;
                    y_src_fp[g] = i_dst[g] * Y_RATIO_FP;

                    // Floor
                    x_l[g] = x_src_fp[g][15:FRAC];
                    y_l[g] = y_src_fp[g][15:FRAC];

                    // Ceil (con saturación en borde)
                    x_h[g] = (x_l[g] < (SRC_W-1)) ? (x_l[g] + 1) : x_l[g];
                    y_h[g] = (y_l[g] < (SRC_H-1)) ? (y_l[g] + 1) : y_l[g];
                end else begin
                    // Lane inactivo - valores por defecto
                    i_dst[g]    = '0;
                    j_dst[g]    = '0;
                    x_src_fp[g] = '0;
                    y_src_fp[g] = '0;
                    x_l[g]      = '0;
                    y_l[g]      = '0;
                    x_h[g]      = '0;
                    y_h[g]      = '0;
                end
            end
        end
    endgenerate

    // FSM secuencial
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state     <= S_IDLE;
            base_idx  <= '0;
            done      <= 1'b0;
            top_start <= 1'b0;

            // Limpiar salida
            for (int i = 0; i < DST_H; i++)
                for (int j = 0; j < DST_W; j++)
                    image_out[i][j] <= 8'd0;

            // Limpiar vectores SIMD
            for (int k = 0; k < N; k++) begin
                I00_vec[k]   <= 8'd0;
                I10_vec[k]   <= 8'd0;
                I01_vec[k]   <= 8'd0;
                I11_vec[k]   <= 8'd0;
                alpha_vec[k] <= 8'd0;
                beta_vec[k]  <= 8'd0;
            end

        end else begin
            case (state)


                // IDLE
                S_IDLE: begin
                    done      <= 1'b0;
                    top_start <= 1'b0;
                    base_idx  <= '0;

                    if (start)
                        state <= S_PREP_BATCH;
                end


                // PREP_BATCH: Cargar datos para N píxeles
                S_PREP_BATCH: begin
                    // Usar lógica combinacional ya calculada
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            // Leer vecinos de la imagen
                            I00_vec[k] <= image_in[y_l[k]][x_l[k]];
                            I10_vec[k] <= image_in[y_l[k]][x_h[k]];
                            I01_vec[k] <= image_in[y_h[k]][x_l[k]];
                            I11_vec[k] <= image_in[y_h[k]][x_h[k]];

                            // Pesos fraccionales Q0.8
                            alpha_vec[k] <= x_src_fp[k][FRAC-1:0];
                            beta_vec[k]  <= y_src_fp[k][FRAC-1:0];
                        end else begin
                            // Lane inactivo
                            I00_vec[k]   <= 8'd0;
                            I10_vec[k]   <= 8'd0;
                            I01_vec[k]   <= 8'd0;
                            I11_vec[k]   <= 8'd0;
                            alpha_vec[k] <= 8'd0;
                            beta_vec[k]  <= 8'd0;
                        end
                    end

                    state <= S_START_TOP;
                end


                // START_TOP: Pulso de start
                S_START_TOP: begin
                    top_start <= 1'b1;
                    state     <= S_WAIT_TOP;
                end

 
                // WAIT_TOP: Esperar resultado
                S_WAIT_TOP: begin
                    top_start <= 1'b0;
                    if (top_done)
                        state <= S_WRITE_BATCH;
                end

                // WRITE_BATCH: Escribir resultados
                S_WRITE_BATCH: begin
                    for (int k = 0; k < N; k++) begin
                        if (valid_lane[k]) begin
                            image_out[i_dst[k]][j_dst[k]] <= pixel_out_vec[k];
                        end
                    end

                    //Si se acaban los pixeles
                    if (base_idx + N >= TOT_PIX) begin
                        done  <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        base_idx <= base_idx + N;
                        state    <= S_PREP_BATCH;
                    end
                end

                // DONE
                S_DONE: begin
                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule