`timescale 1ns / 1ps

`ifndef VIVADO_PRJ_USE
`include "types.vh"
`endif

import types::*;

`define SYSTEM_CLK_HALF_PERIOD 5000

module tb_computing_unit;

localparam SYSTOL_ACTIVATION_COUNT = 16;
localparam SYSTOL_WEIGHT_COUNT = 16;
localparam ACTIVATION_QUEUE_DEPTH = 16;
localparam WEIGHT_QUEUE_DEPTH = 16;
localparam OFFSET_QUEUE_DEPTH = 16;

logic sys_clk;
logic sys_rst;

logic cu_rst_busy;

logic cu_weight_update;

data_type cu_activation [0:SYSTOL_ACTIVATION_COUNT - 1];
logic cu_activation_wr_en;
logic cu_activation_full;

data_type cu_weight [0:SYSTOL_WEIGHT_COUNT - 1];
logic cu_weight_wr_en;
logic cu_weight_full;

logic [2:SYSTOL_WEIGHT_COUNT-1] cu_accum_adder_chain_set;
logic [1:SYSTOL_WEIGHT_COUNT-1] cu_accum_out_data_mux;

data_type cu_offset [0:SYSTOL_WEIGHT_COUNT - 1];
logic cu_offset_wr_en;
logic cu_offset_full;

data_type cu_result [0:SYSTOL_WEIGHT_COUNT - 1];

//reset generation
initial begin
    sys_clk = 0;
    sys_rst = 1;

    #(`SYSTEM_CLK_HALF_PERIOD * 10);
    sys_rst = 0;
end

always #(`SYSTEM_CLK_HALF_PERIOD) sys_clk = ~sys_clk;

computing_unit #(
    .SYSTOL_ACTIVATION_COUNT(SYSTOL_ACTIVATION_COUNT)
    , .ACTIVATION_QUEUE_DEPTH(ACTIVATION_QUEUE_DEPTH)
    , .SYSTOL_WEIGHT_COUNT(SYSTOL_WEIGHT_COUNT)
    , .WEIGHT_QUEUE_DEPTH(WEIGHT_QUEUE_DEPTH)
    , .OFFSET_QUEUE_DEPTH(OFFSET_QUEUE_DEPTH)
    )
cu (
    .clk_i(sys_clk)
    , .rst_i(sys_rst)
    , .rst_busy(cu_rst_busy)

    //systolic array control
    , .weight_update_i(cu_weight_update)
    , .activation_i(cu_activation)
    , .activation_wr_en_i(cu_activation_wr_en)
    , .activation_full_o(cu_activation_full)
    , .weight_i(cu_weight)
    , .weight_wr_en_i(cu_weight_wr_en)
    , .weight_full_o(cu_weight_full)

    //accumulators control
    , .accum_adder_chain_set_i(cu_accum_adder_chain_set)
    , .accum_out_data_mux_i(cu_accum_out_data_mux)

    //offsets control
    , .offset_i(cu_offset)
    , .offset_wr_en_i(cu_offset_wr_en)
    , .offset_full_o(cu_offset_full)

    , .result_o(cu_result)
);

integer weight_column_num, activation_row_num, offset_row_num;
integer proc_ctr;
integer col, row;

//multiplication test for matrices with sizes equal to a systolic array
//sending weights and activations to the computing unit one after the other.
data_type weight_matrix_1 [0:SYSTOL_WEIGHT_COUNT - 1]
                            [0:SYSTOL_ACTIVATION_COUNT - 1];
                            
data_type activation_matrix_1 [0:SYSTOL_ACTIVATION_COUNT - 1]
                                [0:SYSTOL_WEIGHT_COUNT - 1];

data_type offset_matrix_1 [0:SYSTOL_WEIGHT_COUNT - 1]
                                [0:SYSTOL_WEIGHT_COUNT - 1];

data_type mul_result_matrix_1 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];
data_type offset_result_matrix_1 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];
data_type cu_result_matrix_1 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];

