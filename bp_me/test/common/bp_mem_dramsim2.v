/**
 * bp_mem_dramsim2.v
 *
 */

module bp_mem_dramsim2
  import bp_common_pkg::*;
  import bp_cce_pkg::*;
  #(parameter num_lce_p="inv"
    ,parameter num_cce_p="inv"
    ,parameter paddr_width_p="inv"
    ,parameter lce_assoc_p="inv"
    ,parameter block_size_in_bytes_p="inv"
    ,parameter block_size_in_bits_lp=block_size_in_bytes_p*8
    ,parameter lce_sets_p="inv"

    ,parameter lce_req_data_width_p="inv"

    ,parameter mem_els_p="inv"

    ,parameter bp_mem_cce_resp_width_lp=`bp_mem_cce_resp_width(paddr_width_p, num_lce_p, lce_assoc_p)
    ,parameter bp_mem_cce_data_resp_width_lp=`bp_mem_cce_data_resp_width(paddr_width_p, block_size_in_bits_lp, num_lce_p, lce_assoc_p)
    ,parameter bp_cce_mem_cmd_width_lp=`bp_cce_mem_cmd_width(paddr_width_p, num_lce_p, lce_assoc_p)
    ,parameter bp_cce_mem_data_cmd_width_lp=`bp_cce_mem_data_cmd_width(paddr_width_p, block_size_in_bits_lp, num_lce_p, lce_assoc_p)

    ,parameter mem_addr_width_lp=`BSG_SAFE_CLOG2(mem_els_p)
    ,parameter block_offset_bits_lp=`BSG_SAFE_CLOG2(block_size_in_bytes_p)
    ,parameter byte_width_lp=8
    ,localparam word_offset_bits_lp=`BSG_SAFE_CLOG2(lce_req_data_width_p/8)
  )
  (
    input clk_i
    ,input reset_i

    // CCE-MEM Interface
    // CCE to Mem, Mem is demanding and uses vaild->ready (valid-yumi)
    ,input logic [bp_cce_mem_cmd_width_lp-1:0] mem_cmd_i
    ,input logic mem_cmd_v_i
    ,output logic mem_cmd_yumi_o

    ,input logic [bp_cce_mem_data_cmd_width_lp-1:0] mem_data_cmd_i
    ,input logic mem_data_cmd_v_i
    ,output logic mem_data_cmd_yumi_o

    // Mem to CCE, Mem is demanding and uses ready->valid
    ,output logic [bp_mem_cce_resp_width_lp-1:0] mem_resp_o
    ,output logic mem_resp_v_o
    ,input logic mem_resp_ready_i

    ,output logic [bp_mem_cce_data_resp_width_lp-1:0] mem_data_resp_o
    ,output logic mem_data_resp_v_o
    ,input logic mem_data_resp_ready_i
  );

  `declare_bp_me_if(paddr_width_p, block_size_in_bits_lp, num_lce_p, lce_assoc_p);

  bp_cce_mem_cmd_s mem_cmd_s_r, mem_cmd_i_s;
  bp_cce_mem_data_cmd_s mem_data_cmd_s_r, mem_data_cmd_i_s;
  bp_mem_cce_resp_s mem_resp_s_o;
  bp_mem_cce_data_resp_s mem_data_resp_s_o;

  // memory signals
  logic [paddr_width_p-1:0] block_rd_addr, block_wr_addr;
  logic [lce_req_data_width_p-1:0] mem_nc_data, nc_data;

  logic [511:0] dramsim_data;
  logic dramsim_valid;
  logic [511:0] dramsim_data_n;

  int k, j;
  always_comb begin
    mem_resp_o = mem_resp_s_o;
    mem_data_resp_o = mem_data_resp_s_o;
    mem_cmd_i_s = mem_cmd_i;
    mem_data_cmd_i_s = mem_data_cmd_i;

    block_rd_addr = {mem_cmd_i_s.addr[paddr_width_p-1:block_offset_bits_lp], block_offset_bits_lp'(0)};
    block_wr_addr = {mem_data_cmd_i_s.addr[paddr_width_p-1:block_offset_bits_lp], block_offset_bits_lp'(0)};

    // get the 64-bit chunk
    k = mem_cmd_s_r.addr[block_offset_bits_lp-1:word_offset_bits_lp];
    j = mem_cmd_s_r.addr[word_offset_bits_lp-1:0];
    mem_nc_data = dramsim_data[(k*lce_req_data_width_p)+:lce_req_data_width_p];
    if (mem_cmd_s_r.nc_size == e_lce_nc_req_1) begin
      nc_data = {56'('0),mem_nc_data[(j*8)+:8]};
    end else if (mem_cmd_s_r.nc_size == e_lce_nc_req_2) begin
      nc_data = {48'('0),mem_nc_data[(j*8)+:16]};
    end else if (mem_cmd_s_r.nc_size == e_lce_nc_req_4) begin
      nc_data = {32'('0),mem_nc_data[(j*8)+:32]};
    end else if (mem_cmd_s_r.nc_size == e_lce_nc_req_8) begin
      nc_data = mem_nc_data;
    end else begin
      nc_data = '0;
    end
  end

  typedef enum logic [2:0] {
    RESET
    ,READY
    ,RD_CMD
    ,RD_MEM
    ,RD_DATA_CMD
  } mem_state_e;

  mem_state_e mem_st;

  // synopsys sync_set_reset "reset_i"
  always_ff @(posedge clk_i) begin
    if (reset_i) begin
      mem_st <= RESET;

      // outputs
      mem_resp_v_o <= '0;
      mem_data_resp_v_o <= '0;
      mem_resp_s_o <= '0;
      mem_data_resp_s_o <= '0;

      // inputs
      mem_data_cmd_s_r <= '0;
      mem_data_cmd_yumi_o <= '0;
      mem_cmd_s_r <= '0;
      mem_cmd_yumi_o <= '0;
    end
    else begin
      mem_resp_s_o <= '0;
      mem_resp_v_o <= '0;
      mem_data_resp_s_o <= '0;
      mem_data_resp_v_o <= '0;

      case (mem_st)
        RESET: begin
          mem_st <= READY;
        end
        READY: begin
          // mem data command - need to write data to memory
          if (mem_data_cmd_v_i && mem_resp_ready_i) begin
            mem_data_cmd_yumi_o <= 1'b1;
            mem_data_cmd_s_r <= mem_data_cmd_i;
            mem_st <= RD_DATA_CMD;

            // do the write to memory ram
            mem_write_req(block_wr_addr, mem_data_cmd_i_s.data);
          // mem command - need to read data from memory
          end else if (mem_cmd_v_i && mem_data_resp_ready_i) begin
            mem_cmd_yumi_o <= 1'b1;
            mem_cmd_s_r <= mem_cmd_i;
            mem_st <= RD_MEM;

            // register the inputs for the memory, memory will consume them next cycle
            mem_read_req(block_rd_addr);
          end
        end
        RD_MEM: begin
          // read from memory, data will be available next cycle
          mem_cmd_yumi_o <= '0;
          mem_st <= dramsim_valid ? RD_CMD : RD_MEM;
        end
        RD_CMD: begin
          mem_st <= READY;

          mem_data_resp_s_o.msg_type <= mem_cmd_s_r.msg_type;
          mem_data_resp_s_o.payload.lce_id <= mem_cmd_s_r.payload.lce_id;
          mem_data_resp_s_o.payload.way_id <= mem_cmd_s_r.payload.way_id;
          mem_data_resp_s_o.addr <= mem_cmd_s_r.addr;
          if (mem_cmd_s_r.non_cacheable) begin
            mem_data_resp_s_o.data <= {(block_size_in_bits_lp-lce_req_data_width_p)'('0),nc_data};
          end else begin
            mem_data_resp_s_o.data <= dramsim_data;
          end
          mem_data_resp_s_o.non_cacheable <= mem_cmd_s_r.non_cacheable;
          mem_data_resp_s_o.nc_size <= mem_cmd_s_r.nc_size;

          // pull valid high
          mem_data_resp_v_o <= 1'b1;
        end
        RD_DATA_CMD: begin
          mem_data_cmd_yumi_o <= '0;
          mem_st <= dramsim_valid ? READY : RD_DATA_CMD;

          mem_resp_s_o.msg_type <= mem_data_cmd_s_r.msg_type;
          mem_resp_s_o.addr <= mem_data_cmd_s_r.addr;
          mem_resp_s_o.payload.lce_id <= mem_data_cmd_s_r.payload.lce_id;
          mem_resp_s_o.payload.way_id <= mem_data_cmd_s_r.payload.way_id;
          mem_resp_s_o.payload.req_addr <= mem_data_cmd_s_r.payload.req_addr;
          mem_resp_s_o.payload.tr_lce_id <= mem_data_cmd_s_r.payload.tr_lce_id;
          mem_resp_s_o.payload.tr_way_id <= mem_data_cmd_s_r.payload.tr_way_id;
          mem_resp_s_o.payload.transfer <= mem_data_cmd_s_r.payload.transfer;
          mem_resp_s_o.payload.replacement <= mem_data_cmd_s_r.payload.replacement;
          mem_resp_s_o.non_cacheable <= mem_data_cmd_s_r.non_cacheable;
          mem_resp_s_o.nc_size <= mem_data_cmd_s_r.nc_size;

          // pull valid high
          mem_resp_v_o <= 1'b1;
        end
        default: begin
          mem_st <= RESET;
        end
      endcase
    end
  end

import "DPI-C" function void init(input longint clock_period);
import "DPI-C" function bit tick();

import "DPI-C" function void mem_read_req(input longint addr);
import "DPI-C" function void mem_write_req(input longint addr, input bit [511:0] data);

export "DPI-C" function read_resp;
export "DPI-C" function write_resp;

function void read_resp(input bit [511:0] data);
  dramsim_data_n  = data;
endfunction

function void write_resp();

endfunction

initial 
  begin
    init(1000); // TODO: Change me to clock period of system
  end

always_ff @(posedge clk_i)
  begin
    dramsim_valid <= tick(); 
    dramsim_data  <= dramsim_data_n;
  end

endmodule
