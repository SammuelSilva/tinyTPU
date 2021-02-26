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
        MATRIX_WIDTH    : natural := 14;
        MATRIX_HALF     : natural := ((14-1)/NUMBER_OF_MULT)
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            WEIGHT_DATA0     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_DATA1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
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
    
    constant MATRIX_WIDTH   : natural := 14;
    constant MATRIX_HALF             : natural := ((14-1)/NUMBER_OF_MULT);

    signal CLK, RESET       : std_logic;
    signal ENABLE           : std_logic;
    
    signal WEIGHT_DATA0      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_DATA1      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
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

    constant INPUT_MATRIX_V   : INTEGER_ARRAY_2D_TYPE :=
        (
            (-1 , 99 , -1 ,  -1 ,113 , 21 , 32 , 79 , 93 , 64 ,107 ,  1 ,110 ,107),
            (127 , 20 , 26 ,120 , 82 ,108 , 11 , 18 , 79 ,  8 , 78 ,108 ,  4 , 18),
            ( 92 , 96 ,114 , 27 ,  3 , -1 , 82 ,  0 , 96 ,  8 ,108 , 52 , 45 , 14),
           (  32 , 45 , 38 ,110 , 12 , 32 , -1 , 19 , 50 , 28 , 68 , 12 , 24 ,  0),
           (  68 , 26 ,103 , 78 , 20 , 10 , -1 , 30 , 96 , 96 ,108 ,111 , 54 , -1),
           ( 124 , 89 , 57 , 11 , 19 , 77 , 17 ,103 ,117 , 32 ,108 , 80 ,110 , 14),
           (  88 , 38 , -1 , 73 , 54 , -1 , 90 , -1 , 95 , 89 , 38 , -1 , 59 , 34),
           (   9 ,  0 , 29 ,120 , 47 , 42 , 20 , 67 ,110 , 96 ,120 ,110 , 70 , 74),
           (  28 ,  3 , 78 ,110 ,112 , 70 ,124 ,102 , 99 , 63 , 94 , 10 ,  1 ,105),
           ( 115 ,118 , 39 , 69 ,105 ,  0 ,104 , -1 ,  0 ,111 ,123 , 18 , 95 , 63),
           (  12 , 81 , 63 , 31 , 20 ,  0 , 84 ,110 ,  1 , 98 ,  5 , 57 , 69 , 37),
           (  42 , 98 , 54 , 25 ,118 , 40 , -1 , 48 , -1 , 51 ,105 , 64 ,  5 , -1),
           (  23 , 47 ,109 ,125 ,106 , 81 , 23 ,103 , 37 , 58 , 38 , 71 , 50 , 74),
           (   0 , 23 , -1 , 83 , 50 , 84 , 87 ,106 ,115 ,  4 , 38 , 45 ,112 , 69)
        );

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

        constant RESULT_MATRIX_V : INTEGER_ARRAY_2D_TYPE :=
        (
            (52019, 43099, 60834, 57478, 32328, 57027, 30267, 57750, 21852, 30104, 43115, 32725, 47378, 32732),
            (34251, 28702, 44990, 40372, 45592, 45277, 34236, 52078, 24434, 34594, 43367, 41927, 41013, 33039),
            (42518, 22987, 48031, 46041, 45535, 40833, 25411, 61533, 13399, 28079, 36239, 29642, 40320, 25716),
            (19302, 24005, 29323, 20367, 24096, 22002, 20606, 29375, 16266, 22848, 27658, 24626, 22265, 20643),
            (37770, 32342, 50686, 40520, 35552, 36300, 30902, 59027, 22815, 36156, 42250, 35362, 49030, 33378),
            (49487, 33944, 68373, 50667, 53692, 58952, 38973, 71381, 25637, 33909, 45971, 43490, 62862, 47222),
            (33700, 36837, 32921, 34540, 37964, 34787, 20561, 53284, 20009, 31670, 43289, 26322, 29546, 21885),
            (41327, 44703, 62114, 51322, 34731, 49449, 36290, 57917, 32050, 46914, 45606, 38311, 56943, 36550),
            (58334, 45730, 64102, 50501, 44650, 57091, 37398, 64552, 38582, 48450, 43032, 45988, 50774, 36563),
            (56504, 48283, 51538, 66521, 42492, 45404, 36678, 87943, 25163, 44035, 65836, 43414, 42104, 35078),
            (42855, 34109, 48469, 39404, 17674, 39891, 34573, 56647, 25998, 34009, 36364, 34125, 39650, 36920),
            (39931, 25767, 39746, 42574, 24352, 37302, 29371, 47585, 17731, 18185, 36128, 33315, 32378, 33129),
            (53355, 43738, 66717, 48129, 28019, 54613, 45949, 62417, 35263, 48278, 45657, 54401, 49045, 41257),
            (40577, 40478, 63311, 44602, 35861, 60390, 29937, 50212, 30552, 40138, 29805, 35865, 50950, 31996)
                 
        );

    constant WEIGHT_MATRIX_V : INTEGER_ARRAY_2D_TYPE :=
    (
        (55 , -1 ,   0 , 23 ,123 ,0 , 45 ,123 , 4 , 36 ,123 , 95 , 46 , 44),
        (81 , 57 , 81 ,105 , 59 ,118 ,104 , 90 , 1 , -1 ,115 , 52 , 11 ,102),
       ( 93 ,   0 , 96 , 20 , 11 , 17 , 42 ,100 ,20 , 62 ,   0 , 70 , 43 , 13),
        ( 6 , 98 , 44 , 16 , 22 , 17 , 62 , 22 ,65 ,111 , 93 ,108 , 15 , 29),
      ( 102 , 62 , 38 , 85 , -1 , 92 , -1 , 47 ,18 , -1 , 41 , 79 , 19 ,   0),
       (   0 , 28 , 78 ,  6 , 82 , 91 , 71 , 70 ,73 , 45 ,0 ,0 , 24 , 80),
       ( 72 , 44 , 44 , 90 , 77 , 82 ,  0 ,126 ,49 , 62 ,  7 , -1 , 39 , 12),
       ( 89 , 38 ,114 ,  6 , 12 , 76 , 72 , 15 ,78 , 23 , 14 ,113 ,127 ,121),
       ( 38 , 45 , 80 ,  9 ,126 ,119 , -1 ,  5 ,13 ,  6 , 17 , -1 , 74 , 23),
       ( 39 ,106 , 18 , 15 , 16 , -1 , 64 ,124 ,73 , 67 ,120 ,0 , 31 , 89),
       ( 38 , 18 , 59 ,100 , 76 ,  4 , -1 , 69 ,14 , 11 , 31 ,  2 , 83 , 27),
      (  35 , -1 , 78 ,122 , -1 , 91 , 66 , 72 ,12 , 48 , 38 , 41 ,106 , 55),
      (  36 , 81 ,111 , 84 ,0 , 63 , -1 ,122 ,17 , 78 , 33 , 43 , 90 , -1),
      (  86 , 35 , 88 ,114 ,  7 , 56 , 86 , 73 ,12 ,104 , 91 , 48 , 44 ,  4)
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
    signal FlAG        : std_logic;
begin
    DUT_i : DUT
    generic map(
        MATRIX_WIDTH => MATRIX_WIDTH,
        MATRIX_HALF  => MATRIX_HALF

    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
        WEIGHT_DATA0    => WEIGHT_DATA0,
        WEIGHT_DATA1    => WEIGHT_DATA1,
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
            FlAG <= '1';
            RESET <= '0';
            ENABLE <= '0';
            WEIGHT_DATA0 <= (others => (others => '0'));
            WEIGHT_DATA1 <= (others => (others => '0'));
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

            for k in 0 to (MATRIX_WIDTH-1)/2 loop
                WEIGHT_ADDRESS <= std_logic_vector(to_unsigned(k, BYTE_WIDTH));
                for i in 0 to MATRIX_WIDTH-1 loop
                    WEIGHT_DATA0(i) <= std_logic_vector(to_signed(MATRIX((k*2), i), BYTE_WIDTH));
                    if (k*2)+1 <= MATRIX_WIDTH-1 then
                        WEIGHT_DATA1(i) <= std_logic_vector(to_signed(MATRIX((k*2)+1, i), BYTE_WIDTH));
                    end if;
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
       -- CURRENT_SIGN <= '1';
        --CURRENT_INPUT <= INPUT_MATRIX_IV;
        --CURRENT_RESULT <= RESULT_MATRIX_IV;
        --LOAD_WEIGHTS(WEIGHT_MATRIX_IV, '1');
        --START_TEST;
        CURRENT_SIGN <= '1';
        CURRENT_INPUT <= INPUT_MATRIX_V;
        CURRENT_RESULT <= RESULT_MATRIX_V;
        LOAD_WEIGHTS(WEIGHT_MATRIX_V, '1');
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

    PROCESS_INPUT7:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(7) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 7), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(7) <= (others => '0');
    end process;

    PROCESS_INPUT8:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(8) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 8), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(8) <= (others => '0');
    end process;

    PROCESS_INPUT9:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(9) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 9), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(9) <= (others => '0');
    end process;

    PROCESS_INPUT10:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(10) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 10), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(10) <= (others => '0');
    end process;

    PROCESS_INPUT11:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(11) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 11), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(11) <= (others => '0');
    end process;
    
    PROCESS_INPUT12:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(12) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 12), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(12) <= (others => '0');
    end process;

    PROCESS_INPUT13:
    process is
    begin
        wait until START = true;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        wait until '1'=CLK and CLK'event;
        for i in 0 to MATRIX_WIDTH-1 loop
            SYSTOLIC_DATA(13) <= std_logic_vector(to_signed(CURRENT_INPUT(i, 13), BYTE_WIDTH));
            wait until '1'=CLK and CLK'event;
        end loop;
        SYSTOLIC_DATA(13) <= (others => '0');
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