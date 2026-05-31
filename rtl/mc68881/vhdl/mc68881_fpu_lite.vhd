-- Thin wrapper: instantiates mc68881_top with fpu_lite_g => true
-- for MC68040 hardware subset (11 ALU ops) on MiSTer Cyclone V.
-- This avoids Quartus mixed-language boolean generic issues.

library ieee;
use ieee.std_logic_1164.all;

entity mc68881_fpu_lite is
  port (
    a_in    : in  std_logic_vector(4 downto 0);
    d_in    : in  std_logic_vector(31 downto 0);
    d_out   : out std_logic_vector(31 downto 0);
    size_n  : in  std_logic_vector(1 downto 0);
    as_n    : in  std_logic;
    cs_n    : in  std_logic;
    rw      : in  std_logic;
    ds_n    : in  std_logic;
    dsack0_n: out std_logic;
    dsack1_n: out std_logic;
    reset_n : in  std_logic;
    clk     : in  std_logic;
    sense_n      : inout std_logic;
    status_valid : out std_logic;
    -- See mc68881_top.vhd for layout. Pass-through for the FRESTORE-hang
    -- diagnostic probe added in build #16.
    dbg_cir_state : out std_logic_vector(31 downto 0)
  );
end entity mc68881_fpu_lite;

architecture wrapper of mc68881_fpu_lite is
begin
  u_fpu : entity work.mc68881_top
    generic map (
      -- BCD/packed-decimal engine fails clk_sys (32.5 MHz) timing by 3.79 ns
      -- across 10+ paths in mc68881_packed_decimal_unit. Mac OS / System 6/7
      -- ROMs do not use FMOVE.P during boot and rare apps exercise it. Disable
      -- the full engine to recover slack; the FPU will respond to packed
      -- decimal opcodes with zeros (acceptable for our use case).
      packed_decimal_full_g => false,
      fpu_lite_g            => true
    )
    port map (
      a_in         => a_in,
      d_in         => d_in,
      d_out        => d_out,
      size_n       => size_n,
      as_n         => as_n,
      cs_n         => cs_n,
      rw           => rw,
      ds_n         => ds_n,
      dsack0_n     => dsack0_n,
      dsack1_n     => dsack1_n,
      reset_n      => reset_n,
      clk          => clk,
      sense_n      => sense_n,
      status_valid => status_valid,
      dbg_cir_state => dbg_cir_state
    );
end architecture wrapper;
