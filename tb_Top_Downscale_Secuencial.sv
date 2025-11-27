`timescale 1ns/1ps

module tb_Top_Downscale_Secuencial;

    localparam int SRC_W = 32;
    localparam int SRC_H = 32;
    localparam int DST_W = 16;
    localparam int DST_H = 16;

    logic clk, rst;

    logic        cfg_we;
    logic [15:0] cfg_addr;
    logic [7:0]  cfg_data;

    logic start_req;
    logic done;
    logic [7:0] dbg_data;

    // ============
    // VARIABLES (fuera de initial) — Compatible con Quartus
    // ============
    integer i;
    integer j;
    integer pass;
    integer fail;

    real xr;
    real yr;
    real xs;
    real ys;
    real xw;
    real yw;

    integer xl;
    integer yl;
    integer xh;
    integer yh;

    integer a,b,c,d;
    integer hw;

    // ================================================
    // Instancia del TOP
    // ================================================
    Top_Downscale_Secuencial #(
        .SRC_W(SRC_W),
        .SRC_H(SRC_H),
        .DST_W(DST_W),
        .DST_H(DST_H)
    ) dut (
        .clk(clk),
        .rst(rst),
        .cfg_we(cfg_we),
        .cfg_addr(cfg_addr),
        .cfg_data(cfg_data),
        .start_req(start_req),
        .done(done),
        .dbg_data(dbg_data)
    );

    // ================================================
    // CLOCK
    // ================================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // ================================================
    // IMAGEN FUENTE + REFERENCIA
    // ================================================
    integer img_in  [0:SRC_H-1][0:SRC_W-1];
    integer expected[0:DST_H-1][0:DST_W-1];

    function integer bilinear_ref(
        input integer a,b,c,d,
        input real xw, yw
    );
        real w00, w10, w01, w11, r;
        integer pix;

        w00 = (1-xw)*(1-yw);
        w10 = xw*(1-yw);
        w01 = (1-xw)*yw;
        w11 = xw*yw;

        r = a*w00 + b*w10 + c*w01 + d*w11;
        pix = $rtoi(r+0.5);

        if (pix<0) pix=0;
        if (pix>255) pix=255;

        return pix;
    endfunction
	 
	 function automatic int abs_int(int x);
			return (x < 0) ? -x : x;
	 endfunction

    // ================================================
    // MAIN
    // ================================================
    initial begin
        
        xr = real'(SRC_W-1) / real'(DST_W-1);
        yr = real'(SRC_H-1) / real'(DST_H-1);

        rst = 1;
        cfg_we = 0;
        start_req = 0;
        repeat(5) @(posedge clk);
        rst = 0;

        // 1) Generar imagen 32×32
        for (i=0; i<SRC_H; i++)
        for (j=0; j<SRC_W; j++)
            img_in[i][j] = (i*4 + j*2) & 255;

        // 2) Cargar BRAM simulando JTAG
        $display("Cargando imagen en BRAM...");
        for (i=0; i<SRC_H; i++) begin
            for (j=0; j<SRC_W; j++) begin
                @(posedge clk);
                cfg_we   = 1;
                cfg_addr = i*SRC_W + j;
                cfg_data = img_in[i][j];
            end
        end
        @(posedge clk);
        cfg_we = 0;

        // 3) Calcular referencia software
        for (i=0; i<DST_H; i++) begin
            for (j=0; j<DST_W; j++) begin
                
                xs = xr * j;
                ys = yr * i;

                xl = $floor(xs);
                yl = $floor(ys);
                xh = $ceil(xs);
                yh = $ceil(ys);

                xw = xs - xl;
                yw = ys - yl;

                a = img_in[yl][xl];
                b = img_in[yl][xh];
                c = img_in[yh][xl];
                d = img_in[yh][xh];

                expected[i][j] = bilinear_ref(a,b,c,d,xw,yw);
            end
        end

        // 4) Iniciar procesamiento
        @(posedge clk);
        start_req = 1;
        @(posedge clk);
        start_req = 0;

        // 5) Esperar `done`
        wait(done);

        // 6) Comparación HW vs REF
        pass = 0;
        fail = 0;

        for (i=0;i<DST_H;i++)
        for (j=0;j<DST_W;j++) begin
            hw = dut.u_seq.image_out[i][j];
            if (abs_int(hw - expected[i][j]) <= 1)
                pass++;
            else begin
                fail++;
                $display("FAIL (%0d,%0d): HW=%0d REF=%0d",
                    i,j, hw, expected[i][j]);
            end
        end

        $display("PASS=%0d FAIL=%0d", pass, fail);
        $finish;
    end

endmodule
