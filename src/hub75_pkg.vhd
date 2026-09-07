-- hub75_pkg - Shared helpers for the HUB75 panel driver.
--
-- The only thing here is log2_ceil, which the entities use to size their
-- address ports from the panel geometry generics. It has to live in a package
-- because a port width is elaborated before the architecture's declarative
-- part exists, so the function cannot be local to the entity that needs it.

library ieee;
   use ieee.std_logic_1164.all;

package hub75_pkg is

   -- Number of bits needed to address arg distinct items, i.e. ceil(log2(arg)).
   -- log2_ceil(1) is 1 rather than 0, so that a degenerate single-entry
   -- dimension still yields a legal one-bit port rather than a null range.
   function log2_ceil (arg : positive) return positive;

end package hub75_pkg;

package body hub75_pkg is

   function log2_ceil (arg : positive) return positive is
      variable res_v : positive := 1;
   begin
      while 2 ** res_v < arg loop
         res_v := res_v + 1;
      end loop;
      return res_v;
   end function log2_ceil;

end package body hub75_pkg;
