-- tb_hub75 - Self-checking testbench for the HUB75 driver.
--
-- Reaching the end of the simulation is not the verdict; the checks below are.
-- The testbench fills the frame buffer with a known picture while the scanner
-- is held in reset, then releases it and decodes the panel interface the way
-- the panel itself would:
--
--   * every rising edge of hub75_clk_o captures the six colour pins into the
--     next column slot, exactly as the panel's shift registers would;
--   * every rising edge of hub75_lat_o checks the G_COLS captured values
--     against the bit-plane of the picture that should have been sent, checks
--     the row address against the row it should have been sent for, and checks
--     that the panel was blanked while it happened.
--
-- It also independently tracks the expected (row, plane) sequence, so a scanner
-- that emitted correct-looking data in the wrong order fails. The frame time is
-- measured between the first latches of successive frames and reported as a
-- refresh rate, which is the number the panel's >= 300 Hz specification is
-- about.
--
-- The simulation ends via std.env.finish(0) on success and stop(1) on failure,
-- so the exit code is the result.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;
   use std.env.all;

   use work.hub75_pkg.LOG2_CEIL;

entity tb_hub75 is
   generic (
      G_COLS       : positive := 32;
      G_ROWS       : positive := 16;
      G_COLOR_BITS : positive := 4;
      G_CLK_DIV    : positive := 4;
      G_BASE_TICKS : positive := 4;
      G_FRAMES     : positive := 2
   );
end entity tb_hub75;

architecture simulation of tb_hub75 is

   constant C_CLK_PERIOD : time    := 10 ns;                     -- 100 MHz
   constant C_COL_BITS   : natural := log2_ceil(G_COLS);
   constant C_ROW_BITS   : natural := log2_ceil(G_ROWS/2);
   constant C_ADDR_BITS  : natural := log2_ceil(G_ROWS) + C_COL_BITS;
   constant C_LATCHES    : natural := G_FRAMES * (G_ROWS/2) * G_COLOR_BITS;

   signal clk : std_logic := '1';
   signal rst : std_logic := '1';

   signal wr_en   : std_logic := '0';
   signal wr_addr : std_logic_vector(C_ADDR_BITS-1 downto 0) := (others => '0');
   signal wr_data : std_logic_vector(3*G_COLOR_BITS-1 downto 0) := (others => '0');

   signal hub75_r1   : std_logic;
   signal hub75_g1   : std_logic;
   signal hub75_b1   : std_logic;
   signal hub75_r2   : std_logic;
   signal hub75_g2   : std_logic;
   signal hub75_b2   : std_logic;
   signal hub75_a    : std_logic_vector(C_ROW_BITS-1 downto 0);
   signal hub75_clk  : std_logic;
   signal hub75_lat  : std_logic;
   signal hub75_oe_n : std_logic;

   signal hub75_clk_d : std_logic := '0';
   signal hub75_lat_d : std_logic := '0';

   -- Captured shift register, six colour pins per column: r1 g1 b1 r2 g2 b2.

   type t_capture is array (natural range 0 to G_COLS-1) of std_logic_vector(5 downto 0);

   signal capture     : t_capture;
   signal capture_cnt : natural range 0 to G_COLS := 0;

   signal exp_row   : natural range 0 to G_ROWS/2-1 := 0;
   signal exp_plane : natural range 0 to G_COLOR_BITS-1 := 0;

   signal latch_cnt  : natural := 0;
   signal error_cnt  : natural := 0;
   signal frame_time : time    := 0 ns;
   signal last_frame : time    := 0 ns;

   signal filled : std_logic := '0';

   -- The picture: an arbitrary but position-dependent value, chosen so that the
   -- three channels differ from each other and every plane differs from its
   -- neighbours. A driver that mixed up channels or planes cannot pass.
   function pixel_of (addr : natural) return std_logic_vector is
      variable base_v : std_logic_vector(G_COLOR_BITS-1 downto 0);
   begin
      base_v := to_stdlogicvector(addr mod 2**G_COLOR_BITS, G_COLOR_BITS);
      return base_v & (not base_v) & (base_v(0) & base_v(G_COLOR_BITS-1 downto 1));
   end function pixel_of;

