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

--! @file CONTROL_COORDINATOR.vhdl
--! @author Jonas Fuhrmann
--! Este Componente Coordena todas as Control Units.
--! O Control Coordinator encaminha as intruções para as apropriadas Control Unit no momento certo e espera cada Unidade terminar antes de enviar novas instruções.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity CONTROL_COORDINATOR is
    port(
        CLK, RESET                    :  in std_logic;
        ENABLE                        :  in std_logic;
            
        INSTRUCTION                   :  in INSTRUCTION_TYPE; --!< Instrução a Ser encaminhada.
        INSTRUCTION_EN                :  in std_logic; --!< Ativador para a instrução.
        
        BUSY                          : out std_logic; --!< Flag que informa se uma Unit esta ocupada enquanto uma nova instrução tenta ser encaminhada.
        
        WEIGHT_BUSY                   :  in std_logic; --!< Flag de ocupado para o input da Weight Control Unit.
        WEIGHT_RESOURCE_BUSY          :  in std_logic; --!< Flag de ocupado para o Resource input da Weight Control Unit.
        WEIGHT_INSTRUCTION            : out WEIGHT_INSTRUCTION_TYPE; --!< Instrução de Saida para a Weight COntrol Unit.
        WEIGHT_INSTRUCTION_EN         : out std_logic; --!< Ativador para Instrução para a Weight Control Unit.
        
        MATRIX_BUSY                   :  in std_logic; --!< Flag de ocupado para o input da matrix multiply control unit.
        MATRIX_RESOURCE_BUSY          :  in std_logic; --!< Flag de ocupado para o Resource input da matrix multiply control unit.
        MATRIX_INSTRUCTION            : out INSTRUCTION_TYPE; --!< Instrução de Saida para a matrix multiply control unit.
        MATRIX_INSTRUCTION_EN         : out std_logic; --!< Instrução de Saida para a matrix multiply control unit.
        
        ACTIVATION_BUSY               :  in std_logic; --!< Flag de ocupado para o input da activation control unit.
        ACTIVATION_RESOURCE_BUSY      :  in std_logic; --!< Flag de ocupado para o Resource input da activation control unit.
        ACTIVATION_INSTRUCTION        : out INSTRUCTION_TYPE; --!< Instrução de Saida para a activation control unit.
        ACTIVATION_INSTRUCTION_EN     : out std_logic; --!< Instrução de Saida para a activation control unit.
        
        LOAD_INT_BUSY                 :  in std_logic;
        LOAD_INT_RESOURCE_BUSY        :  in std_logic;
        LOAD_INTERRUPTION_EN          : out std_logic;

        SYNCHRONIZE                   : out std_logic --!< Sera TRUE, quando uma instrução síncrona foi inserida e todas as unidades estão finalizadas.
    );
end entity CONTROL_COORDINATOR;

--! @brief The architecture of the control coordinator component.
architecture BEH of CONTROL_COORDINATOR is
    -- Flag de Decodificação no formato "0000"   
    signal EN_FLAGS_cs : std_logic_vector(0 to 4) := (others => '0'); -- 0: WEIGHT 1: MATRIX 2: ACTIVATION 3: SYNCHRONIZE
    signal EN_FLAGS_ns : std_logic_vector(0 to 4);
    
    -- Regitradores de Instruções
    signal INSTRUCTION_cs : INSTRUCTION_TYPE := INIT_INSTRUCTION; -- Inicializado com a funçao INIT_INSTRUCTION que é todas os dados da INSTRUCTION é "0"
    signal INSTRUCTION_ns : INSTRUCTION_TYPE;
    
    -- Registradores de Flag de ativação de Instruções
    signal INSTRUCTION_EN_cs : std_logic := '0';
    signal INSTRUCTION_EN_ns : std_logic;
    
    -- Flag que informa se há ou não uma instrução executando
    signal INSTRUCTION_RUNNING : std_logic;
