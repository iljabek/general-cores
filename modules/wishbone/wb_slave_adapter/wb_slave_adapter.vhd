--------------------------------------------------------------------------------
-- CERN BE-CO-HT
-- General Cores Library
-- https://www.ohwr.org/projects/general-cores
--------------------------------------------------------------------------------
--
-- unit name:   wb_slave_adapter
--
-- description:
--   universal "adapter"
--   pipelined <> classic
--   word-aligned/byte-aligned address
--
--------------------------------------------------------------------------------
-- Copyright CERN 2011-2018
--------------------------------------------------------------------------------
-- Copyright and related rights are licensed under the Solderpad Hardware
-- License, Version 2.0 (the "License"); you may not use this file except
-- in compliance with the License. You may obtain a copy of the License at
-- http://solderpad.org/licenses/SHL-2.0.
-- Unless required by applicable law or agreed to in writing, software,
-- hardware and materials distributed under this License is distributed on an
-- "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
-- or implied. See the License for the specific language governing permissions
-- and limitations under the License.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.wishbone_pkg.all;

entity wb_slave_adapter is

  generic (
    g_master_use_struct  : boolean;
    g_master_mode        : t_wishbone_interface_mode;
    g_master_granularity : t_wishbone_address_granularity;
    g_slave_use_struct   : boolean;
    g_slave_mode         : t_wishbone_interface_mode;
    g_slave_granularity  : t_wishbone_address_granularity
    );

  port (
    clk_sys_i : in std_logic;
    rst_n_i   : in std_logic;

-- slave port (i.e. wb_slave_adapter is slave)
    sl_adr_i : in std_logic_vector(c_wishbone_address_width-1 downto 0);
    sl_dat_i : in std_logic_vector(c_wishbone_data_width-1 downto 0);
    sl_sel_i : in std_logic_vector(c_wishbone_data_width/8-1 downto 0);
    sl_cyc_i : in std_logic;
    sl_stb_i : in std_logic;
    sl_we_i  : in std_logic;


    sl_dat_o   : out std_logic_vector(c_wishbone_data_width-1 downto 0);
    sl_err_o   : out std_logic;
    sl_rty_o   : out std_logic;
    sl_ack_o   : out std_logic;
    sl_stall_o : out std_logic;

    slave_i : in  t_wishbone_slave_in;
    slave_o : out t_wishbone_slave_out;

-- master port (i.e. wb_slave_adapter is master)
    ma_adr_o : out std_logic_vector(c_wishbone_address_width-1 downto 0);
    ma_dat_o : out std_logic_vector(c_wishbone_data_width-1 downto 0);
    ma_sel_o : out std_logic_vector(c_wishbone_data_width/8-1 downto 0);
    ma_cyc_o : out std_logic;
    ma_stb_o : out std_logic;
    ma_we_o  : out std_logic;

    ma_dat_i   : in std_logic_vector(c_wishbone_data_width-1 downto 0);
    ma_err_i   : in std_logic;
    ma_rty_i   : in std_logic;
    ma_ack_i   : in std_logic;
    ma_stall_i : in std_logic;

    master_i : in  t_wishbone_master_in;
    master_o : out t_wishbone_master_out
    );
end wb_slave_adapter;

architecture rtl of wb_slave_adapter is

  function f_num_byte_address_bits
    return integer is
  begin
    case c_wishbone_data_width is
      when 8      => return 0;
      when 16     => return 1;
      when 32     => return 2;
      when 64     => return 3;
      when others =>
        report "wb_slave_adapter: invalid c_wishbone_data_width (we support 8, 16, 32 and 64)" severity failure;
    end case;
    return 0;
  end f_num_byte_address_bits;

  function f_zeros(size : integer)
    return std_logic_vector is
  begin
    return std_logic_vector(to_unsigned(0, size));
  end f_zeros;

  type t_fsm_state is (IDLE, WAIT4ACK);

  signal fsm_state : t_fsm_state := IDLE;

  signal master_in  : t_wishbone_master_in;
  signal master_out : t_wishbone_master_out;
  signal slave_in   : t_wishbone_slave_in;
  signal slave_out  : t_wishbone_slave_out;
  signal stored_we  : std_logic;
  
