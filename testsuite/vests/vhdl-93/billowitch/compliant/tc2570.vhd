
-- Copyright (C) 2001 Bill Billowitch.

-- Some of the work to develop this test suite was done with Air Force
-- support.  The Air Force and Bill Billowitch assume no
-- responsibilities for this software.

-- This file is part of VESTs (Vhdl tESTs).

-- VESTs is free software; you can redistribute it and/or modify it
-- under the terms of the GNU General Public License as published by the
-- Free Software Foundation; either version 2 of the License, or (at
-- your option) any later version. 

-- VESTs is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
-- for more details. 

-- You should have received a copy of the GNU General Public License
-- along with VESTs; if not, write to the Free Software Foundation,
-- Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA 

-- ---------------------------------------------------------------------
--
-- $Id: tc2570.vhd,v 1.2 2001-10-26 16:29:48 paw Exp $
-- $Revision: 1.2 $
--
-- ---------------------------------------------------------------------

ENTITY c07s05b00x00p16n02i02570ent IS
END c07s05b00x00p16n02i02570ent;

ARCHITECTURE c07s05b00x00p16n02i02570arch OF c07s05b00x00p16n02i02570ent IS

BEGIN
  TESTING: PROCESS
  BEGIN
    assert NOT(2.12E6 = (1.06E3*2.0E3))
      report "***PASSED TEST: c07s05b00x00p16n02i02570"
      severity NOTE;
    assert ( 2.12E6 = (1.06E3*2.0E3) ) 
      report "***FAILED TEST: c07s05b00x00p16n02i02570 - The values of the operands and the result lie within the range of the floating point type."
      severity ERROR;
    wait;
  END PROCESS TESTING;

END c07s05b00x00p16n02i02570arch;
