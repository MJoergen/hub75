-- hub75_scan - Row scanner and binary-code-modulation sequencer for a HUB75
-- LED matrix panel.
--
-- A HUB75 panel has no frame store and no brightness control of its own. It is
-- a pair of long shift registers feeding constant-current sinks, plus a 1-of-N
-- row decoder. Everything -- refresh, row multiplexing, grey scale -- has to be
-- generated here, continuously, or the panel goes dark.
--
-- THEORY OF OPERATION
--   The panel is driven one (row, bit-plane) pair at a time, in three phases:
--
--     SHIFT   G_COLS pixels are clocked into the shift registers on
--             hub75_clk_o, one bit per colour per half of the panel. The bit
--             chosen is bit "plane" of each colour channel, not the whole
--             value -- see grey scale below.
--     LATCH   The panel is already blanked (hub75_oe_n_o = '1' throughout
--             SHIFT). The row address is applied, hub75_lat_o pulses to move
--             the shift registers into the output latches, and only then is
--             the blank released.
--     DISPLAY The row is lit for a time proportional to the plane's weight,
--             then blanked again and the next plane starts.
--
--   GREY SCALE IS BINARY CODE MODULATION. Plane p is displayed for
--   2**p * G_BASE_TICKS ticks, so the time a channel spends lit over one pass
--   through all planes is proportional to its value -- an 8-bit channel needs 8
--   passes, not 255. What makes this correct is that each plane's DISPLAY phase
--   is exactly 2**p * G_BASE_TICKS long regardless of what the shift and latch
--   around it cost; the constant per-plane overhead dims the panel uniformly,
--   it does not distort the weighting.
--
--   Planes are the inner loop and rows the outer one, so a row runs its whole
--   intensity sequence before the address moves on. That keeps hub75_a_o
--   changing once per row rather than once per plane.
--
--   REFRESH RATE follows from the above. One row costs
--     sum over p of (G_COLS + 2 + 4 + 2**p * G_BASE_TICKS) ticks
--   and a frame is G_ROWS/2 of those. With the defaults -- 32 columns, 6 bits,
--   40 base ticks, a 25 MHz tick -- the testbench measures 879 us, i.e.
--   1137 Hz, comfortably above the 300 Hz the panels are specified for.
--   Trading up to 8-bit colour costs a factor of four and still clears 300 Hz.
--
--   THE PIXEL PIPELINE IS TWO TICKS DEEP. The frame buffer read is registered,
--   so the address issued at the end of tick n yields data during tick n+1,
--   which is registered onto the colour pins at the end of it and shifted in on
--   tick n+2. That is why the column counter runs to G_COLS+1 and the shift
--   clock is gated off for its first two ticks: those two ticks are filling the
--   pipeline, and the G_COLS pulses that follow carry columns 0 .. G_COLS-1.
--
-- INTERFACE CONTRACTS -- these are requirements on the environment:
-- a) fb_upper_i / fb_lower_i must present the pixel for fb_rd_addr_o exactly
--    one clk_i cycle after the address is driven, and hold it while
--    fb_rd_en_o = '0'. frame_buffer.vhd does both.
-- b) G_CLK_DIV must be at least 2. The shift clock is derived by splitting the
--    tick window in half, which needs two clk_i cycles to split.
-- c) G_COLS and G_ROWS must be powers of two. The column counter carries one
--    spare bit and is allowed to wrap past the last column during the two
--    pipeline-fill ticks; the reads it issues there are discarded, but they
--    must stay in range.
--
-- ORIENTATION
--   Columns are shifted out low-numbered first. If the picture comes out
--   mirrored left-to-right on your panel, the shift register is filled from the
--   other end: count col downwards instead. Nothing else changes.
--
-- RESET
--   Synchronous, active high. Returns to the start of SHIFT with the panel
--   blanked, so a reset is always safe: hub75_oe_n_o = '1' means every LED is
--   off, which is also what the panel powers up needing.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

   use work.hub75_pkg.LOG2_CEIL;

entity hub75_scan is
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
      fb_rd_en_o   : out std_logic;
      fb_rd_addr_o : out std_logic_vector(log2_ceil(G_ROWS/2)+log2_ceil(G_COLS)-1 downto 0);
      fb_upper_i   : in  std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      fb_lower_i   : in  std_logic_vector(3*G_COLOR_BITS-1 downto 0);
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
end entity hub75_scan;

architecture synthesis of hub75_scan is

   constant C_ROW_BITS : natural := log2_ceil(G_ROWS/2);
   constant C_COL_BITS : natural := log2_ceil(G_COLS);
   constant C_MAX_DISP : natural := G_BASE_TICKS * 2**(G_COLOR_BITS-1);

   type t_state is (shift_st, latch_st, display_st);

   signal state : t_state := shift_st;

   signal div_cnt : natural range 0 to G_CLK_DIV-1 := 0;
   signal tick    : std_logic;

   -- One bit wider than a column index, so that the two pipeline-fill ticks
   -- can be counted without a separate flag. See contract c).
   signal col      : std_logic_vector(C_COL_BITS downto 0) := (others => '0');
   signal row      : std_logic_vector(C_ROW_BITS-1 downto 0) := (others => '0');
   signal plane    : natural range 0 to G_COLOR_BITS-1 := 0;
   signal lat_cnt  : natural range 0 to 3 := 0;
   signal disp_cnt : natural range 0 to C_MAX_DISP := 0;
   signal disp_len : natural range 0 to C_MAX_DISP := G_BASE_TICKS;

   signal shift_en : std_logic;

   -- The three control outputs are registered internally rather than driven
   -- straight out of p_scan, so that they can carry a power-up value. A panel
   -- must be blanked from configuration, not merely from the first reset edge:
   -- reset is synchronous, so it cannot take effect until a clock has run, and
   -- until then oe_n would be undefined and the panel would be showing whatever
   -- its own shift registers powered up holding.
   signal pclk : std_logic := '0';
   signal lat  : std_logic := '0';
   signal oe_n : std_logic := '1';

   -- Driven onto fb_rd_addr_o. It exists as a signal of its own only so that it
   -- can carry a power-up value: the read enable is asserted from the very
   -- first cycle, one cycle before reset can drive an address, and an
   -- all-undefined address into the RAM is a simulation warning per cycle.
   signal fb_rd_addr : std_logic_vector(C_ROW_BITS+C_COL_BITS-1 downto 0) := (others => '0');

