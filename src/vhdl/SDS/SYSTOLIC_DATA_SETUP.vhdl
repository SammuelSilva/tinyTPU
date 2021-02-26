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

--! @file SYSTOLIC_DATA_SETUP.vhdl
--! @author Jonas Fuhrmann
--! Este componente recebe um Byte Array e o diagonaliza para a ser usado na MMU.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity SYSTOLIC_DATA_SETUP is
    generic(
        MATRIX_WIDTH  : natural := 8;
        MATRIX_HALF   : natural := (8-1)/NUMBER_OF_MULT
    );
    port(
        CLK, RESET      : in  std_logic;
        ENABLE          : in  std_logic;
        DATA_INPUT      : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< A entrada byte array a ser diagonalizada.
        SYSTOLIC_OUTPUT : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) --!< Saida diagonalizada.
    );
end entity SYSTOLIC_DATA_SETUP;

--! @brief Architecture of the systolic data setup component.
architecture BEH of SYSTOLIC_DATA_SETUP is
    -- Fila da matriz de Byte Array
    signal BUFFER_REG_cs : BYTE_ARRAY_3D_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1, NUMBER_OF_MULT to MATRIX_HALF+1, 0 to NUMBER_OF_MULT-1) := (others => (others => (others => (others => '0'))));
    signal BUFFER_REG_ns : BYTE_ARRAY_3D_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1, NUMBER_OF_MULT to MATRIX_HALF+1, 0 to NUMBER_OF_MULT-1);
begin
    
    INPUT_GEN:
    for k in 0 to NUMBER_OF_MULT-1 generate
        SYSTOLIC_OUTPUT(k) <= DATA_INPUT(k);
    end generate INPUT_GEN; 

    -- Registro responsavel por pegar o DATA_INPUT(1, j) e o inserir no BUFFER_REG e fazer um deslizamento dos dados que ja estavam no buffer
    SHIFT_REG:
    process(DATA_INPUT, BUFFER_REG_cs) is
        variable DATA_INPUT_v       : BYTE_ARRAY_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1);
        variable BUFFER_REG_cs_v    : BYTE_ARRAY_3D_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1, NUMBER_OF_MULT to MATRIX_HALF+1, 0 to NUMBER_OF_MULT-1);
        variable BUFFER_REG_ns_v    : BYTE_ARRAY_3D_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1, NUMBER_OF_MULT to MATRIX_HALF+1, 0 to NUMBER_OF_MULT-1);
        variable FLAG_v             : std_logic;
    begin
        -- Atribui os dados para as variaveis, o DATA_INPUT_V recebe os dados de DATA_INPUT exceto os contidos na posição 0.
        DATA_INPUT_v := DATA_INPUT(NUMBER_OF_MULT to MATRIX_WIDTH-1);
        BUFFER_REG_cs_v := BUFFER_REG_cs;
        FLAG_v := '1';

        for j in NUMBER_OF_MULT to MATRIX_WIDTH-1 loop
            for k in 0 to NUMBER_OF_MULT-1 loop
                if FLAG_V = '1' then 
                    if (k + j) <= MATRIX_WIDTH-1 then
                        BUFFER_REG_ns_v(NUMBER_OF_MULT, (j/NUMBER_OF_MULT) + 1, k) := DATA_INPUT_v(j + k); -- A posição 1 do buffer é atualizado com o valor de DATA_INPUT
                    end if;
                end if;
            end loop;
            FLAG_v := not FLAG_v;
        end loop;
        
        for i in NUMBER_OF_MULT+1 to MATRIX_WIDTH-1 loop
            for j in NUMBER_OF_MULT to MATRIX_HALF+1 loop
                for k in 0 to NUMBER_OF_MULT-1 loop
                    BUFFER_REG_ns_v(i, j, k) := BUFFER_REG_cs_v(i-1, j, k); -- Copia da posição 2 para frente os dados contidos no registrador atual para o proximo
                end loop;
            end loop;
        end loop;

        -- Registrador Proximo recebe o Registrador_v atualizado com o DATA_INPUT na diagonal e os demais dados contidos no registrador atual
        BUFFER_REG_ns <= BUFFER_REG_ns_v; 
    end process SHIFT_REG;
    
    SYSTOLIC_PROCESS:
    process(BUFFER_REG_cs) is
        variable BUFFER_REG_cs_v    :BYTE_ARRAY_3D_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1, NUMBER_OF_MULT to MATRIX_HALF+1, 0 to NUMBER_OF_MULT-1);
        variable SYSTOLIC_OUTPUT_v  : BYTE_ARRAY_TYPE(NUMBER_OF_MULT to MATRIX_WIDTH-1);
        variable FLAG_v             : std_logic;
    begin
        BUFFER_REG_cs_v := BUFFER_REG_cs; -- Carrega o BUFFER atual em sua variavel
        FLAG_v := '1';

        for i in NUMBER_OF_MULT to MATRIX_WIDTH-1 loop
            if FLAG_v = '1' then
                for k in 0 to NUMBER_OF_MULT-1 loop
                    if (k + i) <= MATRIX_WIDTH-1 then
                        SYSTOLIC_OUTPUT_v(i + k) := BUFFER_REG_cs_v((i/NUMBER_OF_MULT) + 1, (i/NUMBER_OF_MULT) + 1, k); -- Pegas os valores na diagonal do BUFFER_REG_cs e insere no systolic_output_v
                    end if;
                end loop;
            end if;
            FLAG_v := not FLAG_v;
        end loop;
        
        SYSTOLIC_OUTPUT(NUMBER_OF_MULT to MATRIX_WIDTH-1) <= SYSTOLIC_OUTPUT_v; -- Carrega o Systolic Output
    end process SYSTOLIC_PROCESS;

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                BUFFER_REG_cs <= (others => (others => (others => (others => '0'))));
            else
                if ENABLE = '1' then -- Caso esteja ativado carrega o Proximo Registro que vem do SHIFT_REG
                    BUFFER_REG_cs <= BUFFER_REG_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;