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

--! @file INSTRUCTION_FIFO.vhdl
--! @author Jonas Fuhrmann
--! Este Componente Incluiu uma Simples FIFO para a Instrução.
--! Instruções são divididas em palavras de 32 Bit, com excessão da ultima palavra, na qual é de 16 bit

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;

entity INSTRUCTION_FIFO is
    generic(
        FIFO_DEPTH  : natural := 32
    );
    port(
        CLK, RESET  : in  std_logic;
        LOWER_WORD  : in  WORD_TYPE; --!< A palavra mais baixa da instrução.
        MIDDLE_WORD : in  WORD_TYPE; --!< A palavra do meio da instrução.
        UPPER_WORD  : in  HALFWORD_TYPE; --!< A meia-palavra (16 Bit) superior da instrução.
        WRITE_EN    : in  std_logic_vector(0 to 2); --!< Ativadores de escrita para cada palavra.
        
        OUTPUT      : out INSTRUCTION_TYPE; --!< Porta de Leitura da FIFO.
        NEXT_EN     : in  std_logic; --!< Ativador de Leitura ou "Proximo" da FIFO (Apaga os valores atuais).
        
        EMPTY       : out std_logic; --!< Determina se a FIFO esta vazia.
        FULL        : out std_logic --!< Determina se a FIFO esta cheia.
    );
end entity INSTRUCTION_FIFO;

--! @brief The architecture of the instruction FIFO component.
architecture BEH of INSTRUCTION_FIFO is
    component FIFO is
        generic(
            FIFO_WIDTH  : natural := 8;
            FIFO_DEPTH  : natural := 32
        );
        port(
            CLK, RESET  : in  std_logic;
            INPUT       : in  std_logic_vector(FIFO_WIDTH-1 downto 0);
            WRITE_EN    : in  std_logic;
            
            OUTPUT      : out std_logic_vector(FIFO_WIDTH-1 downto 0);
            NEXT_EN     : in  std_logic;
            
            EMPTY       : out std_logic;
            FULL        : out std_logic
        );
    end component FIFO;
    for all : FIFO use entity WORK.FIFO(DIST_RAM_FIFO);
    
    signal EMPTY_VECTOR : std_logic_vector(0 to 2);
    signal FULL_VECTOR  : std_logic_vector(0 to 2);
    
    signal LOWER_OUTPUT : WORD_TYPE;
    signal MIDDLE_OUTPUT: WORD_TYPE;
    signal UPPER_OUTPUT : HALFWORD_TYPE;
begin
    
    -- Verificação se a FIFO esta vazia ou Cheia
    EMPTY   <= EMPTY_VECTOR(0) or EMPTY_VECTOR(1) or EMPTY_VECTOR(2);
    FULL    <= FULL_VECTOR(0)  or FULL_VECTOR(1)  or FULL_VECTOR(2);
    
    -- Saida passa pelo conversor de BITS -> Instrução com a concatenação de todas as palavras
    OUTPUT  <= BITS_TO_INSTRUCTION(UPPER_OUTPUT & MIDDLE_OUTPUT & LOWER_OUTPUT);

    -- Port Map para a FIFO das 3 partes do conjunto de palavra que será escrito ou lido no DIST_RAM
    FIFO_0 : FIFO
    generic map(
        FIFO_WIDTH  => 4*BYTE_WIDTH,
        FIFO_DEPTH  => FIFO_DEPTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        INPUT       => LOWER_WORD,
        WRITE_EN    => WRITE_EN(0),
        OUTPUT      => LOWER_OUTPUT,
        NEXT_EN     => NEXT_EN,
        EMPTY       => EMPTY_VECTOR(0),
        FULL        => FULL_VECTOR(0)
    );
    
    FIFO_1 : FIFO
    generic map(
        FIFO_WIDTH  => 4*BYTE_WIDTH,
        FIFO_DEPTH  => FIFO_DEPTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        INPUT       => MIDDLE_WORD,
        WRITE_EN    => WRITE_EN(1),
        OUTPUT      => MIDDLE_OUTPUT,
        NEXT_EN     => NEXT_EN,
        EMPTY       => EMPTY_VECTOR(1),
        FULL        => FULL_VECTOR(1)
    );
    
    FIFO_2 : FIFO
    generic map(
        FIFO_WIDTH  => 2*BYTE_WIDTH,
        FIFO_DEPTH  => FIFO_DEPTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        INPUT       => UPPER_WORD,
        WRITE_EN    => WRITE_EN(2),
        OUTPUT      => UPPER_OUTPUT,
        NEXT_EN     => NEXT_EN,
        EMPTY       => EMPTY_VECTOR(2),
        FULL        => FULL_VECTOR(2)
    );
end architecture BEH;