begin

   assert G_CLK_DIV >= 2
      report "hub75_scan: G_CLK_DIV must be at least 2, see contract b)"
      severity failure;


   ------------------------------------------------------------
   -- Tick generator
   ------------------------------------------------------------

   -- Everything below advances once per tick, i.e. at clk_i / G_CLK_DIV. The
   -- panel's shift clock is that same rate, so G_CLK_DIV sets it: 4 gives
   -- 25 MHz from a 100 MHz clk_i, which is what these panels take.
   p_divider : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if div_cnt = G_CLK_DIV-1 then
            div_cnt <= 0;
         else
            div_cnt <= div_cnt + 1;
         end if;

         if rst_i = '1' then
            div_cnt <= 0;
         end if;
      end if;
   end process p_divider;

   tick <= '1' when div_cnt = G_CLK_DIV-1 else
           '0';


   ------------------------------------------------------------
   -- Shift clock
   ------------------------------------------------------------

   -- High for the second half of every tick window, which puts its rising edge
   -- half a tick after the colour pins change and gives the panel that long as
   -- setup. The data then holds for the rest of the window as hold time.
   shift_en <= '1' when state = shift_st and col >= 2 else
               '0';

   p_shift_clk : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if shift_en = '1' and div_cnt >= G_CLK_DIV/2 then
            pclk <= '1';
         else
            pclk <= '0';
         end if;

         if rst_i = '1' then
            pclk <= '0';
         end if;
      end if;
   end process p_shift_clk;


   ------------------------------------------------------------
   -- Scan sequencer
   ------------------------------------------------------------

   fb_rd_en_o   <= '1' when state = shift_st else
                   '0';
   fb_rd_addr_o <= fb_rd_addr;
   hub75_clk_o  <= pclk;
   hub75_lat_o  <= lat;
   hub75_oe_n_o <= oe_n;

   p_scan : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if tick = '1' then

            case state is

               when shift_st =>
                  -- The frame buffer is presenting column col-2 right now.
                  -- Register it onto the colour pins; the clock pulse that
                  -- shifts it in happens during the next tick window.
                  hub75_r1_o <= fb_upper_i(2*G_COLOR_BITS + plane);
                  hub75_g1_o <= fb_upper_i(G_COLOR_BITS + plane);
                  hub75_b1_o <= fb_upper_i(plane);
                  hub75_r2_o <= fb_lower_i(2*G_COLOR_BITS + plane);
                  hub75_g2_o <= fb_lower_i(G_COLOR_BITS + plane);
                  hub75_b2_o <= fb_lower_i(plane);

                  -- Issue the read for column col. The last two of these run
                  -- past the end of the row and are discarded, see contract c).
                  fb_rd_addr <= row & col(C_COL_BITS-1 downto 0);
                  col        <= col + 1;

                  if col = G_COLS+1 then
                     state   <= latch_st;
                     lat_cnt <= 0;
                  end if;

               when latch_st =>
                  -- Blanked throughout, so the address may move freely here.
                  -- The step counter advances inside each arm rather than once
                  -- above the case, so that the last arm leaves it alone
                  -- instead of running it past the end of its range.
                  case lat_cnt is

                     when 0 =>
                        hub75_a_o <= row;
                        lat_cnt   <= 1;

                     when 1 =>
                        lat     <= '1';
                        lat_cnt <= 2;

                     when 2 =>
                        lat     <= '0';
                        lat_cnt <= 3;

                     when others =>
                        oe_n     <= '0';
                        disp_cnt <= 0;
                        state    <= display_st;

                  end case;

               when display_st =>
                  if disp_cnt = disp_len-1 then
                     oe_n  <= '1';
                     col   <= (others => '0');
                     state <= shift_st;

                     if plane = G_COLOR_BITS-1 then
                        plane    <= 0;
                        disp_len <= G_BASE_TICKS;
                        row      <= row + 1;
                     else
                        plane    <= plane + 1;
                        disp_len <= disp_len + disp_len;
                     end if;
                  else
                     disp_cnt <= disp_cnt + 1;
                  end if;

            end case;

         end if;

         if rst_i = '1' then
            state      <= shift_st;
            col        <= (others => '0');
            row        <= (others => '0');
            plane      <= 0;
            lat_cnt    <= 0;
            disp_cnt   <= 0;
            disp_len   <= G_BASE_TICKS;
            lat        <= '0';
            oe_n       <= '1';
            hub75_a_o  <= (others => '0');
            fb_rd_addr <= (others => '0');
         end if;
      end if;
   end process p_scan;

end architecture synthesis;
