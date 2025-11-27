// =====================================================
//  ImageMemory_SequentialPort.sv
//  Acceso secuencial → 1 lectura/ciclo
// =====================================================

module ImageMemory_SequentialPort #(
    parameter int IMG_W = 512,
    parameter int IMG_H = 512
)(
    input  logic clk,
    input  logic rd_req,
    input  logic [$clog2(IMG_W*IMG_H)-1:0] rd_addr,

    output logic rd_valid,
    output logic [7:0] rd_data,

    // Write port (opcional para carga inicial)
    input  logic we,
    input  logic [$clog2(IMG_W*IMG_H)-1:0] wr_addr,
    input  logic [7:0] wr_data
);

    logic [7:0] mem_rdata;

    ImageMemory #(
        .IMG_W(IMG_W), .IMG_H(IMG_H)
    ) mem (
        .clk(clk),
        .we(we),
        .addr(we ? wr_addr : rd_addr),
        .wr_data(wr_data),
        .rd_data(mem_rdata)
    );

    always_ff @(posedge clk) begin
        rd_valid <= rd_req;
        rd_data  <= mem_rdata;
    end

endmodule
