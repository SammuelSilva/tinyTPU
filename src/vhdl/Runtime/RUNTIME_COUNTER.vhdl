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

--! @file RUNTIME_COUNTER.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui um contador para medição do tempo de execução.
--! O contador inicia quando uma nova instrução é inserida na TPU.
--! Quando a TPU sinaliza uma sincronização, o contador ira parar e "segurar" o valor atual.
--! Verificação do tempo de execução. (VERIFICAR)
use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity RUNTIME_COUNTER is
    port(
        CLK, RESET      :  in std_logic;

        INSTRUCTION_EN  :  in std_logic; --!< Sinaliza que uma nova instrução foi recebida e inicia o contador
        SYNCHRONIZE     :  in std_logic; --!< Sinaliza que os calculos acabaram, para o contador e armazena o valor.
        COUNTER_VAL     : out WORD_TYPE  --!< O valor atual do contador. 
    );
end entity RUNTIME_COUNTER;

--! @brief The architecture of the runtime counter.
architecture BEH of RUNTIME_COUNTER is
    constant ADD_ONE  : std_logic_vector(1 downto 0) := (1 => '0', 0 => '1');

    signal COUNTER_cs : WORD_TYPE := (others => '0');
    signal COUNTER_ns : WORD_TYPE;
    
    signal PIPELINE_cs : WORD_TYPE := (others => '0');
    signal PIPELINE_ns : WORD_TYPE;
    
    signal STATE_cs : std_logic := '0';
    signal STATE_ns : std_logic;
    
    signal RESET_COUNTER : std_logic;
    
    attribute use_dsp : string;
    attribute use_dsp of COUNTER_ns : signal is "yes";
begin
    -- Somador
    COUNTER_ns  <= std_logic_vector(unsigned(COUNTER_cs) + unsigned(ADD_ONE));

    -- Pipeline para o DSP 
    PIPELINE_ns <= COUNTER_cs;
    COUNTER_VAL <= PIPELINE_cs;

    -- Maquina de Estados finita
    -- State_cs = 0 :: Valor de saida do contador é mantido
    -- State_cs = 1 :: Valor de saida do contador é atualizado
    -- Quando ocorre a sincronia (SYNCHRONIZE = 1), o STATE_ns recebe 0 e não ocorre um reset do valor
        -- Independente se há ou não uma instrução nova
    -- State_cs = 0 => State_cs = 1 :: INSTRUCTION_EN & SYNCHRONIZE = '10'
    -- State_cs = 1 => State_cs = 0 :: INSTRUCTION_EN & SYNCHRONIZE = '01','11'
    FSM:
    process(INSTRUCTION_EN, SYNCHRONIZE, STATE_cs) is
        variable INST_EN_SYNCH : std_logic_vector(0 to 1);
    begin
        INST_EN_SYNCH := INSTRUCTION_EN & SYNCHRONIZE; -- Concatena uma instrução nova e se os calculos da ultima intrução terminaram
        case STATE_cs is -- Quando o estado for '0'
            when '0' =>
                case INST_EN_SYNCH is
                    when "00" => -- Nao recebeu nova instrução e há calculos sendo realizados
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                    when "01" => -- Não recebeu nova instrução, os calculos terminaram, armazena o valor atual do contador
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                    when "10" => -- recebeu uma nova instrução.
                        STATE_ns <= '1';
                        RESET_COUNTER <= '1';
                    when "11" => -- Recebeu uma nova instrução e o os calculos terminaram
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                    when others => -- Shouldn't happen
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                end case;
            when '1' => -- Recebeu uma nova instrução (state_cs = 1)
                case INST_EN_SYNCH is
                    when "00" =>  -- Nao recebeu uma instrução e há calculos sendo realizados
                        STATE_ns <= '1';
                        RESET_COUNTER <= '0';
                    when "01" => -- Não recebeu uma instrução, os calculos terminaram, armazena o valor atual do contador
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                    when "10" => -- recebeu uma Instrução e os calculos da atual da atual nao terminou.
                        STATE_ns <= '1';
                        RESET_COUNTER <= '0';
                    when "11" =>
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                    when others => -- Shouldn't happen
                        STATE_ns <= '0';
                        RESET_COUNTER <= '0';
                end case;
            when others => -- Shouldn't happen
                STATE_ns <= '0';
                RESET_COUNTER <= '0';
        end case;
    end process FSM;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                STATE_cs <= '0';
                PIPELINE_cs <= (others => '0');
            else
                STATE_cs <= STATE_ns; -- Estado da maquina
                PIPELINE_cs <= PIPELINE_ns; -- Valor do contador
            end if;
            
            if RESET_COUNTER = '1' then
                COUNTER_cs <= (others => '0');
            else
                if STATE_cs = '1' then -- Se o estado da maquina for atualiza o valor do contador
                    COUNTER_cs <= COUNTER_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;