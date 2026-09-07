-- frame_buffer - Picture store for one HUB75 panel, split into the two halves
-- the panel drives at the same time.
--
-- FUNCTION
--   Writers see one linear picture: wr_addr_i is row & column, with row
--   counting 0 .. G_ROWS-1 from the top. Readers see the panel's view: one
--   address selects a column within a scan row and returns TWO pixels, the one
--   in the upper half on rd_upper_o and the one G_ROWS/2 rows below it on
--   rd_lower_o, which is exactly the pair the panel wants on R1/G1/B1 and
--   R2/G2/B2.
--
--   That is the whole reason this module exists rather than a bare RAM: the
--   split into two sdp_ram instances turns "read two pixels at once" into two
--   ordinary one-read RAMs, and the top bit of the write address picks which
--   one a write lands in. See sdp_ram.vhd's header for why three addresses on
--   one array is not an option.
--
-- PIXEL FORMAT
--   A pixel is red & green & blue, G_COLOR_BITS each, red in the most
--   significant bits.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) The read has a 1-cycle latency and is gated by rd_en_i; rd_upper_o and
--    rd_lower_o hold while rd_en_i = '0'.
-- b) A write to the address being read in the same cycle is read-first: the
--    read returns the old pixel. Nothing here needs the new one.
--
-- RESET
--   None. Picture contents survive rst_i by design -- the scanner is what gets
--   reset, not what it is showing.

library ieee;
   use ieee.std_logic_1164.all;

   use work.hub75_pkg.LOG2_CEIL;

entity frame_buffer is
   generic (
      G_COLS       : positive := 32;
      G_ROWS       : positive := 16;
      G_COLOR_BITS : positive := 6
   );
   port (
      clk_i      : in  std_logic;
      wr_en_i    : in  std_logic;
      wr_addr_i  : in  std_logic_vector(log2_ceil(G_ROWS)+log2_ceil(G_COLS)-1 downto 0);
      wr_data_i  : in  std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      rd_en_i    : in  std_logic;
      rd_addr_i  : in  std_logic_vector(log2_ceil(G_ROWS/2)+log2_ceil(G_COLS)-1 downto 0);
      rd_upper_o : out std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      rd_lower_o : out std_logic_vector(3*G_COLOR_BITS-1 downto 0)
   );
end entity frame_buffer;

architecture synthesis of frame_buffer is

   constant C_HALF_ADDR : natural := log2_ceil(G_ROWS/2) + log2_ceil(G_COLS);

   -- The top write-address bit is the row's most significant bit, which is
   -- precisely "is this pixel in the lower half".
   signal wr_lower    : std_logic;
   signal wr_en_upper : std_logic;
   signal wr_en_lower : std_logic;

begin

   wr_lower    <= wr_addr_i(wr_addr_i'left);
   wr_en_upper <= wr_en_i and not wr_lower;
   wr_en_lower <= wr_en_i and wr_lower;


   i_sdp_ram_upper : entity work.sdp_ram
      generic map (
         G_ADDR_SIZE => C_HALF_ADDR,
         G_DATA_SIZE => 3*G_COLOR_BITS
      )
      port map (
         clk_i     => clk_i,
         wr_en_i   => wr_en_upper,
         wr_addr_i => wr_addr_i(C_HALF_ADDR-1 downto 0),
         wr_data_i => wr_data_i,
         rd_en_i   => rd_en_i,
         rd_addr_i => rd_addr_i,
         rd_data_o => rd_upper_o
      ); -- i_sdp_ram_upper


   i_sdp_ram_lower : entity work.sdp_ram
      generic map (
         G_ADDR_SIZE => C_HALF_ADDR,
         G_DATA_SIZE => 3*G_COLOR_BITS
      )
      port map (
         clk_i     => clk_i,
         wr_en_i   => wr_en_lower,
         wr_addr_i => wr_addr_i(C_HALF_ADDR-1 downto 0),
         wr_data_i => wr_data_i,
         rd_en_i   => rd_en_i,
         rd_addr_i => rd_addr_i,
         rd_data_o => rd_lower_o
      ); -- i_sdp_ram_lower

end architecture synthesis;
