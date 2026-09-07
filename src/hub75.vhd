-- hub75 - Complete driver for one HUB75 LED matrix panel.
--
-- Ties the picture store to the scanner and exposes the two things a user of
-- this core cares about: a write port for pixels, and the panel's own pins.
-- There is nothing else to configure -- the scanner free-runs from reset and
-- keeps the panel refreshed whether or not anyone ever writes a pixel.
--
-- WRITING PIXELS
--   wr_addr_i is row & column with row 0 at the top, so address zero is the
--   top-left pixel and the picture is stored the way it is read. wr_data_i is
--   red & green & blue, G_COLOR_BITS each, red in the most significant bits.
--   A write may happen on any cycle; it does not disturb the scan.
--
--   There is deliberately NO double buffering. A pixel written while the
--   scanner is part-way down the panel shows up immediately, so a picture
--   rewritten faster than the frame rate will tear. The demo pattern generator
--   avoids that by changing its picture only a few tens of times a second; a
--   design that cannot should add a second frame_buffer and swap between them
--   at the top of a frame.
--
-- SIZING
--   The defaults describe the panel this was written for: 32x16 at 1/8 scan,
--   which is three address lines and two halves of eight rows. G_ROWS/2 sets
--   the scan rate, so a 32x32 panel at 1/16 scan is G_ROWS => 32 and a wider
--   address port, no other change.
--
-- RESET
--   Synchronous, active high, and only the scanner sees it. The picture
--   survives; see frame_buffer.vhd.

library ieee;
   use ieee.std_logic_1164.all;

   use work.hub75_pkg.LOG2_CEIL;

entity hub75 is
   generic (
      G_COLS       : positive := 32;
      G_ROWS       : positive := 16;
      G_COLOR_BITS : positive := 6;
      G_CLK_DIV    : positive := 4;
      G_BASE_TICKS : positive := 40
   );
   port (
      clk_i        : in  std_logic;
      rst_i        : in  std_logic;  -- synchronous reset, active high
      wr_en_i      : in  std_logic;
      wr_addr_i    : in  std_logic_vector(log2_ceil(G_ROWS)+log2_ceil(G_COLS)-1 downto 0);
      wr_data_i    : in  std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      hub75_r1_o   : out std_logic;
      hub75_g1_o   : out std_logic;
      hub75_b1_o   : out std_logic;
      hub75_r2_o   : out std_logic;
      hub75_g2_o   : out std_logic;
      hub75_b2_o   : out std_logic;
      hub75_a_o    : out std_logic_vector(log2_ceil(G_ROWS/2)-1 downto 0);
      hub75_clk_o  : out std_logic;
      hub75_lat_o  : out std_logic;
      hub75_oe_n_o : out std_logic
   );
end entity hub75;

architecture synthesis of hub75 is

   signal scan2fb_rd_en   : std_logic;
   signal scan2fb_rd_addr : std_logic_vector(log2_ceil(G_ROWS/2)+log2_ceil(G_COLS)-1 downto 0);
   signal fb2scan_upper   : std_logic_vector(3*G_COLOR_BITS-1 downto 0);
   signal fb2scan_lower   : std_logic_vector(3*G_COLOR_BITS-1 downto 0);

begin

   i_frame_buffer : entity work.frame_buffer
      generic map (
         G_COLS       => G_COLS,
         G_ROWS       => G_ROWS,
         G_COLOR_BITS => G_COLOR_BITS
      )
      port map (
         clk_i      => clk_i,
         wr_en_i    => wr_en_i,
         wr_addr_i  => wr_addr_i,
         wr_data_i  => wr_data_i,
         rd_en_i    => scan2fb_rd_en,
         rd_addr_i  => scan2fb_rd_addr,
         rd_upper_o => fb2scan_upper,
         rd_lower_o => fb2scan_lower
      ); -- i_frame_buffer


   i_hub75_scan : entity work.hub75_scan
      generic map (
         G_COLS       => G_COLS,
         G_ROWS       => G_ROWS,
         G_COLOR_BITS => G_COLOR_BITS,
         G_CLK_DIV    => G_CLK_DIV,
         G_BASE_TICKS => G_BASE_TICKS
      )
      port map (
         clk_i        => clk_i,
         rst_i        => rst_i,
         fb_rd_en_o   => scan2fb_rd_en,
         fb_rd_addr_o => scan2fb_rd_addr,
         fb_upper_i   => fb2scan_upper,
         fb_lower_i   => fb2scan_lower,
         hub75_r1_o   => hub75_r1_o,
         hub75_g1_o   => hub75_g1_o,
         hub75_b1_o   => hub75_b1_o,
         hub75_r2_o   => hub75_r2_o,
         hub75_g2_o   => hub75_g2_o,
         hub75_b2_o   => hub75_b2_o,
         hub75_a_o    => hub75_a_o,
         hub75_clk_o  => hub75_clk_o,
         hub75_lat_o  => hub75_lat_o,
         hub75_oe_n_o => hub75_oe_n_o
      ); -- i_hub75_scan

end architecture synthesis;
