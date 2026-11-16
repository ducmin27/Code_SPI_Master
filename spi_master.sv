module spi_master #(
    parameter int CLK_DIV = 4 // Hệ số chia tần: f_SCLK = f_clk / (2 * CLK_DIV)
)(
    input  logic       clk,
    input  logic       rst_n,
    
    // Giao tiếp với Hệ thống / MCU
    input  logic       start,
    input  logic [7:0] tx_data,
    output logic [7:0] rx_data,
    output logic       busy,
    output logic       done,
    
    // Giao tiếp SPI vật lý (Mode 0: CPOL = 0, CPHA = 0)
    output logic       sclk,
    output logic       cs_n,
    output logic       mosi,
    input  logic       miso
);

    // Định nghĩa các trạng thái FSM bằng kiểu liệt kê (enum)
    typedef enum logic [1:0] {
        IDLE       = 2'b00,
        TRANSFER   = 2'b01,
        DONE_STATE = 2'b10
    } state_t;

    state_t state, next_state;

    // Thanh ghi dịch và bộ đếm
    logic [7:0] tx_shift_reg;
    logic [7:0] rx_shift_reg;
    logic [2:0] bit_cnt;                       // Đếm số bit từ 0 đến 7
    logic [$clog2(CLK_DIV)-1:0] clk_cnt;       // Tự động tính độ rộng bit cho bộ chia tần

    // Đẩy bit MSB ra MOSI ngay khi CS_N kéo xuống 0 (đáp ứng CPHA = 0)
    assign mosi = (~cs_n) ? tx_shift_reg[7] : 1'b0;

    // ---------------------------------------------------------
    // 1. Khối mạch tuần tự (Sequential Logic) dùng always_ff
    // ---------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            tx_shift_reg <= '0;
            rx_shift_reg <= '0;
            rx_data      <= '0;
            bit_cnt      <= '0;
            clk_cnt      <= '0;
            sclk         <= 1'b0; // CPOL = 0: SCLK nghỉ ở mức 0
            cs_n         <= 1'b1; // CS_N nghỉ ở mức 1
            busy         <= 1'b0;
            done         <= 1'b0;
        end else begin
            state <= next_state;

            unique case (state)
                IDLE: begin
                    done    <= 1'b0;
                    sclk    <= 1'b0;
                    clk_cnt <= '0;
                    bit_cnt <= '0;

                    if (start) begin
                        tx_shift_reg <= tx_data; // Nạp dữ liệu truyền
                        cs_n         <= 1'b0;    // Kích hoạt Slave
                        busy         <= 1'b1;    // Báo bận
                    end else begin
                        cs_n         <= 1'b1;
                        busy         <= 1'b0;
                    end
                end

                TRANSFER: begin
                    if (clk_cnt == CLK_DIV - 1) begin
                        clk_cnt <= '0;
                        sclk    <= ~sclk; // Đảo mức xung SCLK

                        // Cạnh lên của SCLK (0 -> 1): Lấy mẫu (Sample) MISO
                        if (sclk == 1'b0) begin
                            rx_shift_reg <= {rx_shift_reg[6:0], miso};
                        end 
                        // Cạnh xuống của SCLK (1 -> 0): Dịch (Shift) MOSI
                        else begin
                            if (bit_cnt == 3'd7) begin
                                bit_cnt <= '0;
                            end else begin
                                tx_shift_reg <= {tx_shift_reg[6:0], 1'b0};
                                bit_cnt      <= bit_cnt + 1'b1;
                            end
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                DONE_STATE: begin
                    cs_n    <= 1'b1;         // Ngắt kết nối Slave
                    sclk    <= 1'b0;         // Giữ SCLK mức 0
                    busy    <= 1'b0;         // Xóa cờ bận
                    done    <= 1'b1;         // Kích hoạt cờ hoàn tất (1 chu kỳ clk)
                    rx_data <= rx_shift_reg; // Cập nhật dữ liệu nhận được ra port
                end

                default: state <= IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 2. Khối mạch tổ hợp (Combinational Logic) dùng always_comb
    // ---------------------------------------------------------
    always_comb begin
        next_state = state; // Mặc định giữ nguyên trạng thái để tránh tạo Latch

        unique case (state)
            IDLE: begin
                if (start)
                    next_state = TRANSFER;
            end

            TRANSFER: begin
                // Chuyển trạng thái tại cạnh xuống thứ 8 của SCLK
                if ((clk_cnt == CLK_DIV - 1) && (sclk == 1'b1) && (bit_cnt == 3'd7))
                    next_state = DONE_STATE;
            end

            DONE_STATE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

endmodule
