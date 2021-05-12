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

--! @file DSP_COUNTER.vhdl
--! @author Jonas Fuhrmann

--! Este componente é um contador, que faz uso de um Bloco DSP (Digital Signal Processing) para rapidas e maiores somas.
--! O contador inicia em 0 e pode ser reiniciado. Se o contador atinge um determinado valor, um Sinal de evento é emitido.
--! @details The counter starts at 0 and can be resetted. If the counter reaches a given end value, an event signal is asserted.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity DSP_COUNTER_BUFF_ACC is
    generic(
        COUNTER_WIDTH   : natural := 32 --!< The width of the counter.
    );
    port(
        CLK, RESET  : in  std_logic;
        ENABLE      : in  std_logic;
        
        END_VAL     : in  std_logic_vector(COUNTER_WIDTH-1 downto 0); --!< O Valor final do componente em que sera emitido um Sinal de evento
        LOAD        : in  std_logic; --!< Sinal para carregar o valor final.
        
        COUNT_VAL   : out std_logic_vector(COUNTER_WIDTH-1 downto 0); --!< O valor atual do contador.
        
        COUNT_EVENT : out std_logic --!< O evento, que sera ativado quando o valor final for atingido.
    );
end entity DSP_COUNTER_BUFF_ACC;

--! @brief The architecture of the DSP counter component.
architecture BEH of DSP_COUNTER_BUFF_ACC is
    constant ADD_TWO  : unsigned(COUNTER_WIDTH-1 downto 0) := (COUNTER_WIDTH-1 downto 2 => '0')&'1'&'0';
    constant ADD_ONE  : unsigned(COUNTER_WIDTH-1 downto 0) := (COUNTER_WIDTH-1 downto 1 => '0')&'1';

    signal ODD : std_logic := '0';
    signal COUNTER : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); -- Contador
    signal END_REG : std_logic_vector(COUNTER_WIDTH-1 downto 0) := (others => '0'); -- Registro do valor final
    
    -- Sinais do evento
    signal EVENT_cs : std_logic := '0';
    signal EVENT_ns : std_logic;
    
    signal EVENT_PIPE_cs : std_logic := '0';
    signal EVENT_PIPE_ns : std_logic;
    
    attribute use_dsp : string;
    attribute use_dsp of COUNTER : signal is "yes";
begin
    -- So é encerrado quando o valor final é atingido. 
    -- Nada impede que o valor final seja atualizado no decorrer da contagem e caso ocorra a contagem não é parada
    -- GERA UM SINAL DE EVENTO

    COUNT_VAL <= COUNTER; -- Carrega o valor atual do contador

    -- COUNT_EVENT <- EVENT_PIPE_cs <- EVENT_PIPE_ns <- EVENT_cs <- EVENT_ns | SO ATIVA SE: COUNTER = END_REG  (Contador atinge valor final)
    EVENT_PIPE_ns <= EVENT_cs;
    COUNT_EVENT <= EVENT_PIPE_cs; -- Quando o COUNT_EVENT for 1 a contagem acaba 

    
    -- Processo que verifica se o valor atual do contador é o valor final
    CHECK:
    process(COUNTER, END_REG) is
        variable ODD_v : std_logic := '0';
    begin
        if COUNTER = END_REG then 
            EVENT_ns <= '1'; -- Sinal para acabar a contagem
        else
            EVENT_ns <= '0';
        end if;
    end process CHECK;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                COUNTER <= (others => '0');
                EVENT_cs <= '0';
                EVENT_PIPE_cs <= '0';
                ODD <= '0';
            else
                if ENABLE = '1' then
                    COUNTER <= std_logic_vector(unsigned(COUNTER) + ADD_ONE); -- Soma de "um em um" --- SOMAR DE DOIS EM DOIS
                    -- Pipe do sinal do Evento, maior parte do tempo é 0
                    EVENT_cs <= EVENT_ns;
                    EVENT_PIPE_cs <= EVENT_PIPE_ns;
                end if;
            end if;
            
            if LOAD = '1' then -- Sinal para carregar o valor final
                END_REG <= END_VAL;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;