task matrix_mul_test_1();
    begin
        $display("");
        $display("--------matrix_mul_test_1 START---------");
        $display("========================================");

        cu_accum_adder_chain_set = 14'b00_0000_0000_0000;
        cu_accum_out_data_mux = 15'b000_0000_0000_0000;

        weight_column_num = 0;
        activation_row_num = 0;
        offset_row_num = 0;
        proc_ctr = 0;

        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++) begin
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++) begin
                mul_result_matrix_1[i][j] = 0;
            end
        end
        
        @(posedge sys_clk);
        #1;
        
        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : mul_array_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                for(integer k=0; k<SYSTOL_ACTIVATION_COUNT;k++)	begin
                    mul_result_matrix_1[i][j] = mul_result_matrix_1[i][j] + 
                                            weight_matrix_1[i][k] * 
                                            activation_matrix_1[k][j];
                end
            end
        end

        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : offset_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                offset_result_matrix_1[i][j] = mul_result_matrix_1[i][j] + 
                                                offset_matrix_1[i][j];
            end
        end
        
        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : CU_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                cu_result_matrix_1[i][j] = (offset_result_matrix_1[i][j] < 0) ? 
                                                0 : offset_result_matrix_1[i][j];
            end
        end
        
        //weight sending
        while (weight_column_num < SYSTOL_ACTIVATION_COUNT) begin : weight_sending
            @(posedge sys_clk);
            #1;

            if(cu_weight_full == 0) begin
                if(weight_column_num == 0) begin
                    cu_weight_update = 1;
                end
                else begin
                    cu_weight_update = 0;
                end

                cu_weight_wr_en = 1;
                for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
                    cu_weight[i] = weight_matrix_1[i][SYSTOL_ACTIVATION_COUNT - weight_column_num - 1];
                end
                weight_column_num = weight_column_num + 1;
            end
            else begin
                cu_weight_wr_en = 0;
            end
        end

        while (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT) + 10)) begin
            @(posedge sys_clk);
            #1;
            
            begin : activation_sending
            cu_weight_update = 0;
            cu_weight_wr_en = 0;

            //activation sending
            if(cu_activation_full == 0) begin
                cu_activation_wr_en = 1;
                for(integer i = 0; i < SYSTOL_ACTIVATION_COUNT; i++) begin
                    cu_activation[i] = 0;
                end
                
                for(integer i = 0; i < activation_row_num + 1; i++) begin
                    if((activation_row_num - i) < SYSTOL_ACTIVATION_COUNT) begin
                        cu_activation[i] = activation_matrix_1[i][activation_row_num - i];
                    end
                end

                activation_row_num = activation_row_num + 1;
            end
            else begin
                cu_activation_wr_en = 0;
            end
            end

            //offsets sending
            //start 4 clock cycle before getting results from accum block
            if (
                (proc_ctr > (SYSTOL_ACTIVATION_COUNT + 5 - 4)) && 
                (offset_row_num < (2 * SYSTOL_WEIGHT_COUNT))
            ) begin : offsets_sending

                if(cu_offset_full == 0) begin
                    cu_offset_wr_en = 1;
                    for(integer i = 0; i < SYSTOL_WEIGHT_COUNT; i++) begin
                        cu_offset[i] = 0;
                    end

                    for(integer i = 0; i < offset_row_num + 1; i++) begin
                        if((offset_row_num - i) < SYSTOL_WEIGHT_COUNT) begin
                            cu_offset[i] = offset_matrix_1[i][offset_row_num - i];
                        end
                    end

                    offset_row_num = offset_row_num + 1;
                end
                else begin
                    cu_offset_wr_en = 0;
                end
            end
            else begin
                cu_offset_wr_en = 0;
            end

            //systol_array results check
            //4 clock cycle delay between sending data to cu and storing data in systolic array
            if ( 
                (proc_ctr > (SYSTOL_ACTIVATION_COUNT + 4)) &&
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT) + 4))
            ) begin : systol_array_results_check

                for(integer z=0; z < (proc_ctr - (SYSTOL_ACTIVATION_COUNT + 4)); z++) begin
                    col = proc_ctr - (SYSTOL_ACTIVATION_COUNT + 4) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.systol_arr_dout[row] == mul_result_matrix_1[row][col]) begin
                            $display("TRUE  | [%0t] SystolArr_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.systol_arr_dout[row], row, col, mul_result_matrix_1[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] SystolArr_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.systol_arr_dout[row], row, col, mul_result_matrix_1[row][col]);
                        end
                    end
                end
            end

            //accum results check
            //5 clock cycle delay between sending data to cu and getting data from accumulators
            //if cu_accum_adder_chain_set == 14'b00_0000_0000_0000;
            //   cu_accum_out_data_mux == 15'b000_0000_0000_0000;
            if (
                (proc_ctr > (SYSTOL_ACTIVATION_COUNT + 5)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT) + 5))
            ) begin : accum_results_check

                for(integer z = 0; z < (proc_ctr - (SYSTOL_ACTIVATION_COUNT + 5)); z++) begin
                    col = proc_ctr - (SYSTOL_ACTIVATION_COUNT + 5) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.accum_dout[row] == mul_result_matrix_1[row][col]) begin
                            $display("TRUE  | [%0t] Accum_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.accum_dout[row], row, col, mul_result_matrix_1[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] Accum_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.accum_dout[row], row, col, mul_result_matrix_1[row][col]);
                        end
                    end
                end             
            end

            //offset results check
            //6 clock cycle delay between sending data to cu and getting data from offsets
            if (
                (proc_ctr > (SYSTOL_ACTIVATION_COUNT + 6)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT) + 6))
            ) begin : offset_results_check

                for(integer z=0; z < (proc_ctr - (SYSTOL_ACTIVATION_COUNT + 6)); z++) begin
                    col = proc_ctr - (SYSTOL_ACTIVATION_COUNT + 6) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.offsets_dout[row] == offset_result_matrix_1[row][col]) begin
                            $display("TRUE  | [%0t] Offsets_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.offsets_dout[row], row, col, offset_result_matrix_1[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] Offsets_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.offsets_dout[row], row, col, offset_result_matrix_1[row][col]);
                        end
                    end
                end             
            end

            //cu results check
            //7 clock cycle delay between sending data to cu and getting data from offsets
            if (
                (proc_ctr > (SYSTOL_ACTIVATION_COUNT + 7)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT) + 7))
            ) begin : CU_results_check

                for(integer z=0; z < (proc_ctr - (SYSTOL_ACTIVATION_COUNT + 7)); z++) begin
                    col = proc_ctr - (SYSTOL_ACTIVATION_COUNT + 7) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu_result[row] == cu_result_matrix_1[row][col]) begin
                            $display("TRUE  | [%0t] CU_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu_result[row], row, col, cu_result_matrix_1[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] CU_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu_result[row], row, col, cu_result_matrix_1[row][col]);
                        end
                    end
                end             
            end
            
            proc_ctr = proc_ctr + 1;
        end

        $display("========================================");
        $display("----------matrix_mul_test_1 END---------");
        $display("");
    end
endtask

//multiplication test for matrices with sizes equal to a systolic array
//sending weights and activations to the computing unit in parallel.
data_type weight_matrix_2 [0:SYSTOL_WEIGHT_COUNT - 1]
                            [0:SYSTOL_ACTIVATION_COUNT - 1];
                            
data_type activation_matrix_2 [0:SYSTOL_ACTIVATION_COUNT - 1]
                                [0:SYSTOL_WEIGHT_COUNT - 1];

data_type offset_matrix_2 [0:SYSTOL_WEIGHT_COUNT - 1]
                                [0:SYSTOL_WEIGHT_COUNT - 1];

data_type mul_result_matrix_2 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];
data_type offset_result_matrix_2 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];
data_type cu_result_matrix_2 [0:SYSTOL_WEIGHT_COUNT-1][0:SYSTOL_WEIGHT_COUNT-1];

