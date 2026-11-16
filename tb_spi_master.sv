`timescale 1ns / 1ps

module tb_spi_master;

    // Tham số cấu hình
    localparam int CLK_DIV = 4;
    localparam time CLK_PERIOD = 20ns; // 50 MHz

    // Khai báo tín hiệu bằng kiểu logic
    logic       clk;
    logic       rst_n;
    logic       start;
    logic [7:0] tx_data;
    logic [7:0] rx_data;
    logic       busy;
    logic       done;
    logic       sclk;
    logic       cs_n;
    logic       mosi;
    logic       miso;

    // Tín hiệu hỗ trợ giả lập môi trường
    logic       loopback_en;
    logic       miso_custom;

    assign miso = loopback_en ? mosi : miso_custom;

    // Khởi tạo DUT với kết nối ngầm định (.*) của SystemVerilog
    spi_master #(
        .CLK_DIV(CLK_DIV)
    ) dut (
        .*
    );

    // Tạo xung nhịp hệ thống
    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2) clk = ~clk;
    end

    // Task hỗ trợ: Thực hiện truyền/nhận Full-Duplex và kiểm tra
    task automatic run_spi_transaction(
        input logic [7:0] master_tx,
        input logic [7:0] expected_rx,
        input bit         is_loopback
    );
        logic [7:0] slave_shift;
        loopback_en = is_loopback;
        tx_data     = master_tx;
        slave_shift = expected_rx;

        // Kích hoạt xung start
        @(posedge clk);
        start = 1'b1;
        @(posedge clk);
        start = 1'b0;

        // Chạy song song: Vừa đợi Master hoàn thành, vừa giả lập dữ liệu trên chân MISO
        fork
            // Tiến trình 1: Giả lập dữ liệu trả về trên đường MISO (nếu không dùng loopback)
            begin
                if (!is_loopback) begin
                    @(negedge cs_n);
                    miso_custom = slave_shift[7]; // Đẩy bit MSB ngay khi CS_N xuống 0
                    repeat (7) begin
                        @(negedge sclk);
                        slave_shift = {slave_shift[6:0], 1'b0};
                        miso_custom = slave_shift[7];
                    end
                end
            end

            // Tiến trình 2: Chờ cờ báo hoàn tất (done) từ Master
            begin
                @(posedge done);
            end
        join

        // Đợi 1 chu kỳ để rx_data ổn định và kiểm tra bằng lệnh assert
        @(posedge clk);
        assert (rx_data === expected_rx)
            $display("[PASS] Time: %0t | TX: 0x%02h | RX: 0x%02h (Expected: 0x%02h)", 
                     $time, master_tx, rx_data, expected_rx);
        else
            $error("[FAIL] Time: %0t | TX: 0x%02h | RX: 0x%02h (Expected: 0x%02h)", 
                   $time, master_tx, rx_data, expected_rx);

        #(CLK_PERIOD * 5);
    endtask

    // Kịch bản kiểm thử chính
    initial begin
        // Khởi tạo trạng thái ban đầu
        rst_n       = 1'b0;
        start       = 1'b0;
        tx_data     = '0;
        loopback_en = 1'b1;
        miso_custom = 1'b0;

        #(CLK_PERIOD * 3);
        rst_n = 1'b1;
        #(CLK_PERIOD * 2);

        $display("   BAT DAU MO PHONG SYSTEMVERILOG SPI MASTER:      ");

        // Test 1: Chế độ Loopback (Gửi 0xA5, nhận về đúng 0xA5)
        $display("\n--- Test 1: Loopback Mode ---");
        run_spi_transaction(8'hA5, 8'hA5, 1'b1);

        // Test 2: Chế độ Full-Duplex độc lập (Gửi 0x5A, nhận về 0x3C cùng lúc)
        $display("\n--- Test 2: Full-Duplex Mode ---");
        run_spi_transaction(8'h5A, 8'h3C, 1'b0);

        // Test 3: Kiểm tra biên với dữ liệu toàn 0 và toàn 1
        $display("\n--- Test 3: Corner Cases (0xFF & 0x00) ---");
        run_spi_transaction(8'hFF, 8'h00, 1'b0);
        run_spi_transaction(8'h00, 8'hFF, 1'b0);

        $display("   HOAN TAT MO PHONG.                              ");
        $finish;
    end

endmodule