begin

   clk <= not clk after C_CLK_PERIOD/2;


   ------------------------------------------------------------
   -- Stimulus
   ------------------------------------------------------------

   -- Fill the whole picture while the scanner is in reset, so that everything
   -- the checker sees afterwards comes from a settled frame buffer.
   p_stimulus : process
   begin
      rst   <= '1';
      wr_en <= '0';
      wait for 10 * C_CLK_PERIOD;

      for addr in 0 to G_ROWS*G_COLS-1 loop
         wait until rising_edge(clk);
         wr_en   <= '1';
         wr_addr <= to_stdlogicvector(addr, C_ADDR_BITS);
         wr_data <= pixel_of(addr);
      end loop;

      wait until rising_edge(clk);
      wr_en  <= '0';
      filled <= '1';

      wait for 10 * C_CLK_PERIOD;
      wait until rising_edge(clk);
      rst <= '0';

      wait;
   end process p_stimulus;


   ------------------------------------------------------------
   -- Panel model and checker
   ------------------------------------------------------------

   p_monitor : process (clk)
      variable up_addr_v : natural;
      variable lo_addr_v : natural;
      variable up_pix_v  : std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      variable lo_pix_v  : std_logic_vector(3*G_COLOR_BITS-1 downto 0);
      variable want_v    : std_logic_vector(5 downto 0);
   begin
      if rising_edge(clk) then
         hub75_clk_d <= hub75_clk;
         hub75_lat_d <= hub75_lat;

         if rst = '0' then

            -- A rising edge on the panel clock shifts one column in.
            if hub75_clk = '1' and hub75_clk_d = '0' then
               assert capture_cnt < G_COLS
                  report "tb_hub75: more than G_COLS clock pulses before a latch"
                  severity error;

               if capture_cnt < G_COLS then
                  capture(capture_cnt) <= hub75_r1 & hub75_g1 & hub75_b1 &
                                          hub75_r2 & hub75_g2 & hub75_b2;
                  capture_cnt          <= capture_cnt + 1;
               end if;
            end if;

            -- A rising edge on the latch moves that row into the panel.
            if hub75_lat = '1' and hub75_lat_d = '0' then
               assert hub75_oe_n = '1'
                  report "tb_hub75: latched while the panel was not blanked"
                  severity error;

               assert capture_cnt = G_COLS
                  report "tb_hub75: latched after " & integer'image(capture_cnt) &
                         " columns, expected " & integer'image(G_COLS)
                  severity error;

               assert hub75_a = to_stdlogicvector(exp_row, C_ROW_BITS)
                  report "tb_hub75: row address is " & integer'image(to_integer(hub75_a)) &
                         ", expected " & integer'image(exp_row)
                  severity error;

               if hub75_oe_n /= '1' or capture_cnt /= G_COLS or
                  hub75_a /= to_stdlogicvector(exp_row, C_ROW_BITS) then
                  error_cnt <= error_cnt + 1;
               end if;

               for col in 0 to G_COLS-1 loop
                  up_addr_v := exp_row * G_COLS + col;
                  lo_addr_v := (exp_row + G_ROWS/2) * G_COLS + col;
                  up_pix_v  := pixel_of(up_addr_v);
                  lo_pix_v  := pixel_of(lo_addr_v);

                  want_v := up_pix_v(2*G_COLOR_BITS + exp_plane) &
                            up_pix_v(G_COLOR_BITS + exp_plane) &
                            up_pix_v(exp_plane) &
                            lo_pix_v(2*G_COLOR_BITS + exp_plane) &
                            lo_pix_v(G_COLOR_BITS + exp_plane) &
                            lo_pix_v(exp_plane);

                  if capture(col) /= want_v then
                     report "tb_hub75: row " & integer'image(exp_row) &
                            " plane " & integer'image(exp_plane) &
                            " column " & integer'image(col) &
                            ": got " & to_hstring(capture(col)) &
                            ", expected " & to_hstring(want_v)
                        severity error;
                     error_cnt <= error_cnt + 1;
                  end if;
               end loop;

               -- Advance the expected sequence: planes inner, rows outer.
               if exp_plane = G_COLOR_BITS-1 then
                  exp_plane <= 0;

                  if exp_row = G_ROWS/2-1 then
                     exp_row <= 0;
                  else
                     exp_row <= exp_row + 1;
                  end if;
               else
                  exp_plane <= exp_plane + 1;
               end if;

               if exp_row = 0 and exp_plane = 0 then
                  frame_time <= now - last_frame;
                  last_frame <= now;
               end if;

               capture_cnt <= 0;
               latch_cnt   <= latch_cnt + 1;
            end if;

         end if;
      end if;
   end process p_monitor;


   ------------------------------------------------------------
   -- Verdict
   ------------------------------------------------------------

   p_verdict : process
   begin
      wait until latch_cnt = C_LATCHES;
      wait until rising_edge(clk);

      report "tb_hub75: " & integer'image(C_LATCHES) & " latches checked over " &
             integer'image(G_FRAMES) & " frames";
      report "tb_hub75: frame time " & time'image(frame_time) & ", refresh " &
             integer'image(1000000000 / (frame_time / 1 ns)) & " Hz";

      if error_cnt = 0 then
         report "tb_hub75: PASSED";
         finish(0);
      else
         report "tb_hub75: FAILED with " & integer'image(error_cnt) & " errors"
            severity error;
         stop(1);
      end if;
   end process p_verdict;


   p_watchdog : process
   begin
      wait for 50 ms;
      report "tb_hub75: timed out after " & integer'image(latch_cnt) & " latches"
         severity error;
      stop(1);
   end process p_watchdog;


   i_hub75 : entity work.hub75
      generic map (
         G_COLS       => G_COLS,
         G_ROWS       => G_ROWS,
         G_COLOR_BITS => G_COLOR_BITS,
         G_CLK_DIV    => G_CLK_DIV,
         G_BASE_TICKS => G_BASE_TICKS
      )
      port map (
         clk_i        => clk,
         rst_i        => rst,
         wr_en_i      => wr_en,
         wr_addr_i    => wr_addr,
         wr_data_i    => wr_data,
         hub75_r1_o   => hub75_r1,
         hub75_g1_o   => hub75_g1,
         hub75_b1_o   => hub75_b1,
         hub75_r2_o   => hub75_r2,
         hub75_g2_o   => hub75_g2,
         hub75_b2_o   => hub75_b2,
         hub75_a_o    => hub75_a,
         hub75_clk_o  => hub75_clk,
         hub75_lat_o  => hub75_lat,
         hub75_oe_n_o => hub75_oe_n
      ); -- i_hub75

end architecture simulation;
