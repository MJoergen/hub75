-- top_nexys4ddr - Board level wrapper: drives a 32x16 HUB75 panel from a
-- Digilent Nexys 4 DDR, showing the demo gradient.
--
-- The panel hangs off two Pmod headers, JB and JC; see hw/nexys4ddr.xdc for the
-- pin assignment and the wiring table in the README.
--
-- LEVEL SHIFTING IS NOT OPTIONAL, even though it will appear to work without.
-- The Artix-7's Pmod pins are 3.3 V LVCMOS and the panel's input buffer is
-- typically a 74HC245 running off 5 V, whose guaranteed input high is 3.5 V.
-- Driving it directly is out of spec: it works on a short cable at room
-- temperature and fails intermittently otherwise. Put a 74AHCT245 in between --
-- it takes 3.3 V inputs and drives 5 V outputs -- and the problem is gone.
--
-- RESET
--   Two sources, ORed: the CPU_RESETN button, synchronised into clk_i, and a
--   power-on stretch that holds reset for the first few hundred cycles after
--   configuration. The latter matters because nothing else guarantees the
--   scanner starts from a blanked panel.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity top_nexys4ddr is
   generic (
      G_COLS       : positive := 32;
      G_ROWS       : positive := 16;
      G_COLOR_BITS : positive := 6;
      G_CLK_DIV    : positive := 4;   -- 100 MHz / 4 = 25 MHz panel shift clock
      G_BASE_TICKS : positive := 40
   );
   port (
      clk_i        : in  std_logic;   -- 100 MHz, pin E3
      rstn_i       : in  std_logic;   -- CPU_RESETN, pin C12, active low
      hub75_r1_o   : out std_logic;
      hub75_g1_o   : out std_logic;
      hub75_b1_o   : out std_logic;
      hub75_r2_o   : out std_logic;
      hub75_g2_o   : out std_logic;
      hub75_b2_o   : out std_logic;
      hub75_a_o    : out std_logic_vector(2 downto 0);
      hub75_clk_o  : out std_logic;
      hub75_lat_o  : out std_logic;
      hub75_oe_n_o : out std_logic;
      led_o        : out std_logic_vector(1 downto 0)
   );
end entity top_nexys4ddr;

architecture synthesis of top_nexys4ddr is

   -- Held all-ones out of configuration and shifted empty from the left, so
   -- reset releases C_POR_BITS cycles after the first clock edge.
   constant C_POR_BITS : natural := 8;

   signal por       : std_logic_vector(C_POR_BITS-1 downto 0) := (others => '1');
   signal rstn_meta : std_logic := '0';
   signal rstn_sync : std_logic := '0';
   signal rst       : std_logic := '1';

   signal heartbeat : std_logic_vector(25 downto 0) := (others => '0');

   signal pat2hub_wr_en   : std_logic;
   signal pat2hub_wr_addr : std_logic_vector(8 downto 0);
   signal pat2hub_wr_data : std_logic_vector(3*G_COLOR_BITS-1 downto 0);

   signal oe_n : std_logic;

begin

   -- The button is asynchronous to clk_i and is double-flopped before use.
   p_reset : process (clk_i)
   begin
      if rising_edge(clk_i) then
         rstn_meta <= rstn_i;
         rstn_sync <= rstn_meta;
         por       <= por(C_POR_BITS-2 downto 0) & '0';
         rst       <= por(C_POR_BITS-1) or not rstn_sync;
      end if;
   end process p_reset;


   p_heartbeat : process (clk_i)
   begin
      if rising_edge(clk_i) then
         heartbeat <= heartbeat + 1;
      end if;
   end process p_heartbeat;


   i_pattern_gen : entity work.pattern_gen
      generic map (
         G_COLS       => G_COLS,
         G_ROWS       => G_ROWS,
         G_COLOR_BITS => G_COLOR_BITS
      )
      port map (
         clk_i     => clk_i,
         rst_i     => rst,
         wr_en_o   => pat2hub_wr_en,
         wr_addr_o => pat2hub_wr_addr,
         wr_data_o => pat2hub_wr_data
      ); -- i_pattern_gen


   i_hub75 : entity work.hub75
      generic map (
         G_COLS       => G_COLS,
         G_ROWS       => G_ROWS,
         G_COLOR_BITS => G_COLOR_BITS,
         G_CLK_DIV    => G_CLK_DIV,
         G_BASE_TICKS => G_BASE_TICKS
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst,
         wr_en_i      => pat2hub_wr_en,
         wr_addr_i    => pat2hub_wr_addr,
         wr_data_i    => pat2hub_wr_data,
         hub75_r1_o   => hub75_r1_o,
         hub75_g1_o   => hub75_g1_o,
         hub75_b1_o   => hub75_b1_o,
         hub75_r2_o   => hub75_r2_o,
         hub75_g2_o   => hub75_g2_o,
         hub75_b2_o   => hub75_b2_o,
         hub75_a_o    => hub75_a_o,
         hub75_clk_o  => hub75_clk_o,
         hub75_lat_o  => hub75_lat_o,
         hub75_oe_n_o => oe_n
      ); -- i_hub75


   hub75_oe_n_o <= oe_n;

   -- LED0 blinks about once a second so a dark panel can be told apart from a
   -- dead bitstream; LED1 lights while the panel is actually being displayed.
   led_o <= (not oe_n) & heartbeat(25);

end architecture synthesis;