begin
    -- Carregamento de uma nova Instrução e do seu ativador
    INSTRUCTION_ns <= INSTRUCTION;
    INSTRUCTION_EN_ns <= INSTRUCTION_EN;

    -- Sinal se a Unit esta ocupada
    BUSY <= INSTRUCTION_RUNNING;
    
    DECODE:
    process(INSTRUCTION) is
        variable INSTRUCTION_v : INSTRUCTION_TYPE;
        
        variable EN_FLAGS_ns_v : std_logic_vector(0 to 4);
        variable SET_SYNCHRONIZE_v : std_logic; -- Não é usada?
    begin
        INSTRUCTION_v := INSTRUCTION;

        if    INSTRUCTION_v.OP_CODE    = x"FF" then -- Quando uma instrução síncrona foi inserida e todas as unidades estão finalizadas.
            EN_FLAGS_ns_v := "00001";
        elsif INSTRUCTION_v.OP_CODE    = x"FE" then -- Unidade que controla a interrupção para carregamento dos pesos para Memoria.
            EN_FLAGS_ns_v := "00010";
        elsif INSTRUCTION_v.OP_CODE(7) = '1'   then -- unidade controla o fluxo de dados dos acumuladores.
            EN_FLAGS_ns_v := "00100";
        elsif INSTRUCTION_v.OP_CODE(5) = '1'   then -- Unidade que controla a Multiplicação de Matrizes junto com o Systolic Data
            EN_FLAGS_ns_v := "01000";
        elsif INSTRUCTION_v.OP_CODE(3) = '1'   then -- Unidade que controla o carregamento dos pesos para MMU.
            EN_FLAGS_ns_v := "10000";
        else -- Nenhuma operação
            EN_FLAGS_ns_v := "00000";
        end if;
        
        EN_FLAGS_ns <= EN_FLAGS_ns_v;
    end process DECODE;
    
    RUNNING_DETECT:
    process(INSTRUCTION_cs, INSTRUCTION_EN_cs, EN_FLAGS_cs, LOAD_INT_BUSY, WEIGHT_BUSY, MATRIX_BUSY, ACTIVATION_BUSY, WEIGHT_RESOURCE_BUSY, LOAD_INT_RESOURCE_BUSY, MATRIX_RESOURCE_BUSY, ACTIVATION_RESOURCE_BUSY) is
        -- Variaveis para os sinais de entrada
        variable INSTRUCTION_v                  : INSTRUCTION_TYPE;
        variable INSTRUCTION_EN_v               : std_logic;
        variable EN_FLAGS_v                     : std_logic_vector(0 to 4);
        variable WEIGHT_BUSY_v                  : std_logic;
        variable MATRIX_BUSY_v                  : std_logic;
        variable ACTIVATION_BUSY_v              : std_logic;
        variable LOAD_INT_BUSY_v                : std_logic;
        variable WEIGHT_RESOURCE_BUSY_v         : std_logic;
        variable MATRIX_RESOURCE_BUSY_v         : std_logic;
        variable ACTIVATION_RESOURCE_BUSY_v     : std_logic;
        variable LOAD_INT_RESOURCE_BUSY_v       : std_logic;

        -- Variaveis para os sinais de Saida
        variable WEIGHT_INSTRUCTION_EN_v        : std_logic;
        variable MATRIX_INSTRUCTION_EN_v        : std_logic;
        variable ACTIVATION_INSTRUCTION_EN_v    : std_logic;
        variable INSTRUCTION_RUNNING_v          : std_logic;
        variable SYNCHRONIZE_v                  : std_logic;
        variable LOAD_INTERRUPTION_v            : std_logic;
    begin
        -- Carregamento da Instrução e de FLAGS
        INSTRUCTION_v              := INSTRUCTION_cs;
        INSTRUCTION_EN_v           := INSTRUCTION_EN_cs;
        EN_FLAGS_v                 := EN_FLAGS_cs;
        WEIGHT_BUSY_v              := WEIGHT_BUSY;
        MATRIX_BUSY_v              := MATRIX_BUSY;
        ACTIVATION_BUSY_v          := ACTIVATION_BUSY;
        LOAD_INT_BUSY_v            := LOAD_INT_BUSY;
        WEIGHT_RESOURCE_BUSY_v     := WEIGHT_RESOURCE_BUSY;
        MATRIX_RESOURCE_BUSY_v     := MATRIX_RESOURCE_BUSY;
        ACTIVATION_RESOURCE_BUSY_v := ACTIVATION_RESOURCE_BUSY;
        LOAD_INT_RESOURCE_BUSY_v   := LOAD_INT_RESOURCE_BUSY;

        if INSTRUCTION_EN_v = '1' then -- Se houver instrução a ser executada
            if EN_FLAGS_v(4) = '1' then -- Se a flag todas as unidades estiverem finalizadas
                -- Se alguma unidade estiver Ocupada
                if WEIGHT_RESOURCE_BUSY_v     = '1' 
                or MATRIX_RESOURCE_BUSY_v     = '1' 
                or ACTIVATION_RESOURCE_BUSY_v = '1' 
                or LOAD_INT_RESOURCE_BUSY_v   = '1' then
                    INSTRUCTION_RUNNING_v       := '1'; -- Então a Flag de instrução é ativada
                    WEIGHT_INSTRUCTION_EN_v     := '0';
                    MATRIX_INSTRUCTION_EN_v     := '0';
                    ACTIVATION_INSTRUCTION_EN_v := '0';
                    LOAD_INTERRUPTION_v         := '0';
                    SYNCHRONIZE_v               := '0';
                else
                    INSTRUCTION_RUNNING_v       := '0';
                    WEIGHT_INSTRUCTION_EN_v     := '0';
                    MATRIX_INSTRUCTION_EN_v     := '0';
                    ACTIVATION_INSTRUCTION_EN_v := '0';
                    LOAD_INTERRUPTION_v         := '0'; 
                    SYNCHRONIZE_v               := EN_FLAGS_v(4); -- Senão todos estão sincronizados
                end if;
            elsif EN_FLAGS_v(3) = '1' then 
                -- Se alguma unidade estiver Ocupada
                if WEIGHT_RESOURCE_BUSY_v     = '1' 
                or MATRIX_RESOURCE_BUSY_v     = '1' 
                or LOAD_INT_RESOURCE_BUSY_v   = '1' then
                    INSTRUCTION_RUNNING_v       := '1'; -- Então a Flag de instrução é ativada
                    WEIGHT_INSTRUCTION_EN_v     := '0';
                    MATRIX_INSTRUCTION_EN_v     := '0';
                    ACTIVATION_INSTRUCTION_EN_v := '0';
                    LOAD_INTERRUPTION_v         := '0';
                    SYNCHRONIZE_v               := '0';
                else
                    INSTRUCTION_RUNNING_v       := ACTIVATION_RESOURCE_BUSY_v or ACTIVATION_BUSY_v;
                    WEIGHT_INSTRUCTION_EN_v     := '0';
                    MATRIX_INSTRUCTION_EN_v     := '0';
                    ACTIVATION_INSTRUCTION_EN_v := '0';
                    LOAD_INTERRUPTION_v         := EN_FLAGS_v(3); 
                    SYNCHRONIZE_v               := '0'; -- Senão todos estão sincronizados
                end if;
            else
                -- Senão, se 
                if (WEIGHT_BUSY_v     = '1' and  EN_FLAGS_v(0) = '1')
                or (MATRIX_BUSY_v     = '1' and (EN_FLAGS_v(1) = '1' or EN_FLAGS_v(2) = '1')) -- Activation espera que a MMU termine
                or (ACTIVATION_BUSY_v = '1' and  EN_FLAGS_v(2) = '1')
                or (LOAD_INT_BUSY_v  = '1'  or  LOAD_INT_RESOURCE_BUSY_v = '1') then
                    INSTRUCTION_RUNNING_v       := '1'; -- Então a Flag de instrução é ativada
                    WEIGHT_INSTRUCTION_EN_v     := '0';
                    MATRIX_INSTRUCTION_EN_v     := '0';
                    ACTIVATION_INSTRUCTION_EN_v := '0';
                    LOAD_INTERRUPTION_v         := '0';
                    SYNCHRONIZE_v               := '0';
                else
                    INSTRUCTION_RUNNING_v       := '0'; -- Não Há Instrução sendo Realizada
                    -- As Flags de ativação são passadas 
                    WEIGHT_INSTRUCTION_EN_v     := EN_FLAGS_v(0);
                    MATRIX_INSTRUCTION_EN_v     := EN_FLAGS_v(1);
                    ACTIVATION_INSTRUCTION_EN_v := EN_FLAGS_v(2);
                    LOAD_INTERRUPTION_v         := '0';
                    SYNCHRONIZE_v               := '0';
                end if;
            end if;
        else -- Default
            INSTRUCTION_RUNNING_v       := '0';
            WEIGHT_INSTRUCTION_EN_v     := '0';
            MATRIX_INSTRUCTION_EN_v     := '0';
            ACTIVATION_INSTRUCTION_EN_v := '0';
            LOAD_INTERRUPTION_v         := '0';
            SYNCHRONIZE_v               := '0';
        end if;
        
        INSTRUCTION_RUNNING             <= INSTRUCTION_RUNNING_v;
        WEIGHT_INSTRUCTION_EN           <= WEIGHT_INSTRUCTION_EN_v;
        MATRIX_INSTRUCTION_EN           <= MATRIX_INSTRUCTION_EN_v;
        ACTIVATION_INSTRUCTION_EN       <= ACTIVATION_INSTRUCTION_EN_v;
        LOAD_INTERRUPTION_EN            <= LOAD_INTERRUPTION_v;
        SYNCHRONIZE                     <= SYNCHRONIZE_v;
    end process RUNNING_DETECT;
    
    -- Carrega as Instruções
    WEIGHT_INSTRUCTION      <= TO_WEIGHT_INSTRUCTION(INSTRUCTION_cs);
    MATRIX_INSTRUCTION      <= INSTRUCTION_cs;
    ACTIVATION_INSTRUCTION  <= INSTRUCTION_cs;

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                EN_FLAGS_cs <= (others => '0');
                INSTRUCTION_cs <= INIT_INSTRUCTION;
                INSTRUCTION_EN_cs <= '0';
            else -- Carrega uma nova instrução, caso não haja uma
                if INSTRUCTION_RUNNING = '0' and ENABLE = '1' then
                    EN_FLAGS_cs <= EN_FLAGS_ns;
                    INSTRUCTION_cs <= INSTRUCTION_ns;
                    INSTRUCTION_EN_cs <= INSTRUCTION_EN_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;