`timescale 1ns/1ps

module tb_Downscale_SIMD;

    localparam int SRC_H = 4;
    localparam int SRC_W = 4;
    localparam int DST_H = 3;
    localparam int DST_W = 3;
    localparam int N     = 4;

    logic clk, rst, start;

    // Imagen de entrada y salida
    logic [7:0] image_in [0:SRC_H-1][0:SRC_W-1];
    logic [7:0] image_out[0:DST_H-1][0:DST_W-1];

    logic done;

    // Instancia del DUT
    Downscale_SIMD #(
        .SRC_H(SRC_H),
        .SRC_W(SRC_W),
        .DST_H(DST_H),
        .DST_W(DST_W),
        .N    (N)
    ) dut (
        .clk      (clk),
        .rst      (rst),
        .start    (start),
        .image_in (image_in),
        .done     (done),
        .image_out(image_out)
    );

    // Clock
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Función de referencia (igual que en Python, pero en real)
    function automatic int bilinear_ref_pixel(
        input int a, b, c, d,
        input real xw, yw
    );
        real w00 = (1.0 - xw)*(1.0 - yw);
        real w10 =  xw       *(1.0 - yw);
        real w01 = (1.0 - xw)*yw;
        real w11 =  xw       *yw;
        real r   = a*w00 + b*w10 + c*w01 + d*w11;
        int pix  = $rtoi(r + 0.5);

        if (pix < 0)   pix = 0;
        if (pix > 255) pix = 255;
        return pix;
    endfunction

    // MAIN TB
    initial begin
        int i, j;
        real x_ratio, y_ratio;
        real x_src, y_src;
        int x_l, x_h, y_l, y_h;
        real x_w, y_w;
        int a,b,c,d;
        int expected[DST_H][DST_W];
        int diff;
        int pass_count = 0;
        int fail_count = 0;

        // Imagen fuente 4x4
        image_in[0] = '{10, 30, 50, 70};
        image_in[1] = '{90, 110,130,150};
        image_in[2] = '{170,190,210,230};
        image_in[3] = '{240,245,250,255};

        // Ratios reales
        x_ratio = real'(SRC_W - 1) / real'(DST_W - 1);
        y_ratio = real'(SRC_H - 1) / real'(DST_H - 1);

        $display("Imagen fuente 4x4:");
        for (i = 0; i < SRC_H; i++) begin
            $write("  ");
            for (j = 0; j < SRC_W; j++) begin
                $write("%0d ", image_in[i][j]);
            end
            $write("\n");
        end
        $display("");
        $display("Ratios: x_ratio=%0.4f, y_ratio=%0.4f", x_ratio, y_ratio);

        // Calcular referencia 3x3
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                x_src = x_ratio * j;
                y_src = y_ratio * i;

                x_l = int'($floor(x_src));
                y_l = int'($floor(y_src));
                x_h = int'($ceil(x_src));
                y_h = int'($ceil(y_src));

                x_w = x_src - x_l;
                y_w = y_src - y_l;

                a = image_in[y_l][x_l];
                b = image_in[y_l][x_h];
                c = image_in[y_h][x_l];
                d = image_in[y_h][x_h];

                expected[i][j] = bilinear_ref_pixel(a,b,c,d,x_w,y_w);

                $display("\nRef pixel (%0d,%0d):", i, j);
                $display("  x_src=%0.4f y_src=%0.4f", x_src, y_src);
                $display("  x_l=%0d x_h=%0d  y_l=%0d y_h=%0d", x_l,x_h,y_l,y_h);
                $display("  x_w=%0.4f y_w=%0.4f", x_w, y_w);
                $display("  a=%0d b=%0d c=%0d d=%0d", a,b,c,d);
                $display("  expected=%0d", expected[i][j]);
            end
        end

        // Reset
        rst   = 1;
        start = 0;
        repeat(4) @(posedge clk);
        rst   = 0;

        // Lanzar downscale SIMD
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Esperar fin
        wait(done == 1);

        // Comparación
        $display("\n=== COMPARACIÓN HW (Downscale_SIMD) vs REF ===");
        for (i = 0; i < DST_H; i++) begin
            for (j = 0; j < DST_W; j++) begin
                diff = image_out[i][j] - expected[i][j];
                if (diff < 0) diff = -diff;

                $display("Pixel (%0d,%0d): HW=%0d REF=%0d diff=%0d",
                         i,j,image_out[i][j], expected[i][j], diff);

                if (diff <= 1)
                    pass_count++;
                else
                    fail_count++;
            end
        end

        $display("\nResumen: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        if (fail_count == 0)
            $display("TODOS los píxeles pasaron (±1 LSB).");
        else
            $display("Hay diferencias entre HW y referencia.");

        $finish;
    end

endmodule
