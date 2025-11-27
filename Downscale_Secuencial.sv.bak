`timescale 1ns/1ps

module Downscale_Secuencial #(
    parameter int SRC_H = 4,
    parameter int SRC_W = 4,
    parameter int DST_H = 3,
    parameter int DST_W = 3
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

    // ===============================
    // Formato fijo Q8.8
    // ===============================
    localparam int FRAC       = 8;
    localparam int ONE_FP     = 1 << FRAC;
    
    // Ratios en punto fijo Q8.8
    // x_ratio = (SRC_W-1) / (DST_W-1)
    localparam int X_RATIO_FP = ((SRC_W - 1) << FRAC) / (DST_W - 1);
    localparam int Y_RATIO_FP = ((SRC_H - 1) << FRAC) / (DST_H - 1);

    // Anchos de bits necesarios
    localparam int COORD_BITS = $clog2(SRC_W > SRC_H ? SRC_W : SRC_H) + 1;
    localparam int DST_I_BITS = $clog2(DST_H);
    localparam int DST_J_BITS = $clog2(DST_W);

    // ===============================
    // Señales hacia/desde ModoSecuencial
    // ===============================
    logic        valid_in;
    logic [7:0]  I00, I10, I01, I11;
    logic [7:0]  alpha, beta;
    logic        valid_out;
    logic [7:0]  pixel_out;

    // Instancia del interpolador
    ModoSecuencial u_secuencial (
        .clk       (clk),
        .rst       (rst),
        .valid_in  (valid_in),
        .I00       (I00),
        .I10       (I10),
        .I01       (I01),
        .I11       (I11),
        .alpha     (alpha),
        .beta      (beta),
        .valid_out (valid_out),
        .pixel_out (pixel_out)
    );

    // ===============================
    // FSM
    // ===============================
    typedef enum logic [1:0] {
        S_IDLE,
        S_SETUP,
        S_WAIT_RESULT,
        S_DONE
    } state_t;

    state_t state, next_state;

    // Coordenadas destino (registradas)
    logic [DST_I_BITS:0] i_dst;
    logic [DST_J_BITS:0] j_dst;

    // Señales combinacionales para cálculo de coordenadas fuente
    logic [15:0] x_src_fp, y_src_fp;  // Q8.8
    logic [COORD_BITS-1:0] x_l, x_h, y_l, y_h;
    
    // ===============================
    // Lógica combinacional: cálculo de coordenadas
    // ===============================
    always_comb begin
        // Posición fuente en Q8.8
        x_src_fp = j_dst * X_RATIO_FP;
        y_src_fp = i_dst * Y_RATIO_FP;

        // Floor (parte entera)
        x_l = x_src_fp[15:FRAC];
        y_l = y_src_fp[15:FRAC];

        // Ceil (floor + 1 si no estamos en el borde)
        x_h = (x_l < (SRC_W-1)) ? (x_l + 1) : x_l;
        y_h = (y_l < (SRC_H-1)) ? (y_l + 1) : y_l;
    end

    // ===============================
    // FSM secuencial
    // ===============================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state    <= S_IDLE;
            valid_in <= 1'b0;
            done     <= 1'b0;
            i_dst    <= 0;
            j_dst    <= 0;
            
            // Limpiar imagen de salida
            for (int i = 0; i < DST_H; i++)
                for (int j = 0; j < DST_W; j++)
                    image_out[i][j] <= 8'd0;
                    
        end else begin
            case (state)
                // ==================
                // IDLE: Esperar start
                // ==================
                S_IDLE: begin
                    done     <= 1'b0;
                    valid_in <= 1'b0;
                    if (start) begin
                        i_dst <= 0;
                        j_dst <= 0;
                        state <= S_SETUP;
                    end
                end

                // ==================
                // SETUP: Calcular coordenadas y vecinos
                // ==================
                S_SETUP: begin
                    // Asignar píxeles vecinos desde la imagen de entrada
                    I00 <= image_in[y_l][x_l];
                    I10 <= image_in[y_l][x_h];
                    I01 <= image_in[y_h][x_l];
                    I11 <= image_in[y_h][x_h];

                    // Pesos fraccionales (solo parte fraccional de x_src_fp, y_src_fp)
                    alpha <= x_src_fp[FRAC-1:0];  // Q0.8
                    beta  <= y_src_fp[FRAC-1:0];  // Q0.8

                    // Activar interpolador
                    valid_in <= 1'b1;
                    state    <= S_WAIT_RESULT;
                end

                // ==================
                // WAIT: Esperar resultado del interpolador
                // ==================
                S_WAIT_RESULT: begin
                    // Desactivar valid_in después de 1 ciclo
                    valid_in <= 1'b0;

                    if (valid_out) begin
                        // Guardar píxel en imagen de salida
                        image_out[i_dst][j_dst] <= pixel_out;

                        // ¿Último píxel?
                        if ((i_dst == (DST_H-1)) && (j_dst == (DST_W-1))) begin
                            done  <= 1'b1;
                            state <= S_DONE;
                        end else begin
                            // Avanzar al siguiente píxel
                            if (j_dst == (DST_W-1)) begin
                                j_dst <= 0;
                                i_dst <= i_dst + 1;
                            end else begin
                                j_dst <= j_dst + 1;
                            end
                            state <= S_SETUP;
                        end
                    end
                end

                // ==================
                // DONE: Mantener señal done hasta que start baje
                // ==================
                S_DONE: begin
                    if (!start)
                        state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule