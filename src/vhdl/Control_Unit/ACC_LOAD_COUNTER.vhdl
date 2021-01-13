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

--! @file ACC_LOAD_COUNTER.vhdl
--! @author Jonas Fuhrmann

--! Este componente é um contador, que faz uso de um Bloco DSP (Digital Signal Processing) para rapidas e maiores somas.
--! O Contador pode ser carregado com qualquer valor dado e soma o valor inicial a cada Ciclo de clock. 
--! O Contador sera resetado para o valor inicial, quando o mesmo alcancar um Valor.


use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    

--! @brief The architecture of the DSP load counter component.
-- COUNTER_WIDTH = 32
architecture ACC_COUNTER of DSP_LOAD_COUNTER is
    signal COUNTER_INPUT_cs : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); -- Sinais de passagem do Input do contador
    signal COUNTER_INPUT_ns : std_logic_vector(COUNTER_WIDTH-1 downto 0);
    
    signal START_VAL_cs : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); -- Sinais de passagem do valor inical
    signal START_VAL_ns : std_logic_vector(COUNTER_WIDTH-1 downto 0);
    
    signal INPUT_PIPE_cs : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); -- Pipe de passagem do input
    signal INPUT_PIPE_ns : std_logic_vector(COUNTER_WIDTH-1 downto 0);
    
    signal COUNTER_cs : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); 
    signal COUNTER_ns : std_logic_vector(COUNTER_WIDTH-1 downto 0);
    
    signal LOAD_cs : std_logic := '0'; -- Sinais de Carregamento
    signal LOAD_ns : std_logic;
    
    attribute use_dsp : string;
    attribute use_dsp of COUNTER_ns : signal is "yes";
begin
    -- Este acumulador reseta tanto com o LOAD quanto quando o valor de COUNTER_cs atingir um valor designado: (to_unsigned(MATRIX_WIDTH-1, COUNTER_WIDTH) + unsigned(START_VAL_cs))
    -- NAO GERA UM SINAL DE EVENTO
    
    LOAD_ns <= LOAD; -- "Load" é carregado
    
    START_VAL_ns <= START_VAL; -- O valor inicial é carregado

    -- INPUT_PIPE_ns recebe o valor de START_VAL quando o valor de LOAD estiver ativado, caso contrario ele recebe na posicao inicial 1 e nas restantes 0
    INPUT_PIPE_ns <= START_VAL when LOAD = '1' else ((COUNTER_WIDTH-1 downto 1 => '0')&'1');
    COUNTER_INPUT_ns <= INPUT_PIPE_cs; -- COUNTER_INPUT_ns <- INPUT_PIPE_cs <- INPUT_PIPE_ns;
    
    -- O primeiro caso faz com que o contador reset para o estado inicial, ou seja, o output seria o valor inicial, no restante somente o Else ocorre somando de um em um.
    COUNTER_ns <= START_VAL_cs when COUNTER_cs = std_logic_vector(to_unsigned(MATRIX_WIDTH-1, COUNTER_WIDTH) + unsigned(START_VAL_cs))
                               else std_logic_vector(unsigned(COUNTER_cs) + unsigned(COUNTER_INPUT_cs));
    COUNT_VAL <= COUNTER_cs; -- COUNT_VAL <- COUNTER_cs <- COUNTER_ns | ou | COUNT_VAL <- COUNTER_cs <- (others => '0')
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                COUNTER_INPUT_cs <= (others => '0');
                INPUT_PIPE_cs <= (others => '0');
                LOAD_cs <= '0';
            else
                if ENABLE = '1' then
                    COUNTER_INPUT_cs <= COUNTER_INPUT_ns; -- Recebe o dado que esta armazenado no INPUT_PIPE_cs que pode ser no começo o Start_value e no restante 1
                    INPUT_PIPE_cs <= INPUT_PIPE_ns; -- Carrega o proximo dado a ser inserido no COUNTER_INPUT_cs que pode ser 1 ou o start_value
                    LOAD_cs <= LOAD_ns; -- LOAD_cs <- LOAD_ns <- LOAD;
                end if;
            end if;
            
            -- Se o contador atingir o "valor esperado" então o mesmo deve resetado para o valor inicial
            if LOAD_cs = '1' then
                COUNTER_cs <= (others => '0');
            else
                if ENABLE = '1' then -- Atualiza o valor do contador atual
                    COUNTER_cs <= COUNTER_ns;
                end if;
            end if;
            
            if LOAD = '1' then -- So é carregado no começo da contagem
                START_VAL_cs <= START_VAL_ns;
            end if;
        end if;
    end process SEQ_LOG;
end architecture ACC_COUNTER;
