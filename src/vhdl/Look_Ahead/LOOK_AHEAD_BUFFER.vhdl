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

--! @file LOOK_AHEAD_BUFFER.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui um pequeno look ahead buffer para as instruções.
--! As instruções de peso devem ser executadas com a MMU em paralelo.
--! O LAB espera por uma instrução de Matrix Multiply, quando uma instrução de peso é enviada.


use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity LOOK_AHEAD_BUFFER is
    port(
        CLK, RESET          :  in std_logic;
        ENABLE              :  in std_logic;
        
        INSTRUCTION_BUSY    :  in std_logic; --!< Busy feedback do control coordinator para parar o pipeline.
        
        INSTRUCTION_INPUT   :  in INSTRUCTION_TYPE; --!< O input para as instruções.
        INSTRUCTION_WRITE   :  in std_logic; --!< Flag de escrita para as instruções.
        
        INSTRUCTION_OUTPUT  : out INSTRUCTION_TYPE; --!< O output para as instruções em pipeline.
        INSTRUCTION_READ    : out std_logic --!< Flag de leitura para as instruções.
    );
end entity LOOK_AHEAD_BUFFER;

--! @brief The architecture of the look ahead buffer.
architecture BEH of LOOK_AHEAD_BUFFER is
    -- Registradores para o Input da instruçao
    signal INPUT_REG_cs     : INSTRUCTION_TYPE := INIT_INSTRUCTION;
    signal INPUT_REG_ns     : INSTRUCTION_TYPE;
    
    -- Registradores para a Flag de escrita
    signal INPUT_WRITE_cs   : std_logic := '0';
    signal INPUT_WRITE_ns   : std_logic;
    
    -- Pipeline para as instruções
    signal PIPE_REG_cs      : INSTRUCTION_TYPE := INIT_INSTRUCTION;
    signal PIPE_REG_ns      : INSTRUCTION_TYPE;
    
    -- Pipeline para as flags de escrita
    signal PIPE_WRITE_cs    : std_logic := '0';
    signal PIPE_WRITE_ns    : std_logic;
    
    -- Registradores para o Output das instruções
    signal OUTPUT_REG_cs    : INSTRUCTION_TYPE := INIT_INSTRUCTION;
    signal OUTPUT_REG_ns    : INSTRUCTION_TYPE;
    
    -- Registradores para as instruções em pipeline
    signal OUTPUT_WRITE_cs  : std_logic := '0';
    signal OUTPUT_WRITE_ns  : std_logic;
begin
    -- Inserção de uma nova instrução
    INPUT_REG_ns    <= INSTRUCTION_INPUT;
    
    -- A instrução de saida para o pipeline recebera uma nova instrução se o Controlador nao estiver "BUSY", caso contrario recebe o valor default
    INSTRUCTION_OUTPUT  <= OUTPUT_REG_cs when INSTRUCTION_BUSY = '0' else INIT_INSTRUCTION;
    
    -- Inserção de uma nova flag para escrita
    INPUT_WRITE_ns  <= INSTRUCTION_WRITE;

    -- A instrução de saida para o pipeline ler uma nova instrução se o Controlador nao estiver "BUSY", caso contrario recebe o valor default
    INSTRUCTION_READ    <= OUTPUT_WRITE_cs when INSTRUCTION_BUSY = '0' else '0';

    -- ??????????????????????????????????
    LOOK_AHEAD:
    process(INPUT_REG_cs, PIPE_REG_cs, INPUT_WRITE_cs, PIPE_WRITE_cs) is
    begin 
        if PIPE_WRITE_cs = '1' then -- Verifica se existe uma instrução a ser inserida
            if PIPE_REG_cs.OP_CODE(OP_CODE_WIDTH-1 downto 3) = "00001" then -- Verifica se há um peso no Pipeline
                if INPUT_WRITE_cs = '1' then -- E se o sinal de escrita estiver ativado, então novos dados são alimentados para o output e inseridos no pipeline
                    PIPE_REG_ns     <= INPUT_REG_cs;
                    OUTPUT_REG_ns   <= PIPE_REG_cs;
                    PIPE_WRITE_ns   <= INPUT_WRITE_cs;
                    OUTPUT_WRITE_ns <= PIPE_WRITE_cs;
                else -- Espera por uma nova instrução a ser inserida
                    PIPE_REG_ns     <= PIPE_REG_cs; -- O pipe atual retorna um estado
                    OUTPUT_REG_ns   <= INIT_INSTRUCTION; -- O output de instrução é default
                    PIPE_WRITE_ns   <= PIPE_WRITE_cs;-- O pipe atual retorna um estado
                    OUTPUT_WRITE_ns <= '0'; -- Output de escrita é default
                end if;
            else 
                PIPE_REG_ns     <= INPUT_REG_cs;
                OUTPUT_REG_ns   <= PIPE_REG_cs;
                PIPE_WRITE_ns   <= INPUT_WRITE_cs;
                OUTPUT_WRITE_ns <= PIPE_WRITE_cs;
            end if;
        else -- Se não tiver ele insere mesmo assim. QUE???????????????????????????????
            PIPE_REG_ns     <= INPUT_REG_cs;
            OUTPUT_REG_ns   <= PIPE_REG_cs;
            PIPE_WRITE_ns   <= INPUT_WRITE_cs;
            OUTPUT_WRITE_ns <= PIPE_WRITE_cs;
        end if;
    end process LOOK_AHEAD;

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                INPUT_REG_cs    <= INIT_INSTRUCTION;
                PIPE_REG_cs     <= INIT_INSTRUCTION;
                OUTPUT_REG_cs   <= INIT_INSTRUCTION;
                
                INPUT_WRITE_cs  <= '0';
                PIPE_WRITE_cs   <= '0';
                OUTPUT_WRITE_cs <= '0';
            else
                if ENABLE = '1' and INSTRUCTION_BUSY = '0' then
                    INPUT_REG_cs    <= INPUT_REG_ns;
                    PIPE_REG_cs     <= PIPE_REG_ns;
                    OUTPUT_REG_cs   <= OUTPUT_REG_ns;
                    
                    INPUT_WRITE_cs  <= INPUT_WRITE_ns;
                    PIPE_WRITE_cs   <= PIPE_WRITE_ns;
                    OUTPUT_WRITE_cs <= OUTPUT_WRITE_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;