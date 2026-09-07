-- pattern_gen - Demo picture source: a slowly drifting colour gradient.
--
-- Writes one pixel per clock cycle, sweeping the whole picture over and over,
-- so the frame buffer is always fully painted. The colours are a function of
-- the pixel's position and a phase counter, and the phase advances only about
-- fifty times a second -- slowly enough that the picture is effectively static
-- within one panel refresh, which is what keeps the un-buffered write port from
-- tearing. See the note in hub75.vhd.
--
-- This is scaffolding for bringing a panel up, not a display list. Replace it
-- with whatever actually has something to say.
--
-- RESET
--   Synchronous, active high. Restarts the sweep from the top-left pixel.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.hub75_pkg.LOG2_CEIL;

entity pattern_gen is
   generic (
      G_COLS       : positive := 32;
      G_ROWS       : positive := 16;
      G_COLOR_BITS : positive := 6;
      G_PHASE_BITS : positive := 21   -- clk_i cycles per phase step, log2
   );
   port (
      clk_i     : in  std_logic;
      rst_i     : in  std_logic;  -- synchronous reset, active high
      wr_en_o   : out std_logic;
      wr_addr_o : out std_logic_vector(log2_ceil(G_ROWS)+log2_ceil(G_COLS)-1 downto 0);
      wr_data_o : out std_logic_vector(3*G_COLOR_BITS-1 downto 0)
   );
end entity pattern_gen;

architecture synthesis of pattern_gen is

   constant C_COL_BITS  : natural := log2_ceil(G_COLS);
   constant C_ADDR_BITS : natural := log2_ceil(G_ROWS) + C_COL_BITS;

   signal addr      : std_logic_vector(C_ADDR_BITS-1 downto 0)  := (others => '0');
   signal phase_cnt : std_logic_vector(G_PHASE_BITS-1 downto 0) := (others => '0');
   signal phase     : std_logic_vector(G_COLOR_BITS-1 downto 0) := (others => '0');

   signal pos_x : std_logic_vector(G_COLOR_BITS-1 downto 0);
   signal pos_y : std_logic_vector(G_COLOR_BITS-1 downto 0);

begin

   pos_x <= resize(addr(C_COL_BITS-1 downto 0), G_COLOR_BITS);
   pos_y <= resize(addr(C_ADDR_BITS-1 downto C_COL_BITS), G_COLOR_BITS);


   p_sweep : process (clk_i)
   begin
      if rising_edge(clk_i) then
         addr      <= addr + 1;
         phase_cnt <= phase_cnt + 1;

         if and(phase_cnt) = '1' then
            phase <= phase + 1;
         end if;

         if rst_i = '1' then
            addr      <= (others => '0');
            phase_cnt <= (others => '0');
            phase     <= (others => '0');
         end if;
      end if;
   end process p_sweep;


   -- Three ramps drifting against each other: red along the panel, green down
   -- it at four times the rate so the sixteen rows still span the range, and
   -- blue running backwards so the three never line up into grey.
   wr_en_o   <= '1';
   wr_addr_o <= addr;
   wr_data_o <= (pos_x + phase) & (pos_y(G_COLOR_BITS-3 downto 0) & "00") & (phase - pos_x);

end architecture synthesis;