begin  -- rtl

  gen_slave_use_struct : if (g_slave_use_struct) generate
    slave_in <= slave_i;
  end generate gen_slave_use_struct;

  gen_slave_use_slv : if (not g_slave_use_struct) generate
    slave_in.cyc <= sl_cyc_i;
    slave_in.stb <= sl_stb_i;
    slave_in.we  <= sl_we_i;
    slave_in.dat <= sl_dat_i;
    slave_in.sel <= sl_sel_i;
    slave_in.adr <= sl_adr_i;
  end generate gen_slave_use_slv;

  slave_o    <= slave_out;
  sl_ack_o   <= slave_out.ack;
  sl_rty_o   <= slave_out.rty;
  sl_err_o   <= slave_out.err;
  sl_stall_o <= slave_out.stall;
  sl_dat_o   <= slave_out.dat;
  

  gen_master_use_struct : if (g_master_use_struct) generate
    master_in <= master_i;
  end generate gen_master_use_struct;

  gen_master_use_slv : if (not g_master_use_struct) generate
    master_in <= (
      ack   => ma_ack_i,
      rty   => ma_rty_i,
      err   => ma_err_i,
      dat   => ma_dat_i,
      stall => ma_stall_i);
  end generate gen_master_use_slv;

  master_o <= master_out;
  ma_adr_o <= master_out.adr;
  ma_dat_o <= master_out.dat;
  ma_sel_o <= master_out.sel;
  ma_cyc_o <= master_out.cyc;
  ma_stb_o <= master_out.stb;
  ma_we_o  <= master_out.we;

  p_gen_address : process(slave_in, master_out)
  begin
    if(g_master_granularity = g_slave_granularity) then
      master_out.adr <= slave_in.adr;
    elsif(g_master_granularity = BYTE) then  -- byte->word
      master_out.adr <= slave_in.adr(c_wishbone_address_width-f_num_byte_address_bits-1 downto 0)
                        & f_zeros(f_num_byte_address_bits);
    else
      master_out.adr <= f_zeros(f_num_byte_address_bits)
                        & slave_in.adr(c_wishbone_address_width-1 downto f_num_byte_address_bits);
    end if;
  end process;
  
  P2C : if (g_slave_mode = PIPELINED and g_master_mode = CLASSIC)   generate
    master_out.stb  <= slave_in.stb;
    slave_out.stall <= not master_in.ack;
  end generate;
  
  C2P : if (g_slave_mode = CLASSIC   and g_master_mode = PIPELINED) generate
    master_out.stb  <= slave_in.stb when fsm_state=IDLE else '0';
    slave_out.stall <= '0'; -- classic will ignore this anyway
    
    state_machine : process(clk_sys_i) is
    begin
      if rising_edge(clk_sys_i) then
        if rst_n_i = '0' then
          fsm_state <= IDLE;
        else
          case fsm_state is
            when IDLE => 
              if slave_in.stb ='1' and slave_in.cyc = '1' and master_in.stall='0' and master_in.ack='0' then
                fsm_state <= WAIT4ACK;
              end if;
            when WAIT4ACK => 
              if (slave_in.stb = '0' and slave_in.cyc = '0') or master_in.ack='1' or master_in.err='1' then 
                fsm_state <= IDLE;
              end if;
          end case;
        end if;
      end if;
    end process;
  end generate;
  
  X2X : if (g_slave_mode = g_master_mode) generate
    master_out.stb  <= slave_in.stb;
    slave_out.stall <= master_in.stall;
  end generate;
  
  master_out.dat <= slave_in.dat;
  master_out.cyc <= slave_in.cyc;
  master_out.sel <= slave_in.sel;
  master_out.we  <= slave_in.we;

  slave_out.ack <= master_in.ack;
  slave_out.err <= master_in.err;
  slave_out.rty <= master_in.rty;
  slave_out.dat <= master_in.dat;
end rtl;
