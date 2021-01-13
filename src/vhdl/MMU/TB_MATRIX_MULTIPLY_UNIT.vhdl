-- Copyright 2018 Jonas Fuhrmann. All rights reserved.
--
-- This project is dual licensed under GNU General Public License version 3
-- and a commercial license available on request.
---------------------------------------------------------------------------
-- For non commercial use only:
-- This file is part of tinyTPU.
-- 
-- tinyTPU is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- tinyTPU is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with tinyTPU. If not, see <http://www.gnu.org/licenses/>.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity TB_MATRIX_MULTIPLY_UNIT is
end entity TB_MATRIX_MULTIPLY_UNIT;

architecture BEH of TB_MATRIX_MULTIPLY_UNIT is
    component DUT is
        generic(
        MATRIX_WIDTH    : natural := 14
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            WEIGHT_DATA     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_SIGNED   : in  std_logic;
            SYSTOLIC_DATA   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            SYSTOLIC_SIGNED : in  std_logic;
            
            ACTIVATE_WEIGHT : in  std_logic; -- Activates the loaded weights sequentially
            LOAD_WEIGHT     : in  std_logic; -- Preloads one column of weights with WEIGHT_DATA
            WEIGHT_ADDRESS  : in  BYTE_TYPE; -- Addresses up to 256 columns of preweights
            
            RESULT_DATA     : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component DUT;
    for all : DUT use entity WORK.MATRIX_MULTIPLY_UNIT(BEH);
    
    constant MATRIX_WIDTH   : natural := 7;
    
    signal CLK, RESET       : std_logic;
    signal ENABLE           : std_logic;
    
    signal WEIGHT_DATA      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_SIGNED    : std_logic;
    signal SYSTOLIC_DATA    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal SYSTOLIC_SIGNED  : std_logic;
    
    signal ACTIVATE_WEIGHT  : std_logic;
    signal LOAD_WEIGHT      : std_logic;
    signal WEIGHT_ADDRESS   : BYTE_TYPE;
    
    signal RESULT_DATA      : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- for clock gen
    constant clock_period   : time := 10 ns;
    signal stop_the_clock   : boolean := false;
    
    signal START            : boolean;
    signal EVALUATE         : boolean;
    
    -- Unsigned
    -- Tested input data

    constant INPUT_MATRIX_IV  : INTEGER_ARRAY_2D_TYPE :=
        (
            (6,41,110,96,18,101,65),
            (7,40,91,28,112,31,71),
            (10,13,67,3,68,38,99),
            (67,73,-1,11,88,102,4),
            (103,85,6,43,21,30,35),
            (2,36,4,9,63,0,11),
            (95,56,92,16,49,114,18)
        );
        
    constant INPUT_MATRIX_I   : INTEGER_ARRAY_2D_TYPE :=
        (
            ( 40,  76,  19, 192, 0),
            (  3,  84,  12,   8, 1),
            ( 54,  18, 255, 120, 0),
            ( 30,  84, 122,   2, 1),
            (  0,   1,   1,   1, 1)
        );

    constant INPUT_MATRIX_II   : INTEGER_ARRAY_2D_TYPE :=
        (
            ( 255, 0, 12, 18, 22  ),
            (   3, 1,  0, 2, 45  ),
            (  0,  0, 122, 14, 13),
            ( 23,  56, 89,   78, 153),
            (  0,   32,   3,   35, 0)
        );

    constant INPUT_MATRIX_III   : INTEGER_ARRAY_2D_TYPE :=
    (
        ( 0, 0, 0, 0, 1  ),
        (   1, 0,  2, 0, 0  ),
        ( 25,  0, 0, 1, 1),
        ( 23,  2, 5,   0, 0),
        (  0,   0,   0,   1, 1)
    );
    
    
    -- Tested weight data
    constant WEIGHT_MATRIX  : INTEGER_ARRAY_2D_TYPE :=
        (
            ( 13,  0, 178,   9, 0),
            ( 84,  0, 245,  18, 1),
            (255,  0,  14,   3, 1),
            ( 98,  0,  78,  29, 1),
            (  1,  0,   1,   1, 1)

        );

    constant WEIGHT_MATRIX_IV : INTEGER_ARRAY_2D_TYPE :=
        (
            (-70,20,89,-62,94,-39,22),
            (-114,88,-64,-13,34,111,-116),
            (-16,88,115,65,3,-108,47),
            (62,-116,-63,52,125,50,-21),
            (-102,94,66,14,-34,83,-1),
            (-97,120,96,47,4,-77,65),
            (-96,-100,-51,-124,-10,-18,50)
        );
    -- Result of matrix multiply
    constant RESULT_MATRIX_I  : INTEGER_ARRAY_2D_TYPE :=
        (
            (30565,  0, 40982, 7353, 287),
            (10940,  0, 21907, 1808, 105),
            (78999,  0, 26952, 5055, 393),
            (38753,  0, 27785, 2207, 209),
            (  438,  0,   338,   51,   4)
        );

    constant RESULT_MATRIX_II  : INTEGER_ARRAY_2D_TYPE :=
        (
            (8161,  0, 46984, 2875, 52),
            (364,  0, 980, 148, 48),
            (32495,  0, 2813, 785, 149),
            (35495,  0, 25297, 3897, 376),
            (  6883,  0,   10612,   1600,   70)
        );
        
    constant RESULT_MATRIX_III  : INTEGER_ARRAY_2D_TYPE :=
        (
            (1,  0, 1, 1, 1),
            (523,  0, 206, 15, 2),
            (424,  0, 4529, 255, 2),
            (1742,  0, 4654, 258, 7),
            (  99,  0,   79,   30,   2)
        );

    constant RESULT_MATRIX_IV : INTEGER_ARRAY_2D_TYPE :=
        (
            (-18775,  9584, 12081,  8176, 13430, -10216,  8327),
            (-26017, 15568, 13511,   638,  1397,   1370,  4656),
            (-23194,  7944, 10661, -5816, -1192,  -5097,  9150),
            (-31568, 26512, 15879,   934,  7528,   5526,  -530),
            (-22742,  7154,  4189, -7501, 17021,   5723, -4536),
            (-11232,  7338,  1364,  -346,   297,   8967, -3646),
            (-31298, 29554, 27703,  4006, 11720, -11660,  7843)          
        );
    -- Signed
    -- Tested input data
    constant INPUT_MATRIX_SIGNED    : INTEGER_ARRAY_2D_TYPE :=
        (
            ( 74,  91,  64,  10, 22),
            (  5,  28,  26,   9, 53),
            ( 56,   9,  72, 127,  0),
            ( 94,  26,  92,   8,  1),
            (  2,   5,   4,   8,  7)
        );
    
    -- Tested weight data
    constant WEIGHT_MATRIX_SIGNED   : INTEGER_ARRAY_2D_TYPE :=
        (
            ( -13,  89,  92,   9, 0),
            ( -84, 104,  86,  18, 1),
            (-128,  73,  14,   3, 2),
            ( -98, 127,  78,  29, 1),
            (  -3,   0,   1,   2, 1)
        );
    
    -- Result of matrix multiply
    constant RESULT_MATRIX_SIGNED   : INTEGER_ARRAY_2D_TYPE :=
        (
            (-17844, 21992, 16332, 2830, 251),
            (- 6786,  6398,  3987,  994, 142),
            (-23146, 27305, 16840, 4565, 280),
            (-15969, 18802, 12797, 1824, 219),
            ( -1763,  2006,  1301,  366,  28)
        );
        
    signal CURRENT_INPUT    : INTEGER_ARRAY_2D_TYPE(0 to MATRIX_WIDTH-1, 0 to MATRIX_WIDTH-1);
    signal CURRENT_RESULT   : INTEGER_ARRAY_2D_TYPE(0 to MATRIX_WIDTH-1, 0 to MATRIX_WIDTH-1);
    signal CURRENT_SIGN     : std_logic;
    
    signal QUIT_CLOCK0 : boolean;
    signal QUIT_CLOCK1 : boolean;
begin
    DUT_i : DUT
    generic map(
        MATRIX_WIDTH => MATRIX_WIDTH
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
        WEIGHT_DATA     => WEIGHT_DATA,
        WEIGHT_SIGNED   => WEIGHT_SIGNED,
        SYSTOLIC_DATA   => SYSTOLIC_DATA,
        SYSTOLIC_SIGNED => SYSTOLIC_SIGNED,
        ACTIVATE_WEIGHT => ACTIVATE_WEIGHT,
        LOAD_WEIGHT     => LOAD_WEIGHT,
        WEIGHT_ADDRESS  => WEIGHT_ADDRESS,
        RESULT_DATA     => RESULT_DATA
    );
    
    STIMULUS:
    process is
        procedure LOAD_WEIGHTS(
            MATRIX : in INTEGER_ARRAY_2D_TYPE;
            SIGNED_NOT_UNSIGNED : in std_logic
        ) is
        begin
            START <= false;
            RESET <= '0';
            ENABLE <= '0';
            WEIGHT_DATA <= (others => (others => '0'));
            ACTIVATE_WEIGHT <= '0';
            LOAD_WEIGHT <= '0';
            WEIGHT_ADDRESS <= (others => '0');
            WEIGHT_SIGNED <= '0';
            wait until '1'=CLK and CLK'event;

            -- RESET
            RESET <= '1';
            wait until '1'=CLK and CLk'event;
            RESET <= '0';
            WEIGHT_SIGNED <= SIGNED_NOT_UNSIGNED;

            for k in 0 to MATRIX_WIDTH-1 loop

                WEIGHT_ADDRESS <= std_logic_vector(to_unsigned(k, BYTE_WIDTH));
                for i in 0 to MATRIX_WIDTH-1 loop
                    WEIGHT_DATA(i) <= std_logic_vector(to_signed(MATRIX(k, i), BYTE_WIDTH));
                end loop;
    
                LOAD_WEIGHT <= '1';
                wait until '1'=CLK and CLK'event;

            end loop;
            --
            LOAD_WEIGHT <= '0';
            WEIGHT_SIGNED <= '0';
            ACTIVATE_WEIGHT <= '1';
            ENABLE <= '1';
            --
        end procedure LOAD_WEIGHTS;

        procedure START_TEST 
        is
        begin
            START <= true;
            wait until '1'=CLK and CLK'event;
            START <= false;
            ACTIVATE_WEIGHT <= '0';

            for i in 0 to 3*MATRIX_WIDTH-1 loop
                wait until '1'=CLK and CLK'event;
            end loop;
        end procedure START_TEST;
    begin
        CURRENT_SIGN <= '1';
        CURRENT_INPUT <= INPUT_MATRIX_IV;
        CURRENT_RESULT <= RESULT_MATRIX_IV;
        LOAD_WEIGHTS(WEIGHT_MATRIX_IV, '1');
        START_TEST;

     -- QUIT_CLOCK0 <= false;
     -- CURRENT_SIGN <= '0';
     -- CURRENT_INPUT <= INPUT_MATRIX_I;
     -- CURRENT_RESULT <= RESULT_MATRIX_I;
     -- LOAD_WEIGHTS(WEIGHT_MATRIX,  '0');
     -- START_TEST;
     -- CURRENT_SIGN <= '0';
     -- CURRENT_INPUT <= INPUT_MATRIX_II;
     -- CURRENT_RESULT <= RESULT_MATRIX_II;
     -- START_TEST;
     -- CURRENT_SIGN <= '0';
     -- CURRENT_INPUT <= INPUT_MATRIX_III;
     -- CURRENT_RESULT <= RESULT_MATRIX_III;
     -- START_TEST;

     -- CURRENT_SIGN <= '1';
     -- CURRENT_INPUT <= INPUT_MATRIX_SIGNED;
     -- CURRENT_RESULT <= RESULT_MATRIX_SIGNED;
     -- LOAD_WEIGHTS(WEIGHT_MATRIX_SIGNED, '1');
     -- START_TEST;

        QUIT_CLOCK0 <= true;
        wait;
    end process STIMULUS;
    
    PROCESS_INPUT0:
    process is
    begin
        wait until START = true;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(0) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 0), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(0) <= (others => '0');
        wait until '1'=CLK and CLK'event;
    end process;
    
    PROCESS_INPUT1:
    process is
    begin
        EVALUATE <= false;
        wait until START = true;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(1) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 1), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(1) <= (others => '0');
        EVALUATE <= true;
        wait until '1'=CLK and CLK'event;
        EVALUATE <= false;
    end process;
    
    PROCESS_INPUT2:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(2) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 2), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(2) <= (others => '0');
    end process;
    
    PROCESS_INPUT3:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(3) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 3), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(3) <= (others => '0');
    end process;

    PROCESS_INPUT4:
    process is
    begin
        SYSTOLIC_SIGNED <= '0';
        wait until START = true;
        SYSTOLIC_SIGNED <= CURRENT_SIGN;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(4) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 4), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(4) <= (others => '0');
    end process;

    PROCESS_INPUT5:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(5) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 5), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(5) <= (others => '0');
    end process;

    PROCESS_INPUT6:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(6) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 6), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(6) <= (others => '0');
    end process;
    
    EVALUATE_RESULT:
    process is
    begin
        QUIT_CLOCK1 <= false;
        wait until EVALUATE = true;
        for i in 0 to MATRIX_WIDTH-1 loop

            if RESULT_DATA(0) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 0), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 0" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;
        
            if RESULT_DATA(1) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 1), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 1" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;
        
            if RESULT_DATA(2) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 2), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 2" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;
        
            if RESULT_DATA(3) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 3), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 3" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;

            if RESULT_DATA(4) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 4), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 4" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;

            if RESULT_DATA(5) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 5), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 5" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;

            if RESULT_DATA(6) /= std_logic_vector(to_signed(CURRENT_RESULT(i, 6), 4*BYTE_WIDTH)) then
                report "Test failed! Result should be 6" severity WARNING;
                QUIT_CLOCK1 <= false;
                wait;
            end if;

        end loop;
        report "Test was successful!" severity NOTE;
    end process EVALUATE_RESULT;
        
        
    stop_the_clock <= QUIT_CLOCK0 or QUIT_CLOCK1;
    
    CLOCK_GEN: 
    process
    begin
        while not stop_the_clock loop
          CLK <= '0', '1' after clock_period / 2;
          wait for clock_period;
        end loop;
        wait;
    end process CLOCK_GEN;
    
end architecture BEH;