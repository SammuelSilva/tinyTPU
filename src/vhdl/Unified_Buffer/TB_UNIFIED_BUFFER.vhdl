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
    
entity TB_UNIFIED_BUFFER is
end entity TB_UNIFIED_BUFFER;

architecture BEH of TB_UNIFIED_BUFFER is
    component DUT is
        generic(
        MATRIX_WIDTH    : natural := 14;
        -- How many tiles can be saved
        TILE_WIDTH      : natural := 4096 --!< The depth of the buffer.
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            -- Master port - Possui maior importancia que outras portas
            MASTER_ADDRESS      : in  BUFFER_ADDRESS_TYPE; --!< Endereço do Mestre(host), Possui maior importancia que outros Endereçamentos.
            MASTER_EN           : in  std_logic; --!< Mestre(host) enable, Possui maior importancia que outras Ativações.
            MASTER_WRITE_EN     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Mestre(host) write enable, Possui maior importancia que outras ativações de escrita.
            MASTER_WRITE_PORT   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Mestre(host) write port, Possui maior importancia que outras Portas de Escrita.
            MASTER_READ_PORT    : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Mestre(host) read port, Possui maior importancia que outras Portas de Leitura.

            -- Port0, so é possivel a realização de leitura
            ADDRESS0        : in  BUFFER_ADDRESS_TYPE; --!< Endereço da porta 0.
            EN0             : in  std_logic; --!< Ativação da porta 0.
            READ_PORT0      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Leitura da porta 0.

            -- Port1, só é possivel a realização de escrita.
            ADDRESS1        : in  BUFFER_ADDRESS_TYPE; --!< Endereço da porta 1.
            EN1             : in  std_logic; --!< Ativação da porta 1.
            WRITE_EN1       : in  std_logic; --!< Ativação de escrita da porta 1.
            WRITE_PORT1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) --!< Escrita da porta 1.
        );
    end component DUT;
    for all : DUT use entity WORK.UNIFIED_BUFFER(BEH);
    
    constant MATRIX_WIDTH    : natural := 14;
    constant TILE_WIDTH      : natural := 4096;
    
    signal CLK               : std_logic;
    signal RESET             : std_logic;
    signal ENABLE            : std_logic;

    signal MASTER_ADDRESS    : BUFFER_ADDRESS_TYPE;  
    signal MASTER_EN         : std_logic;       
    signal MASTER_WRITE_EN   : std_logic_vector(0 to MATRIX_WIDTH-1);   
    signal MASTER_WRITE_PORT : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);      
    signal MASTER_READ_PORT  : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); 

    signal ADDRESS0          : BUFFER_ADDRESS_TYPE;
    signal EN0               : std_logic;
    signal READ_PORT0        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    signal ADDRESS1          : BUFFER_ADDRESS_TYPE;
    signal EN1               : std_logic;
    signal WRITE_EN1         : std_logic;
    signal WRITE_PORT1       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- for clock gen
    constant clock_period    : time := 10 ns;
    signal stop_the_clock    : boolean;
begin

    DUT_i : DUT
    generic map(
        MATRIX_WIDTH      => MATRIX_WIDTH,
        TILE_WIDTH        => TILE_WIDTH
    )
    port map(
        CLK               => CLK,
        RESET             => RESET,
        ENABLE            => ENABLE,

        MASTER_ADDRESS    => MASTER_ADDRESS,  
        MASTER_EN         => MASTER_EN,       
        MASTER_WRITE_EN   => MASTER_WRITE_EN, 
        MASTER_WRITE_PORT => MASTER_WRITE_PORT,      
        MASTER_READ_PORT  => MASTER_READ_PORT, 

        ADDRESS0          => ADDRESS0,
        EN0               => EN0,
        READ_PORT0        => READ_PORT0,

        ADDRESS1          => ADDRESS1,        
        EN1               => EN1,
        WRITE_EN1         => WRITE_EN1,
        WRITE_PORT1       => WRITE_PORT1
    );
    
    STIMULUS:
    process is
    begin
        ENABLE <= '0';
        RESET <= '0';

        ADDRESS0 <= (others => '0');
        ADDRESS1 <= (others => '0');
        EN0 <= '0';
        EN1 <= '0';
        WRITE_EN1 <= '0';
        WRITE_PORT1 <= (others => (others => '0'));
        
        wait until '1'= CLK and CLK'event;
        RESET <= '1';
        wait until '1'= CLK and CLK'event;
        RESET <= '0';

        -- TEST write to memory through MASTER

        MASTER_EN <= '1';
        for i in 0 to 5 loop
            MASTER_ADDRESS <= std_logic_vector(to_unsigned(i, 3*BYTE_WIDTH));
            MASTER_WRITE_EN <= (std_logic_vector(to_unsigned(i, MATRIX_WIDTH)));
            for j in 0 to MATRIX_WIDTH-1 loop
                MASTER_WRITE_PORT(j) <= std_logic_vector(to_unsigned(j*(i+1), BYTE_WIDTH));
            end loop;
            wait until '1'=CLK and CLK'event;
        end loop;

        wait until '1' = CLK and CLK'event;

        MASTER_EN <= '0';

        --CHECK      
        ENABLE <= '1';  
        EN0 <= '1';
        
        for i in 0 to 5 loop
            ADDRESS0 <= std_logic_vector(to_unsigned(i, 3*BYTE_WIDTH));
            for j in 0 to MATRIX_WIDTH-1 loop
                wait for 1 ns;
                if READ_PORT0(j) /= std_logic_vector(to_unsigned(j*(i+1), BYTE_WIDTH)) then
                    report "Error reading memory through port1!";
                    --stop_the_clock <= true;
                    --wait;
                end if;
            end loop;
            wait until '1'=CLK and CLK'event;
        end loop;

        ENABLE <= '0';
        EN0 <= '0';
        wait until '1' = CLK and CLK'event;
        
        report "Test was successful!" severity NOTE;
        stop_the_clock <= true;
        wait;
    end process STIMULUS;
    
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