`timescale 1ns/1ps

module tb_Downscale_Secuencial;

    // Parámetros de prueba
    localparam int SRC_H = 4;
    localparam int SRC_W = 4;
    localparam int DST_H = 3;
    localparam int DST_W = 3;

    logic clk, rst, start;
    logic done;

    // Imagen de entrada/salida vistas desde el TB
    logic [7:0] image_in  [0:SRC_H-1][0:SRC_W-1];
    logic [7:0] image_out [0:DST_H-1][0:DST_W-1];

    int pass_count = 0;
    int fail_count = 0;

    // =============================
    // Instancia del DUT
    // =============================
    Downscale_Secuencial #(
        .SRC_H(SRC_H),
        .SRC_W(SRC_W),
        .DST_H(DST_H),
        .DST_W(DST_W)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .image_in (image_in),
        .done     (done),
        .image_out(image_out)
    );

    // =============================
    // Clock
    // =============================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // =============================
    // Modelo de referencia en REAL
    // (igual al Python que pusiste)
    // =============================
    function automatic int bilinear_ref(
        input int a, b, c, d,
        input real xw, yw
    );
        real w00, w10, w01, w11;
        real pix_r;
        int  pix_i;
        begin
            w00 = (1.0 - xw) * (1.0 - yw);
            w10 = (      xw) * (1.0 - yw);
            w01 = (1.0 - xw) * (      yw);
            w11 = (      xw) * (      yw);

            pix_r = a*w00 + b*w10 + c*w01 + d*w11;
            pix_i = $rtoi(pix_r + 0.5);

            if (pix_i < 0)      pix_i = 0;
            else if (pix_i > 255) pix_i = 255;

            return pix_i;
        end
    endfunction

    // =============================
    // Test principal
    // =============================
    initial begin
        int i, j;
        real x_ratio, y_ratio;
        real x_src, y_src;
        int  x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int  a, b, c, d;
        int  expected [0:DST_H-1][0:DST_W-1];
        int  diff;

        // Imagen 4x4
        image_in[0][0] =  10; image_in[0][1] =  30; image_in[0][2] =  50; image_in[0][3] =  70;
        image_in[1][0] =  90; image_in[1][1] = 110; image_in[1][2] = 130; image_in[1][3] = 150;
        image_in[2][0] = 170; image_in[2][1] = 190; image_in[2][2] = 210; image_in[2][3] = 230;
        image_in[3][0] = 240; image_in[3][1] = 245; image_in[3][2] = 250; image_in[3][3] = 255;

        $display("Imagen fuente 4x4:");
        for (i = 0; i < SRC_H; i++) begin
            $write("  ");
            for (j = 0; j < SRC_W; j++) begin
                $write("%0d ", image_in[i][j]);
            end
            $write("\n");
        end

        // Ratios como en el código Python
        x_ratio = real'(SRC_W - 1) / real'(DST_W - 1);
        y_ratio = real'(SRC_H - 1) / real'(DST_H - 1);

        $display("\nRatios: x_ratio=%.4f, y_ratio=%.4f", x_ratio, y_ratio);

        // Calcular referencia completa
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                x_src = x_ratio * j;
                y_src = y_ratio * i;

                x_l = int'($floor(x_src));
                x_h = int'($ceil (x_src));
                y_l = int'($floor(y_src));
                y_h = int'($ceil (y_src));

                x_w = x_src - x_l;
                y_w = y_src - y_l;

                a = image_in[y_l][x_l];
                b = image_in[y_l][x_h];
                c = image_in[y_h][x_l];
                d = image_in[y_h][x_h];

                expected[i][j] = bilinear_ref(a,b,c,d,x_w,y_w);

                $display("\nRef pixel (%0d,%0d):", i, j);
                $display("  x_src=%.4f y_src=%.4f", x_src, y_src);
                $display("  x_l=%0d x_h=%0d  y_l=%0d y_h=%0d", x_l,x_h,y_l,y_h);
                $display("  x_w=%.4f y_w=%.4f", x_w, y_w);
                $display("  a=%0d b=%0d c=%0d d=%0d", a,b,c,d);
                $display("  expected=%0d", expected[i][j]);
            end
        end

        // Reset
        rst   = 1'b1;
        start = 1'b0;
        repeat(4) @(posedge clk);
        rst = 1'b0;

        // Lanzar downscale en HW
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Esperar a que termine
        wait(done == 1'b1);

        // Comparar resultados
        $display("\n=== COMPARACIÓN HW vs REF ===");
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                diff = image_out[i][j] - expected[i][j];
                if (diff < 0) diff = -diff;

                $display("Pixel (%0d,%0d): HW=%0d REF=%0d diff=%0d",
                         i, j, image_out[i][j], expected[i][j], diff);

                if (diff <= 1) begin
                    pass_count++;
                end else begin
                    fail_count++;
                end
            end
        end

        $display("\nResumen: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("TODOS los píxeles pasaron (±1 LSB).");
        else
            $display("Hay diferencias fuera de tolerancia.");

        #20;
        $finish;
    end

    // Dump opcional
    initial begin
        $dumpfile("tb_Downscale_Secuencial.vcd");
        $dumpvars(0, tb_Downscale_Secuencial);
    end

endmodule
