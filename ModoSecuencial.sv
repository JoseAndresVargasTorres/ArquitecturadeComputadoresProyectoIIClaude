module ModoSecuencial (
    input  logic              clk,
    input  logic              rst,
    input  logic              valid_in,
    input  logic [7:0]        I00, I10, I01, I11,  // píxeles 8 bits [0-255]
    input  logic [7:0]        alpha, beta,         // Q0.8: 0x00=0.0, 0xFF≈0.996
    output logic              valid_out,
    output logic [7:0]        pixel_out            // píxel resultante [0-255]
);
    // =========================
    // ETAPA 1: Extensión a Q8.8
    // =========================
    logic [15:0] I00_q, I10_q, I01_q, I11_q;  // Sin signo para píxeles
    logic [15:0] alpha_q, beta_q;              // Sin signo para coeficientes
    
    always_comb begin
        // Píxeles: entero 8 bits → Q8.8 (shift left 8)
        I00_q = {I00, 8'h00};
        I10_q = {I10, 8'h00};
        I01_q = {I01, 8'h00};
        I11_q = {I11, 8'h00};
        
        // Alpha/Beta: Q0.8 → Q8.8 (parte entera = 0)
        alpha_q = {8'h00, alpha};
        beta_q  = {8'h00, beta};
    end
    
    // =========================
    // ETAPA 2: Interpolación horizontal
    //    a = I00 + alpha * (I10 - I00)
    //    b = I01 + alpha * (I11 - I01)
    // =========================
    logic signed [16:0] diff_x0, diff_x1;     // 17 bits con signo para diferencias
    logic [31:0]        mult_ax, mult_bx;     // 32 bits sin signo para productos
    logic [15:0]        term_ax, term_bx;     // 16 bits sin signo
    logic [15:0]        a_q, b_q;             // 16 bits sin signo
    
    always_comb begin
        // Diferencias (pueden ser negativas)
        diff_x0 = $signed({1'b0, I10_q}) - $signed({1'b0, I00_q});
        diff_x1 = $signed({1'b0, I11_q}) - $signed({1'b0, I01_q});
        
        // Multiplicación: Q8.8 * Q8.8 = Q16.16
        // Manejar signo correctamente
        if (diff_x0 < 0) begin
            mult_ax = (-diff_x0) * alpha_q;
            term_ax = mult_ax[23:8];
            a_q = I00_q - term_ax;
        end else begin
            mult_ax = diff_x0 * alpha_q;
            term_ax = mult_ax[23:8];
            a_q = I00_q + term_ax;
        end
        
        if (diff_x1 < 0) begin
            mult_bx = (-diff_x1) * alpha_q;
            term_bx = mult_bx[23:8];
            b_q = I01_q - term_bx;
        end else begin
            mult_bx = diff_x1 * alpha_q;
            term_bx = mult_bx[23:8];
            b_q = I01_q + term_bx;
        end
    end
    
    // =========================
    // ETAPA 3: Interpolación vertical
    //    v = a + beta * (b - a)
    // =========================
    logic signed [16:0] diff_y;               // 17 bits con signo
    logic [31:0]        mult_by;              // 32 bits sin signo
    logic [15:0]        term_by;              // 16 bits sin signo
    logic [15:0]        v_q;                  // 16 bits sin signo
    
    always_comb begin
        diff_y = $signed({1'b0, b_q}) - $signed({1'b0, a_q});
        
        if (diff_y < 0) begin
            mult_by = (-diff_y) * beta_q;
            term_by = mult_by[23:8];
            v_q = a_q - term_by;
        end else begin
            mult_by = diff_y * beta_q;
            term_by = mult_by[23:8];
            v_q = a_q + term_by;
        end
    end
    
    // =========================
    // ETAPA 4: Redondeo y conversión a 8 bits
    // =========================
    logic [16:0] v_rounded;                   // 17 bits para sumar 0.5
    logic [8:0]  pixel_int;                   // 9 bits para detectar overflow
    logic [7:0]  pixel_clamped;
    
    always_comb begin
        // Sumar 0.5 en Q8.8 → 0x0080 (128 decimal)
        v_rounded = {1'b0, v_q} + 17'h0080;
        
        // Extraer parte entera (shift right 8)
        pixel_int = v_rounded[16:8];
        
        // Saturación a [0, 255]
        if (pixel_int > 9'd255)
            pixel_clamped = 8'd255;
        else
            pixel_clamped = pixel_int[7:0];
    end
    
    // =========================
    // ETAPA 5: Registro de salida
    // =========================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            valid_out <= 1'b0;
            pixel_out <= 8'd0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                pixel_out <= pixel_clamped;
            end
        end
    end

endmodule