task matrix_mul_test_2();
    begin
        $display("");
        $display("--------matrix_mul_test_2 START---------");
        $display("========================================");

        cu_accum_adder_chain_set = 14'b00_0000_0000_0000;
        cu_accum_out_data_mux = 15'b000_0000_0000_0000;

        weight_column_num = 0;
        activation_row_num = 0;
        offset_row_num = 0;
        proc_ctr = 0;

        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++) begin
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++) begin
                mul_result_matrix_2[i][j] = 0;
            end
        end
        
        @(posedge sys_clk);
        #1;
        
        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : mul_array_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                for(integer k=0; k<SYSTOL_ACTIVATION_COUNT;k++)	begin
                    mul_result_matrix_2[i][j] = mul_result_matrix_2[i][j] + 
                                                weight_matrix_2[i][k] * 
                                                activation_matrix_2[k][j];
                end
            end
        end

        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : offset_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                offset_result_matrix_2[i][j] = mul_result_matrix_2[i][j] + 
                                                offset_matrix_2[i][j];
            end
        end
        
        for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin : CU_gold_res_calc
            for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
                cu_result_matrix_2[i][j] = (offset_result_matrix_2[i][j] < 0) ? 
                                                0 : offset_result_matrix_2[i][j];
            end
        end
        
        while (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 3 * SYSTOL_ACTIVATION_COUNT) + 10)) begin
            @(posedge sys_clk);
            #1;
            
            //weight sending
            if(weight_column_num < SYSTOL_ACTIVATION_COUNT) begin : weight_sending
                if(cu_weight_full == 0) begin
                    if(weight_column_num == 0) begin
                        cu_weight_update = 1;
                    end
                    else begin
                        cu_weight_update = 0;
                    end

                    cu_weight_wr_en = 1;
                    for(integer i=0; i < SYSTOL_WEIGHT_COUNT; i++)	begin
                        cu_weight[i] = weight_matrix_2[i][SYSTOL_ACTIVATION_COUNT - weight_column_num - 1];
                    end
                    weight_column_num = weight_column_num + 1;
                end
                else begin
                    cu_weight_wr_en = 0;
                end
            end
            else begin
                cu_weight_update = 0;
                cu_weight_wr_en = 0;
            end

            //activation sending
            if(activation_row_num < (SYSTOL_WEIGHT_COUNT + 2 * SYSTOL_ACTIVATION_COUNT)) begin : activation_sending
                if(cu_activation_full == 0) begin
                    cu_activation_wr_en = 1;
                    for(integer i = 0; i < SYSTOL_ACTIVATION_COUNT; i++) begin
                        cu_activation[i] = 0;
                    end
                    
                    for(integer i = 0; i < activation_row_num + 1; i++) begin
                        if((activation_row_num - i) < SYSTOL_ACTIVATION_COUNT) begin
                            cu_activation[i] = activation_matrix_2[i][activation_row_num - i];
                        end
                    end

                    activation_row_num = activation_row_num + 1;
                end
                else begin
                    cu_activation_wr_en = 0;
                end
            end
            else begin
                cu_activation_wr_en = 0;
            end

            //offsets sending
            //start 4 clock cycle before getting results from accum block
            if (
                (proc_ctr > (2 * SYSTOL_ACTIVATION_COUNT + 5 - 4)) && 
                (offset_row_num < (2 * SYSTOL_WEIGHT_COUNT))
            ) begin : offsets_sending

                if(cu_offset_full == 0) begin
                    cu_offset_wr_en = 1;
                    for(integer i = 0; i < SYSTOL_WEIGHT_COUNT; i++) begin
                        cu_offset[i] = 0;
                    end

                    for(integer i = 0; i < offset_row_num + 1; i++) begin
                        if((offset_row_num - i) < SYSTOL_WEIGHT_COUNT) begin
                            cu_offset[i] = offset_matrix_2[i][offset_row_num - i];
                        end
                    end

                    offset_row_num = offset_row_num + 1;
                end
                else begin
                    cu_offset_wr_en = 0;
                end
            end
            else begin
                cu_offset_wr_en = 0;
            end

            //systol array results check
            //4 clock cycle delay between sending data to cu and storing data in systolic array
            if (
                (proc_ctr > (2 * SYSTOL_ACTIVATION_COUNT + 4)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 3 * SYSTOL_ACTIVATION_COUNT) + 4))
            ) begin : systol_array_results_check

                for(integer z = 0; z < (proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 4)); z++) begin
                    col = proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 4) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.systol_arr_dout[row] == mul_result_matrix_2[row][col]) begin
                            $display("TRUE  | [%0t] SystolArr_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.systol_arr_dout[row], row, col, mul_result_matrix_2[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] SystolArr_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.systol_arr_dout[row], row, col, mul_result_matrix_2[row][col]);
                        end
                    end
                end
            end

            //accum results check
            //5 clock cycle delay between sending data to cu and getting data from accumulators
            //if cu_accum_adder_chain_set == 14'b00_0000_0000_0000;
            //   cu_accum_out_data_mux == 15'b000_0000_0000_0000;
            if (
                (proc_ctr > (2 * SYSTOL_ACTIVATION_COUNT + 5)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 3 * SYSTOL_ACTIVATION_COUNT) + 5))
            ) begin : accum_results_check

                for(integer z = 0; z < (proc_ctr - (2* SYSTOL_ACTIVATION_COUNT + 5)); z++) begin
                    col = proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 5) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.accum_dout[row] == mul_result_matrix_2[row][col]) begin
                            $display("TRUE  | [%0t] Accum_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.accum_dout[row], row, col, mul_result_matrix_2[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] Accum_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.accum_dout[row], row, col, mul_result_matrix_2[row][col]);
                        end
                    end
                end             
            end

            //offset results check
            //6 clock cycle delay between sending data to cu and getting data from offsets
            if (
                (proc_ctr > (2 * SYSTOL_ACTIVATION_COUNT + 6)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 3 * SYSTOL_ACTIVATION_COUNT) + 6))
            ) begin : offset_results_check

                for(integer z=0; z < (proc_ctr - (2* SYSTOL_ACTIVATION_COUNT + 6)); z++) begin
                    col = proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 6) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu.offsets_dout[row] == offset_result_matrix_2[row][col]) begin
                            $display("TRUE  | [%0t] Offsets_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.offsets_dout[row], row, col, offset_result_matrix_2[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] Offsets_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu.offsets_dout[row], row, col, offset_result_matrix_2[row][col]);
                        end
                    end
                end             
            end

            //cu results check
            //7 clock cycle delay between sending data to cu and getting data from offsets
            if (
                (proc_ctr > (2 * SYSTOL_ACTIVATION_COUNT + 7)) && 
                (proc_ctr <= ((SYSTOL_WEIGHT_COUNT + 3 * SYSTOL_ACTIVATION_COUNT) + 7))
            ) begin : CU_results_check

                for(integer z=0; z < (proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 7)); z++) begin
                    col = proc_ctr - (2 * SYSTOL_ACTIVATION_COUNT + 7) - 1 - z;
                    row = z;
                    if((row < SYSTOL_WEIGHT_COUNT) && (col < SYSTOL_WEIGHT_COUNT)) begin
                        if(cu_result[row] == cu_result_matrix_2[row][col]) begin
                            $display("TRUE  | [%0t] CU_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu_result[row], row, col, cu_result_matrix_2[row][col]);
                        end
                        else begin
                            $display("FALSE | [%0t] CU_out | C[%0d][%0d] = %0d | C_gold[%0d][%0d] = %0d ", 
                                    $time, row, col, cu_result[row], row, col, cu_result_matrix_2[row][col]);
                        end
                    end
                end             
            end

            proc_ctr = proc_ctr + 1;
        end

        $display("========================================");
        $display("----------matrix_mul_test_2 END---------");
        $display("");
    end
endtask

initial begin : main
    $timeformat(-9, 0, "ns");

    cu_weight_update = 0;
    cu_activation_wr_en = 0;
    cu_weight_wr_en = 0;
    cu_offset_wr_en = 0;

    cu_accum_adder_chain_set = 14'b00_0000_0000_0000;
    cu_accum_out_data_mux = 15'b000_0000_0000_0000;
    
    for(integer i=0; i<SYSTOL_ACTIVATION_COUNT;i++)	begin
        cu_activation[i] = 0;
    end
    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        cu_weight[i] = 0;
    end
    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        cu_offset[i] = 0;
    end
    
    @(negedge sys_rst);
    
    @(negedge cu_rst_busy);
    
    begin : input_data_generation
    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        for(integer j=0; j<SYSTOL_ACTIVATION_COUNT;j++)	begin
            weight_matrix_1[i][j] = ($random % 8192) + 1;
            activation_matrix_1[j][i] = ($random % 8192) + 1;

            weight_matrix_2[i][j] = weight_matrix_1[i][j];
            activation_matrix_2[j][i] = activation_matrix_1[j][i];
        end
    end

    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
            offset_matrix_1[i][j] = ($random % 8192) + 1;

            offset_matrix_2[i][j] = offset_matrix_1[i][j];
        end
    end
    end
    
    begin : input_data_display
    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        for(integer j=0; j<SYSTOL_ACTIVATION_COUNT;j++)	begin
            $display("weight[%0d][%0d] = %0d", i, j, weight_matrix_1[i][j]);
        end
    end
    
    for(integer i=0; i<SYSTOL_ACTIVATION_COUNT;i++)	begin
        for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
            $display("activation[%0d][%0d] = %0d", i, j, activation_matrix_1[i][j]);
        end
    end

    for(integer i=0; i<SYSTOL_WEIGHT_COUNT;i++)	begin
        for(integer j=0; j<SYSTOL_WEIGHT_COUNT;j++)	begin
            $display("offset[%0d][%0d] = %0d", i, j, offset_matrix_1[i][j]);
        end
    end
    end
    
    matrix_mul_test_1();

    matrix_mul_test_2();

    $finish;
    
end

endmodule   
