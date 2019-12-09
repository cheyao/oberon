LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

-- Project Oberon, Revised Edition 2013

-- Book copyright (C)2013 Niklaus Wirth and Juerg Gutknecht;
-- software copyright (C)2013 Niklaus Wirth (NW), Juerg Gutknecht (JG), Paul
-- Reed (PR/PDR).

-- Permission to use, copy, modify, and/or distribute this software and its
-- accompanying documentation (the "Software") for any purpose with or
-- without fee is hereby granted, provided that the above copyright notice
-- and this permission notice appear in all copies.

-- THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHORS DISCLAIM ALL WARRANTIES
-- WITH REGARD TO THE SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF
-- MERCHANTABILITY, FITNESS AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
-- AUTHORS BE LIABLE FOR ANY CLAIM, SPECIAL, DIRECT, INDIRECT, OR
-- CONSEQUENTIAL DAMAGES OR ANY DAMAGES OR LIABILITY WHATSOEVER, WHETHER IN
-- AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
-- CONNECTION WITH THE DEALINGS IN OR USE OR PERFORMANCE OF THE SOFTWARE.*/

-- PS/2 mouse PDR 14.10.2013 / 03.09.2015 / 01.10.2015
-- with Microsoft 3rd (scroll) button init magic

-- wheel support and rewritten to VHDL by EMARD 10.05.2019
-- https://isdaman.com/alsos/hardware/mouse/ps2interface.htm

entity mousem is
  generic
  (
    c_x_bits:   integer range 8 to 11 := 8;
    c_y_bits:   integer range 8 to 11 := 8;
    c_y_neg:    integer range 0 to  1 := 0;
    c_z_bits:   integer range 4 to 11 := 4;
    c_z_ena:    integer range 0 to  1 := 1; -- 1:yes wheel, 0:not wheel
    c_hotplug:  integer range 0 to  1 := 1  -- 1:mouse hotplug detection 0:no mouse hotplug (save LUTs)
  );
  port
  (
    clk: in std_logic;
    clk_ena: in std_logic := '1';
    ps2m_reset: in std_logic := '0';
    ps2m_clk, ps2m_dat: inout std_logic;
    update: out std_logic;
    x, dx: out std_logic_vector(c_x_bits-1 downto 0);
    y, dy: out std_logic_vector(c_y_bits-1 downto 0);
    z, dz: out std_logic_vector(c_z_bits-1 downto 0);
    btn: out std_logic_vector(2 downto 0)
  );
end;

architecture syn of mousem is
  signal r_x, x_next, s_dx, r_dx: std_logic_vector(c_x_bits-1 downto 0);
  signal r_y, y_next, s_dy, r_dy: std_logic_vector(c_y_bits-1 downto 0);
  signal r_z, z_next, s_dz, r_dz: std_logic_vector(c_z_bits-1 downto 0);
  signal pad_dx: std_logic_vector(c_x_bits-9 downto 0);
  signal pad_dy: std_logic_vector(c_y_bits-9 downto 0);
  signal pad_dz: std_logic_vector(c_z_bits-5 downto 0);
  signal r_btn, btn_next : std_logic_vector(2 downto 0);
  signal sent, sent_next : std_logic_vector(2 downto 0);
  constant c_rx_bits : integer := 31 + 11*c_z_ena;
  constant c_rx_hotplug_pad : std_logic_vector(c_rx_bits-21 downto 0) := (others => '1');
  constant c_rx_hotplug : std_logic_vector(c_rx_bits-1 downto 0) := "00000000011101010100" & c_rx_hotplug_pad;
  signal rx, rx_next : std_logic_vector(c_rx_bits-1 downto 0);
  signal tx, tx_next : std_logic_vector(9 downto 0);
  signal rx7, rx8 : std_logic_vector(7 downto 0);
  signal count, count_next : std_logic_vector(14 downto 0);
  signal filter : std_logic_vector(5 downto 0);
  signal req : std_logic;
  signal shift, endbit, endcount, done, run : std_logic;
  signal cmd : std_logic_vector(8 downto 0);  --including odd tx parity bit
  signal r_ps2m_reset: std_logic;
