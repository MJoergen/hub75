-- sdp_ram - Simple dual-port RAM: one write port, one read port.
--
-- FUNCTION
--   One memory array, one clock, two independent addresses: wr_addr_i writes
--   and rd_addr_i reads. The read is registered with a 1-cycle latency and
--   gated by rd_en_i, so rd_data_o holds its previous value while
--   rd_en_i = '0'.
--
-- WHY NOT TWO READ PORTS
--   The frame buffer needs to read two pixels at once -- one from each half of
--   the panel -- and to be written by whatever is generating the picture. That
--   is three addresses, which does not fit one RAM primitive. Rather than let
--   the synthesiser duplicate the array behind our back, frame_buffer.vhd
--   splits the picture into two instances of this module, one per half, and
--   each instance then needs only the one read and the one write it has.
--
-- READ/WRITE ORDERING
--   Read-first. A read and a write of the same address in the same cycle
--   returns the OLD contents; the new value is visible from the next read.
--   That falls out of both happening in one process against a signal: the read
--   sees the pre-update value.
--
-- RESET
--   None. The array powers up zeroed and is never cleared afterwards; a driver
--   that cares writes every pixel before enabling the panel.

library ieee;
   use ieee.std_logic_1164.all;
   use ieee.numeric_std_unsigned.all;

entity sdp_ram is
   generic (
      G_RAM_STYLE : string  := "block";
      G_ADDR_SIZE : natural := 8;
      G_DATA_SIZE : natural := 18
   );
   port (
      clk_i     : in  std_logic;
      wr_en_i   : in  std_logic;
      wr_addr_i : in  std_logic_vector(G_ADDR_SIZE-1 downto 0);
      wr_data_i : in  std_logic_vector(G_DATA_SIZE-1 downto 0);
      rd_en_i   : in  std_logic;
      rd_addr_i : in  std_logic_vector(G_ADDR_SIZE-1 downto 0);
      rd_data_o : out std_logic_vector(G_DATA_SIZE-1 downto 0)
   );
end entity sdp_ram;

architecture synthesis of sdp_ram is

   type t_mem is array (natural range 0 to 2**G_ADDR_SIZE-1) of
           std_logic_vector(G_DATA_SIZE-1 downto 0);

   signal mem : t_mem := (others => (others => '0'));

   attribute ram_style : string;
   attribute ram_style of mem : signal is G_RAM_STYLE;

begin

   -- One process, one driver, no shared variable: the write and the read share
   -- the array so that the tools infer a single block RAM rather than two.
   p_mem : process (clk_i)
   begin
      if rising_edge(clk_i) then
         if wr_en_i = '1' then
            mem(to_integer(wr_addr_i)) <= wr_data_i;
         end if;

         -- Reads the signal, not the just-assigned value, hence read-first.
         if rd_en_i = '1' then
            rd_data_o <= mem(to_integer(rd_addr_i));
         end if;
      end if;
   end process p_mem;

end architecture synthesis;
