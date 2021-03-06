
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
-- $Id: tc2902.vhd,v 1.2 2001-10-26 16:29:50 paw Exp $
-- $Revision: 1.2 $
--
-- ---------------------------------------------------------------------

ENTITY c02s01b01x01p02n02i02902ent IS
END c02s01b01x01p02n02i02902ent;

ARCHITECTURE c02s01b01x01p02n02i02902arch OF c02s01b01x01p02n02i02902ent IS
  type    t1 is (one,two,three);
  signal    s1 : t1;
  constant    c1 : integer:=65;

  procedure proc1(constant cc1:in integer;variable vv1:in real;signal ss1:in t1) is
  begin
    assert (cc1=65)
      report "Constants of mode in for procedures are not copied properly"
      severity failure;
    assert (vv1=43.1)
      report "Variables of mode in for procedures are not copied properly"
      severity failure;
    assert (ss1=two)
      report "Signals of mode in for procedures are not copied properly"
      severity failure;
    assert NOT( cc1=65 and vv1=43.1 and ss1=two )
      report "***PASSED TEST: c02s01b01x01p02n02i02902"
      severity NOTE;
    assert ( cc1=65 and vv1=43.1 and ss1=two )
      report "***FAILED TEST: c02s01b01x01p02n02i02902 - Values of actual parameters of mode in are not copied into their associated formal parameter."
      severity ERROR;
  end proc1;
BEGIN
  TESTING: PROCESS
    variable v1:real;
  BEGIN
    s1<=two;
    v1:=43.1;
    wait for 5 ns;
    proc1(c1,v1,s1);
    wait;
  END PROCESS TESTING;

END c02s01b01x01p02n02i02902arch;
