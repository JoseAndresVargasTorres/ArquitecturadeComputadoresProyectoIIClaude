module ImageMemory #(
    parameter int IMG_W = 512,
    parameter int IMG_H = 512
)(
    input  logic clk,
    input  logic we,
    input  logic [$clog2(IMG_W*IMG_H)-1:0] addr,
    input  logic [7:0] wr_data,
    output logic [7:0] rd_data
);

    localparam int DEPTH = IMG_W * IMG_H;

    // Memoria BRAM inferida
    logic [7:0] mem [0:DEPTH-1];

    // Escritura / Lectura sincronizada
    always_ff @(posedge clk) begin
        if (we)
            mem[addr] <= wr_data;

        rd_data <= mem[addr];
    end

endmodule
