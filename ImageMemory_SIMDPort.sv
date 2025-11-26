// =====================================================
// ImageMemory_SIMDPort.sv
// N caches independientes con árbitro de memoria
// =====================================================

module ImageMemory_SIMDPort #(
    parameter int IMG_W     = 512,
    parameter int IMG_H     = 512,
    parameter int N         = 4,   // Lanes SIMD
    parameter int LINE_SIZE = 8    // Tamaño de línea de caché
)(
    input  logic clk,
    input  logic rst,

    // Requests SIMD (N lanes independientes)
    input  logic                           rd_req   [N],
    input  logic [$clog2(IMG_W*IMG_H)-1:0] rd_addr  [N],
    output logic                           rd_valid [N],
    output logic [7:0]                     rd_data  [N],

    // Puerto de escritura para cargar la memoria
    input  logic we,
    input  logic [$clog2(IMG_W*IMG_H)-1:0] wr_addr,
    input  logic [7:0] wr_data
);

    localparam int DEPTH       = IMG_W * IMG_H;
    localparam int ADDR_BITS   = $clog2(DEPTH);
    localparam int OFFSET_BITS = $clog2(LINE_SIZE);
    localparam int TAG_BITS    = ADDR_BITS - OFFSET_BITS;

    // ============================
    // Memoria base BRAM (1 puerto)
    // ============================
    logic [7:0]           mem_rdata;
    logic [ADDR_BITS-1:0] mem_addr;

    ImageMemory #(
        .IMG_W(IMG_W),
        .IMG_H(IMG_H)
    ) mem (
        .clk    (clk),
        .we     (we),
        .addr   (we ? wr_addr : mem_addr),
        .wr_data(wr_data),
        .rd_data(mem_rdata)
    );

    // ====================================================
    // Estructura de caché por lane
    // ====================================================
    typedef struct {
        logic                valid;
        logic [TAG_BITS-1:0] tag;
        logic [7:0]          data [LINE_SIZE];
    } cache_line_t;

    cache_line_t cache [N];

    // ====================================================
    // FSM por lane
    // ====================================================
    typedef enum logic [1:0] {
        IDLE,
        WAIT_ARB,
        FETCH,
        OUTPUT
    } state_t;

    state_t state [N];

    // Control por lane
    logic [OFFSET_BITS-1:0] fetch_idx      [N];
    logic [ADDR_BITS-1:0]   line_addr_base [N];
    logic [TAG_BITS-1:0]    req_tag        [N];
    logic [OFFSET_BITS-1:0] req_offset     [N];

    // Lane activo en memoria
    logic [$clog2(N)-1:0] active_lane;
    logic                 mem_busy;

    // ====================================================
    // Decodificación de dirección: tag + offset
    // ====================================================
    genvar g;
    generate
        for (g = 0; g < N; g++) begin : gen_addr_decode
            always_comb begin
                req_tag[g]    = rd_addr[g][ADDR_BITS-1:OFFSET_BITS];
                req_offset[g] = rd_addr[g][OFFSET_BITS-1:0];
            end
        end
    endgenerate

    // ====================================================
    // Round-robin arbiter sintetizable
    // ====================================================
    logic [$clog2(N)-1:0] arb_ptr;      // Puntero RR
    logic [N-1:0]         lane_needs_mem;
    logic [$clog2(N)-1:0] next_lane;
    logic                 found_next;
    logic [$clog2(N)-1:0] idx_rr;

    // ¿Qué lanes están esperando memoria?
    always_comb begin
        lane_needs_mem = '0;
        for (int i = 0; i < N; i++) begin
            lane_needs_mem[i] = (state[i] == WAIT_ARB);
        end
    end

    // Selección RR sin usar % ni declarar vars dentro del for
    always_comb begin
        next_lane  = arb_ptr;
        found_next = 1'b0;
        idx_rr     = '0;

        // offset recorre 1..N
        for (int offset = 1; offset <= N; offset++) begin
            // (arb_ptr + offset) mod N
            if (arb_ptr + offset >= N)
                idx_rr = arb_ptr + offset - N;
            else
                idx_rr = arb_ptr + offset;

            if (!found_next && lane_needs_mem[idx_rr]) begin
                next_lane  = idx_rr;
                found_next = 1'b1;
            end
        end
    end

    // ====================================================
    // FSM por lane + árbitro
    // ====================================================
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < N; i++) begin
                state[i]       <= IDLE;
                rd_valid[i]    <= 1'b0;
                cache[i].valid <= 1'b0;
                fetch_idx[i]   <= '0;
            end
            mem_busy    <= 1'b0;
            arb_ptr     <= '0;
            active_lane <= '0;
            mem_addr    <= '0;
        end else begin
            // Por defecto, ninguna salida válida
            for (int i = 0; i < N; i++) begin
                rd_valid[i] <= 1'b0;
            end

            // =========================
            // FSM por lane
            // =========================
            for (int i = 0; i < N; i++) begin
                case (state[i])

                    // -----------------
                    // IDLE
                    // -----------------
                    IDLE: begin
                        if (rd_req[i]) begin
                            // HIT de caché
                            if (cache[i].valid && (cache[i].tag == req_tag[i])) begin
                                rd_data[i]  <= cache[i].data[req_offset[i]];
                                rd_valid[i] <= 1'b1;
                            end else begin
                                // MISS → preparar fetch
                                line_addr_base[i] <= {req_tag[i], {OFFSET_BITS{1'b0}}};
                                fetch_idx[i]      <= '0;
                                state[i]          <= WAIT_ARB;
                            end
                        end
                    end

                    // -----------------
                    // WAIT_ARB
                    // -----------------
                    WAIT_ARB: begin
                        if (!mem_busy && found_next && (next_lane == i)) begin
                            // Este lane gana la memoria
                            active_lane <= i;
                            mem_busy    <= 1'b1;
                            state[i]    <= FETCH;
                            fetch_idx[i] <= '0;
                        end
                    end

                    // -----------------
                    // FETCH: cargar línea completa
                    // -----------------
                    FETCH: begin
                        if (i == active_lane) begin
                            // Protocolo simple de lectura:
                            // ciclo 0: poner mem_addr (no se escribe data aún)
                            // ciclo 1..LINE_SIZE: leer mem_rdata y avanzar

                            // Primer ciclo: apuntar a base
                            if (fetch_idx[i] == 0) begin
                                mem_addr    <= line_addr_base[i];
                                fetch_idx[i] <= fetch_idx[i] + 1;
                            end
                            // Ciclos 1..LINE_SIZE-1: almacenar dato anterior y pedir siguiente
                            else if (fetch_idx[i] < LINE_SIZE) begin
                                cache[i].data[fetch_idx[i]-1] <= mem_rdata;
                                mem_addr    <= line_addr_base[i] + fetch_idx[i];
                                fetch_idx[i] <= fetch_idx[i] + 1;
                            end
                            // Último ciclo: almacenar último dato y cerrar
                            else begin // fetch_idx == LINE_SIZE
                                cache[i].data[LINE_SIZE-1] <= mem_rdata;
                                cache[i].valid             <= 1'b1;
                                cache[i].tag               <= req_tag[i];
                                state[i]                   <= OUTPUT;
                                fetch_idx[i]               <= '0;
                                mem_busy                   <= 1'b0;  // liberar memoria
                                arb_ptr                    <= i;     // avanzar RR
                            end
                        end
                    end

                    // -----------------
                    // OUTPUT
                    // -----------------
                    OUTPUT: begin
                        rd_data[i]  <= cache[i].data[req_offset[i]];
                        rd_valid[i] <= 1'b1;
                        state[i]    <= IDLE;
                    end

                endcase
            end
        end
    end

endmodule
