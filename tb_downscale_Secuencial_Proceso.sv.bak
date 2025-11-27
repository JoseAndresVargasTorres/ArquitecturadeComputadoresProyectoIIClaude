`timescale 1ns/1ps

module tb_downscale_ModoSecuencial;

    // Parámetros de la imagen
    localparam int SRC_H  = 4;
    localparam int SRC_W  = 4;
    localparam int DST_H  = 3;
    localparam int DST_W  = 3;

    // Imagen fuente (4x4)
    logic [7:0] image [0:SRC_H-1][0:SRC_W-1];

    // Señales del DUT
    logic              clk;
    logic              rst;
    logic              valid_in;
    logic [7:0]        I00, I10, I01, I11;
    logic [7:0]        alpha, beta;   // Q0.8
    logic              valid_out;
    logic [7:0]        pixel_out;

    int unsigned pass_count = 0;
    int unsigned fail_count = 0;

    // Instancia del DUT
    ModoSecuencial dut (
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

    // ==========================
    // Clock
    // ==========================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // ==========================
    // Modelo de referencia basado en el algoritmo en el avance 1.
    // ==========================
    function automatic int bilinear_ref_pixel (
        input int a, b, c, d,
        input real x_weight, y_weight
    );
        real w00, w10, w01, w11;
        real pix_r;
        int  pix_i;
        begin
            w00 = (1.0 - x_weight) * (1.0 - y_weight);
            w10 = (       x_weight) * (1.0 - y_weight);
            w01 = (1.0 - x_weight) * (       y_weight);
            w11 = (       x_weight) * (       y_weight);

            pix_r = a*w00 + b*w10 + c*w01 + d*w11;

            // redondeo al entero más cercano
            pix_i = $rtoi(pix_r + 0.5);

            // saturación a [0,255]
            if (pix_i < 0)        pix_i = 0;
            else if (pix_i > 255) pix_i = 255;

            return pix_i;
        end
    endfunction

    // ==========================
    // Task para un píxel destino
    // ==========================
    task automatic run_pixel (
        input int i_dst, j_dst,
        input real x_ratio, y_ratio
    );
        // Coordenadas y pesos como en Python
        real x_src, y_src;
        int  x_l, x_h, y_l, y_h;
        real x_w, y_w;

        // Vecinos
        int a, b, c, d;
        int expected;
        int diff;

        // Alpha/Beta en Q0.8
        int alpha_int, beta_int;
        begin
            // 1) Coordenadas fuente (mismas fórmulas que en Python)
            x_src = x_ratio * j_dst;
            y_src = y_ratio * i_dst;

            // 2) floor y ceil
            x_l = int'($floor(x_src));
            x_h = int'($ceil (x_src));
            y_l = int'($floor(y_src));
            y_h = int'($ceil (y_src));

            // Clamp por seguridad
            if (x_l < 0)         x_l = 0;
            if (y_l < 0)         y_l = 0;
            if (x_h < 0)         x_h = 0;
            if (y_h < 0)         y_h = 0;
            if (x_l > SRC_W-1)   x_l = SRC_W-1;
            if (x_h > SRC_W-1)   x_h = SRC_W-1;
            if (y_l > SRC_H-1)   y_l = SRC_H-1;
            if (y_h > SRC_H-1)   y_h = SRC_H-1;

            // 3) Pesos (como en tu Python)
            x_w = x_src - x_l;
            y_w = y_src - y_l;

            // 4) Vecinos (a,b,c,d)
            a = image[y_l][x_l];
            b = image[y_l][x_h];
            c = image[y_h][x_l];
            d = image[y_h][x_h];

            // 5) Convertir pesos a Q0.8 (alpha/beta)
            alpha_int = int'(x_w * 256.0 + 0.5);
            beta_int  = int'(y_w * 256.0 + 0.5);

            if (alpha_int < 0)        alpha_int = 0;
            else if (alpha_int > 255) alpha_int = 255;
            if (beta_int  < 0)        beta_int  = 0;
            else if (beta_int  > 255) beta_int  = 255;

            // 6) Calcular referencia con el mismo (a,b,c,d,x_w,y_w)
            expected = bilinear_ref_pixel(a, b, c, d, x_w, y_w);

            $display("\n--- Pixel destino (%0d, %0d) ---", i_dst, j_dst);
            $display("  x_src=%.4f, y_src=%.4f", x_src, y_src);
            $display("  x_l=%0d, x_h=%0d, y_l=%0d, y_h=%0d",
                     x_l, x_h, y_l, y_h);
            $display("  x_w=%.4f, y_w=%.4f", x_w, y_w);
            $display("  a=%0d, b=%0d, c=%0d, d=%0d", a, b, c, d);
            $display("  alpha_int=%0d (%.4f), beta_int=%0d (%.4f)",
                     alpha_int, alpha_int/256.0,
                     beta_int,  beta_int/256.0);
            $display("  Esperado (ref) = %0d", expected);

            // 7) Alimentar DUT
            @(posedge clk);
            valid_in <= 1'b1;
            I00      <= a[7:0];
            I10      <= b[7:0];
            I01      <= c[7:0];
            I11      <= d[7:0];
            alpha    <= alpha_int[7:0];
            beta     <= beta_int[7:0];

            @(posedge clk);
            valid_in <= 1'b0;

            // Esperar a que el DUT declare salida válida
            wait (valid_out == 1'b1);
            // pixel_out estable aquí

            diff = pixel_out - expected;
            if (diff < 0) diff = -diff;

            $display("  pixel_out = %0d  (diff=%0d)", pixel_out, diff);

            if (diff <= 1) begin
                $display("  ✓ PASS (dentro de ±1 LSB)");
                pass_count++;
            end else begin
                $display("  ✗ FAIL (fuera de tolerancia)");
                fail_count++;
            end
        end
    endtask

    // ==========================
    // Inicialización y barrido tipo downscale()
    // ==========================
    initial begin
        int i, j;
        real x_ratio, y_ratio;

        // Imagen fuente 4x4
        image[0][0] =  10; image[0][1] =  30; image[0][2] =  50; image[0][3] =  70;
        image[1][0] =  90; image[1][1] = 110; image[1][2] = 130; image[1][3] = 150;
        image[2][0] = 170; image[2][1] = 190; image[2][2] = 210; image[2][3] = 230;
        image[3][0] = 240; image[3][1] = 245; image[3][2] = 250; image[3][3] = 255;

        $display("Imagen fuente 4x4:");
        for (i = 0; i < SRC_H; i++) begin
            $write("  ");
            for (j = 0; j < SRC_W; j++) begin
                $write("%0d ", image[i][j]);
            end
            $write("\n");
        end

        // Reset
        rst      = 1'b1;
        valid_in = 1'b0;
        I00 = 0; I10 = 0; I01 = 0; I11 = 0;
        alpha = 0; beta = 0;

        repeat (4) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);

        // Ratios como en tu Python:
        // x_ratio = (img_width - 1) / (new_w - 1)
        // y_ratio = (img_height - 1) / (new_h - 1)
        x_ratio = real'(SRC_W - 1) / real'(DST_W - 1);
        y_ratio = real'(SRC_H - 1) / real'(DST_H - 1);

        $display("\nRatios: x_ratio=%.4f, y_ratio=%.4f", x_ratio, y_ratio);

        // Barrido de toda la imagen destino
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                run_pixel(i, j, x_ratio, y_ratio);
            end
        end

        $display("\n=== FIN DOWNscale HW vs REF ===");
        $display("Resumen: PASS=%0d, FAIL=%0d", pass_count, fail_count);

        if (fail_count == 0)
            $display("TODOS los píxeles pasaron");
        else
            $fatal(1, "Hubo píxeles que fallaron");

        #20;
        $finish;
    end

    // Dump de ondas
    initial begin
        $dumpfile("tb_downscale_ModoSecuencial.vcd");
        $dumpvars(0, tb_downscale_ModoSecuencial);
    end

endmodule