begin
  -- 322222222221111111111 (scroll mouse z and rx parity p ignored)
  -- 0987654321098765432109876543210   X, Y = overflow
  -- -------------------------------   s, t = x, y sign bits
  -- yyyyyyyy01pxxxxxxxx01pYXts1MRL0   normal report
  -- p--ack---0Ap--cmd---01111111111   cmd + ack bit (A) & byte
  
  run <= '1' when sent = 7 else '0';
  -- enable reporting, rate 200,100,80
  cmd <= "0" & x"F4" when sent = 0 
    else "0" & x"C8" when sent = 2 -- 200
    else "0" & x"64" when sent = 4 -- 100
    else "1" & x"50" when sent = 6 --  50
    else "1" & x"F3";
  endcount <= '1' when count(14 downto 12) = "111" else '0'; -- more than 11*100uS @25MHz
  shift <= '1' when req = '0' and filter = "100000" else '0'; -- low for 200nS @25MHz
  endbit <= (not rx(0)) when run = '1' else (not rx(rx'high-20));
  done <= endbit and endcount and not req;

  G_yes_hotplug: if c_hotplug = 1 generate
  -- after hot-plug, mouse sends AA 00
  -- when scoped it looks like: "0010101011100000000011"
  -- rx stores it in reverse    "1100000000011101010100"
  -- mouse will be reinitialized when this bit
  -- combination appears in rx: "00000000011101010100" & "1..1"
  -- trailing 1's match initialized (empty) rx.
  -- unwanted reset is unlikely during normal mouse operation.
  process(clk)
  begin
    if rising_edge(clk) then
      if run = '1' then -- normal run after initialization
        if r_ps2m_reset = '0' then
          if rx(rx'high downto rx'length-c_rx_hotplug'length) = c_rx_hotplug then
            r_ps2m_reset <= '1'; -- self-reset when mouse is hot-plugged
          else
            r_ps2m_reset <= ps2m_reset; -- reset by external
          end if;
        end if;
      else -- run = '0' prevent reset during initialization sequence
        r_ps2m_reset <= '0';
      end if; -- if run
    end if;
  end process;
  end generate;

  G_not_hotplug: if not (c_hotplug = 1) generate
  r_ps2m_reset <= ps2m_reset;
  end generate;

  rx7 <= x"00" when rx(7) = '1' else rx(19 downto 12);
  G_yes_pad_x: if C_x_bits > 8 generate
  pad_dx <= (others => rx(5));
  s_dx <= (others => '0') when run = '0'
     else pad_dx & rx7;
  end generate;
  G_not_pad_x: if C_x_bits <= 8 generate
  s_dx <= (others => '0') when run = '0'
     else rx7;
  end generate;
  
  rx8 <= x"00" when rx(8) = '1' else rx(30 downto 23);
  G_yes_pad_y: if C_y_bits > 8 generate
  pad_dy <= (others => rx(6));
  s_dy <= (others => '0') when run = '0'
     else pad_dy & rx8;
  end generate;
  G_not_pad_y: if C_y_bits <= 8 generate
  s_dy <= (others => '0') when run = '0'
     else rx8;
  end generate;

  G_have_wheel: if c_z_ena > 0 generate
  G_yes_pad_z: if C_z_bits > 4 generate
  pad_dz <= (others => rx(37));
  s_dz <= (others => '0') when run = '0'
     else pad_dz & rx(37 downto 34);
  end generate;
  G_not_pad_z: if C_z_bits <= 4 generate
  s_dz <= (others => '0') when run = '0'
     else rx(37 downto 34);
  end generate;
  end generate; -- have wheel

  ps2m_clk <= '0' when req = '1' else 'Z'; -- bidir clk/request
  ps2m_dat <= '0' when tx(0) = '0' else 'Z'; -- bidir data

  count_next <= (others => '0') when (r_ps2m_reset or shift or endcount) = '1' else count + 1;
  sent_next <= (others => '0') when r_ps2m_reset = '1'
        else sent + 1 when (done and not run) = '1'
        else sent;
  tx_next <= (others => '1') when (r_ps2m_reset or run) = '1'
        else cmd & "0" when req = '1'
        else "1" & tx(tx'high downto 1) when shift = '1'
        else tx;
  rx_next <= (others => '1') when (r_ps2m_reset or done) = '1'
        else ps2m_dat & rx(rx'high downto 1) when (shift and not endbit) = '1'
        else rx;
  x_next <= (others => '0') when run = '0'
        else r_x + s_dx when done = '1'
        else r_x;
  G_not_invert_y: if C_y_neg = 0 generate
  y_next <= (others => '0') when run = '0'
        else r_y - s_dy when done = '1' -- PS2 mouse sends negative dy
        else r_y;
  end generate;
  G_yes_invert_y: if C_y_neg = 1 generate
  y_next <= (others => '0') when run = '0'
        else r_y + s_dy when done = '1' -- PS2 mouse sends negative dy
        else r_y;
  end generate;
  z_next <= (others => '0') when run = '0'
        else r_z - s_dz when done = '1'
        else r_z;
  btn_next <= (others => '0') when run = '0'
        else rx(3 downto 1) when done = '1'
        else r_btn;
  process(clk)
  begin
    if rising_edge(clk) then
      if clk_ena = '1' then
        filter <= filter(filter'high-1 downto 0) & ps2m_clk;
        count <= count_next;
        req <= (not r_ps2m_reset) and (not run) and (req xor endcount);
        sent <= sent_next;
        tx <= tx_next;
        rx <= rx_next;
        r_x <= x_next;
        r_y <= y_next;
        r_z <= z_next;
        r_btn <= btn_next;
        r_dx <= s_dx;
        r_dy <= s_dy;
        r_dz <= s_dz;
        update <= done;
      else -- clk_ena = '0'
        update <= '0';
      end if; -- clk_ena
    end if; -- rising_edge
  end process;  
  x <= r_x;
  y <= r_y;
  z <= r_z;
  btn <= r_btn;
  dx <= r_dx;
  dy <= r_dy;
  dz <= r_dz;
end syn;
