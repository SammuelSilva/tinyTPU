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

--! @file DIST_RAM.vhdl
--! @author Jonas Fuhrmann
--! Este Componente inclui uma memoria, 
--! Este Componente deve ser utilizado por Memorias Menores

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity DIST_RAM is
    generic(
        DATA_WIDTH      : natural := 8; --!< A Largura de uma palavra de dados.
        DATA_DEPTH      : natural := 32; --!< A "altura" da memoria.
        ADDRESS_WIDTH   : natural := 5 --!< A Largura dos endereços.
    );
    port(
        CLK     : in  std_logic;
        IN_ADDR : in  std_logic_vector(ADDRESS_WIDTH-1 downto 0); --!< Input do endereço para a memoria.
        INPUT   : in  std_logic_vector(DATA_WIDTH-1 downto 0); --!< Porta de escrita do dado na memoria.
        WRITE_EN: in  std_logic; --!< Ativador de escrita da memoria.
        OUT_ADDR: in  std_logic_vector(ADDRESS_WIDTH-1 downto 0); --!< Output do endereço da memoria.
        OUTPUT  : out std_logic_vector(DATA_WIDTH-1 downto 0) --!< Porta de leitura da memória.
    );
end entity DIST_RAM;

--! @brief The architecture of the distributed RAM component.
architecture BEH of DIST_RAM  is
    --!< Ram de que armazena 32 palavras
    type RAM_TYPE is array (0 to DATA_DEPTH-1) of std_logic_vector(DATA_WIDTH-1 downto 0);
	signal RAM : RAM_TYPE;
begin
    --!< A Cada Evento de Clock e clock igual a '1', caso a escrita esteja ativada é inserido uma palavra na memoria de 32 bits.
    --!< O Output e o Input são o mesmo endereço, então o dado escrito na memoria será lido (Obrigatoriamente) caso o IF seja verdadeiro.
    --!< Caso contrario será realizada somente a leitura de uma palavra da memoria.
    RAM_PROC:
    process(CLK, IN_ADDR, OUT_ADDR) is
    begin
        if CLK'event and CLK = '1' then
            if WRITE_EN = '1' then
                RAM(to_integer(unsigned(IN_ADDR))) <= INPUT;
            end if;
        end if;
        
        OUTPUT <= RAM(to_integer(unsigned(OUT_ADDR)));
    end process RAM_PROC; 
end architecture BEH;