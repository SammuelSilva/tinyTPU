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

--! @file WEIGHT_CONTROL.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui a Control Unit para o carregamento dos pesos.
--! Pesos são lidos do Weight Buffer e são fornecidos de forma sequencial na Matrix Multiply Unit.
--! Se a Control Unit chegar ao final dos PreWeight Registers da Matrix Multiply Unit, ela recomeça a carregar o proximo conjunto de valores.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;
    
entity WEIGHT_CONTROL is
    generic(
        MATRIX_WIDTH            : natural := 8;
        MATRIX_HALF             : natural := (8-1)/NUMBER_OF_MULT
    );
    port(
        CLK, RESET              :  in std_logic;
        ENABLE                  :  in std_logic;
    
        INSTRUCTION             :  in WEIGHT_INSTRUCTION_TYPE; --!< A instrução do Peso a ser executada.
        INSTRUCTION_EN          :  in std_logic; --!< Flag de ativação da instrução.
        
        WEIGHT_READ_EN          : out std_logic; --!< Flag de Leitura para o Weight Buffer.
        WEIGHT_BUFFER_ADDRESS   : out WEIGHT_ADDRESS_TYPE; --!< Endereço de leitura para o Weight Buffer.
        
        LOAD_WEIGHT             : out std_logic; --!< Flag de Carregamento de Peso para a Matrix Multiply Unit.
        WEIGHT_ADDRESS          : out BYTE_TYPE; --!< Endereço do peso para a Matrix Multiply Unit.
        
        WEIGHT_SIGNED           : out std_logic; --!< Determina se os pesosa são signed ou unsigned.
                
        BUSY                    : out std_logic; --!< Se a Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        RESOURCE_BUSY           : out std_logic  --!< O recurso esta em uso e a instrução não esta totalmente terminada.
    );
end entity WEIGHT_CONTROL;

--! @brief The architecture of the weight control unit.
architecture BEH of WEIGHT_CONTROL is
    -- So é resetado quando o valor final é atingido. 
    -- GERA UM SINAL DE EVENTO
    component COUNTER is
        generic(
            COUNTER_WIDTH   : natural := 32
        );
        port(
            CLK, RESET  : in  std_logic;
            ENABLE      : in  std_logic;
            
            END_VAL     : in  std_logic_vector(COUNTER_WIDTH-1 downto 0); --!< O Valor final do componente em que sera emitido um Sinal de evento
            LOAD        : in  std_logic; --!< Sinal para carregar o valor final.
            
            COUNT_VAL   : out std_logic_vector(COUNTER_WIDTH-1 downto 0);--!< O valor atual do contador. 
            
            COUNT_EVENT : out std_logic--!< O evento, que sera ativado quando o valor final for atingido. 
        );
    end component COUNTER;
    for all : COUNTER use entity WORK.DSP_COUNTER(BEH);
    
    -- O mesmo contador de ACC_LOAD_COUNTER porem este so pode ser resetado atraves do LOAD.
    component LOAD_COUNTER is
        generic(
            COUNTER_WIDTH   : natural := 32
        );
        port(
            CLK, RESET  : in  std_logic;
            ENABLE      : in  std_logic;
            
            START_VAL   : in  std_logic_vector(COUNTER_WIDTH-1 downto 0);  --!< O valor inicial do contador.
            LOAD        : in  std_logic;  --!< Flag de carregamento para o valor inicial.
            
            COUNT_VAL   : out std_logic_vector(COUNTER_WIDTH-1 downto 0) --!< O valor atual do contador.
        );
    end component LOAD_COUNTER;
    for all : LOAD_COUNTER use entity WORK.DSP_LOAD_COUNTER(BEH);

    -- Registradores da Flag de Leitura para o Weight Buffer.
    signal WEIGHT_READ_EN_cs        : std_logic := '0';
    signal WEIGHT_READ_EN_ns        : std_logic;
    
    -- Registradores da Flag de Carregamento de Peso para a Matrix Multiply Unit.
    signal LOAD_WEIGHT_cs           : std_logic_vector(0 to 2) := (others => '0');
    signal LOAD_WEIGHT_ns           : std_logic_vector(0 to 2);
    
    -- Registradores que carregam o sinal que Determina se os pesos são signed ou unsigned.
    signal WEIGHT_SIGNED_cs         : std_logic := '0';
    signal WEIGHT_SIGNED_ns         : std_logic;
    
    -- Pipeline para Carregar o sinal da operação
    signal SIGNED_PIPE_cs           : std_logic_vector(0 to 2) := (others => '0');
    signal SIGNED_PIPE_ns           : std_logic_vector(0 to 2);
    
    -- Sinais para definir se uma instrução deve ser carregada ou resetada
    signal SIGNED_LOAD              : std_logic;
    signal SIGNED_RESET             : std_logic;

    -- WEIGHT_COUNTER_WIDTH é um valor natural maior que o log2 da MATRIX_WIDTH-1 (Caso MATRIX_WIDHT-1 = 13, então o valor é 4)
    constant WEIGHT_COUNTER_WIDTH   : natural := natural(ceil(log2(real(MATRIX_WIDTH-1))));
    
    constant ADD_ONE         : unsigned(WEIGHT_COUNTER_WIDTH-1 downto 0) := (WEIGHT_COUNTER_WIDTH-1 downto 1 => '0')&'1';
    -- Registradores que armazenam o Endereço do peso para a Matrix Multiply Unit
    signal WEIGHT_ADDRESS_cs        : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_ADDRESS_ns        : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    -- Pipeline para o endereço do Peso
    signal WEIGHT_PIPE0_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE0_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    signal WEIGHT_PIPE1_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE1_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    signal WEIGHT_PIPE2_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE2_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    signal WEIGHT_PIPE3_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE3_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    signal WEIGHT_PIPE4_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE4_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    signal WEIGHT_PIPE5_cs          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_PIPE5_ns          : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    -- Registrador que armazena O endereço do peso no Weight Buffer (é obtido pelo contador COUNT_VAL do DSP_LOAD_COUNTER)
    signal BUFFER_PIPE_cs           : WEIGHT_ADDRESS_TYPE := (others => '0');
    signal BUFFER_PIPE_ns           : WEIGHT_ADDRESS_TYPE;
    
    -- Pipeline de ativação da leitura de peso, valor inserido no pipe0 vem do processo Control
    signal READ_PIPE0_cs            : std_logic := '0';
    signal READ_PIPE0_ns            : std_logic;
    
    signal READ_PIPE1_cs            : std_logic := '0';
    signal READ_PIPE1_ns            : std_logic;
    
    signal READ_PIPE2_cs            : std_logic := '0';
    signal READ_PIPE2_ns            : std_logic;
    
    -- Sinal que armazena a informação se uma instrução está ou nao sendo executada ainda
    signal RUNNING_cs : std_logic := '0';
    signal RUNNING_ns : std_logic;

    -- Pipeline das instruções 
    signal RUNNING_PIPE_cs : std_logic_vector(0 to 2) := (others => '0');
    signal RUNNING_PIPE_ns : std_logic_vector(0 to 2);
    
    -- LENGTH_COUNTER signals
    signal LENGTH_RESET     : std_logic;
    signal LENGTH_LOAD      : std_logic;
    signal LENGTH_EVENT     : std_logic;
    
    -- ADDRESS_COUNTER signals
    signal ADDRESS_LOAD     : std_logic;
begin
    -- Port Map para o DSP_COUNTER
    LENGTH_COUNTER_i : COUNTER
    generic map(
        COUNTER_WIDTH => LENGTH_WIDTH -- Tamanho 32
    )
    port map(
        CLK         => CLK,
        RESET       => LENGTH_RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        END_VAL     => INSTRUCTION.CALC_LENGTH, -- Busca o tamanho da instrução
        LOAD        => LENGTH_LOAD, -- Sinal de aviso para o carregamento do valor a ser atingido pelo contador
        COUNT_VAL   => open,
        COUNT_EVENT => LENGTH_EVENT -- Sinal de aviso se o processo de contagem terminou
    );
    
    -- Port Map para o DSP_LOAD_COUNTER
    ADDRESS_COUNTER_i : LOAD_COUNTER
    generic map(
        COUNTER_WIDTH => WEIGHT_ADDRESS_WIDTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        START_VAL   => INSTRUCTION.WEIGHT_ADDRESS, -- Std_logic_vector que é o valor de inicio da contagem usando o endereço do peso, provavelmente o WEIGHT BUFFER
        LOAD        => ADDRESS_LOAD,  -- Sinal de carregamento do valor inicial
        COUNT_VAL   => BUFFER_PIPE_ns -- Valor da contagem retornado que é o endereço para o WEIGHT BUFFER
    );

    -- Pipeline de ativação da leitura de peso, valor inserido no pipe0 vem do processo Control
        -- WEIGHT_READ_EN_cs <- WEIGHT_READ_EN_ns <- WEIGHT_READ_EN_ns_v (CONTROL) - Basicamente controla tudo.
    READ_PIPE0_ns   <= WEIGHT_READ_EN_cs;
    READ_PIPE1_ns   <= READ_PIPE0_cs;
    READ_PIPE2_ns   <= READ_PIPE1_cs;
    WEIGHT_READ_EN  <= '0' when WEIGHT_READ_EN_cs = '0' else READ_PIPE2_cs; -- WEIGHT_READ_EN_cs é o valor mais atual da flag sendo assim ele define se há um dado lido novo
    
    -- Leitura do Weight buffer leva 3 ciclos de clock
        -- e.g: LOAD_WEIGHT_ns = [A,B,C] => [X,B,C] => [X,C,B]
        -- e.g: LOAD_WEIGHT_cs = [C,B,A] => A --> LOAD_WEIGHT
        -- Provavelmente as 3 instruções abaixo ocorre de baixo para cima
    LOAD_WEIGHT_ns(0)       <= '0' when WEIGHT_READ_EN_cs = '0' else READ_PIPE2_cs;
    LOAD_WEIGHT_ns(1 to 2)  <= LOAD_WEIGHT_cs(0 to 1);
    LOAD_WEIGHT             <= LOAD_WEIGHT_cs(2);
    
    -- Carrega o sinal da operação se o SIGNED_LOAD = 1 (Valor que vem do processo Control) então WEIGHT_SIGNED_cs = WEIGHT_SIGNED_ns
        -- Provavelmente as 3 instruções abaixo ocorre de baixo para cima
    WEIGHT_SIGNED_ns    <= INSTRUCTION.OP_CODE(0);
    SIGNED_PIPE_ns(0)   <= WEIGHT_SIGNED_cs; --  WEIGHT_SIGNED_cs <- WEIGHT_SIGNED_ns <- INSTRUCTION.OP_CODE(0)
    SIGNED_PIPE_ns(1)   <= SIGNED_PIPE_cs(0);
    SIGNED_PIPE_ns(2)   <= SIGNED_PIPE_cs(1);
    WEIGHT_SIGNED       <= '0' when LOAD_WEIGHT_cs(2) = '0' else SIGNED_PIPE_cs(2); -- Carrega o ultimo valor 
    
    -- Pipeline do Endereço dos pesos
    WEIGHT_PIPE0_ns <= WEIGHT_ADDRESS_cs; -- WEIGHT_ADDRESS_cs <- WEIGHT_ADDRESS_ns
    WEIGHT_PIPE1_ns <= WEIGHT_PIPE0_cs;
    WEIGHT_PIPE2_ns <= WEIGHT_PIPE1_cs;
    WEIGHT_PIPE3_ns <= WEIGHT_PIPE2_cs;
    WEIGHT_PIPE4_ns <= WEIGHT_PIPE3_cs;
    WEIGHT_PIPE5_ns <= WEIGHT_PIPE4_cs;
    WEIGHT_ADDRESS(WEIGHT_COUNTER_WIDTH-1 downto 0) <= WEIGHT_PIPE5_cs; -- copia o tamanho certo do pipe 
    WEIGHT_ADDRESS(BYTE_WIDTH-1 downto WEIGHT_COUNTER_WIDTH) <= (others => '0'); -- Preenche o restante com 0
    
    WEIGHT_BUFFER_ADDRESS <= BUFFER_PIPE_cs; -- O endereço do peso no Weight Buffer é obtido pelo contador COUNT_VAL do DSP_LOAD_COUNTER

    BUSY <= RUNNING_cs;
    RUNNING_PIPE_ns(0) <= RUNNING_cs;
    RUNNING_PIPE_ns(1 to 2) <= RUNNING_PIPE_cs(0 to 1);
    
    -- Função para verificar se uma instruçao foi finalizada e o Recurso está liberado
    RESOURCE:
    process(RUNNING_cs, RUNNING_PIPE_cs) is
        variable RESOURCE_BUSY_v : std_logic;
    begin
        RESOURCE_BUSY_v := RUNNING_cs; -- Recebe o sinal da instrução atual
        --if RESOURCE_BUSY_v = '0' then
            for i in 0 to 2 loop
                RESOURCE_BUSY_v := RESOURCE_BUSY_v or RUNNING_PIPE_cs(i);
            end loop;
        --end if;
        RESOURCE_BUSY <= RESOURCE_BUSY_v;
    end process RESOURCE;
    
    -- Anda pelo endereço do peso de "Um em Um" até MATRIX_WIDTH
    WEIGHT_ADDRESS_COUNTER:
    process(WEIGHT_ADDRESS_cs) is
    begin
        if WEIGHT_ADDRESS_cs = std_logic_vector(to_unsigned(MATRIX_HALF, WEIGHT_COUNTER_WIDTH)) then
            WEIGHT_ADDRESS_ns <= (others => '0');
        else
            WEIGHT_ADDRESS_ns <= std_logic_vector(unsigned(WEIGHT_ADDRESS_cs) + ADD_ONE); --ADD_TWO?
        end if;
    end process WEIGHT_ADDRESS_COUNTER;
        
    CONTROL:
    process(INSTRUCTION_EN, RUNNING_cs, LENGTH_EVENT) is
        variable INSTRUCTION_EN_v           : std_logic;
        variable RUNNING_cs_v               : std_logic;
        variable LENGTH_EVENT_v             : std_logic;
        
        variable RUNNING_ns_v               : std_logic;
        variable ADDRESS_LOAD_v             : std_logic;
        variable WEIGHT_ADDRESS_ns_v        : BYTE_TYPE;
        variable WEIGHT_READ_EN_ns_v        : std_logic;
        variable LENGTH_LOAD_v              : std_logic;
        variable LENGTH_RESET_v             : std_logic;
        variable SIGNED_LOAD_v              : std_logic;
        variable SIGNED_RESET_v             : std_logic;
    begin
        INSTRUCTION_EN_v    := INSTRUCTION_EN; -- Sinal de que possui uma instrução para ser carregada
        RUNNING_cs_v        := RUNNING_cs; -- Sinal de que uma instrução pode estar sendo executada
        LENGTH_EVENT_v      := LENGTH_EVENT; -- Sinal de que um evento de parada foi atingido
        
        --synthesis translate_off
        if INSTRUCTION_EN_v = '1' and RUNNING_cs_v = '1' then
            report "New Instruction shouldn't be feeded while processing! WEIGHT_CONTROL.vhdl" severity warning;
        end if;
        --synthesis translate_on
    
        if RUNNING_cs_v = '0' then -- Se nao há instruções sendo realizadas então pode carregar uma instrução nova
            if INSTRUCTION_EN_v = '1' then -- Se INSTRUCTION_EN for 1 é carregada uma nova instrução
                RUNNING_ns_v        := '1';
                ADDRESS_LOAD_v      := '1';
                WEIGHT_READ_EN_ns_v := '1';
                LENGTH_LOAD_v       := '1';
                LENGTH_RESET_v      := '1';
                SIGNED_LOAD_v       := '1';
                SIGNED_RESET_v      := '0';
            else
                RUNNING_ns_v        := '0';
                ADDRESS_LOAD_v      := '0';            
                WEIGHT_READ_EN_ns_v := '0';
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                SIGNED_LOAD_v       := '0';
                SIGNED_RESET_v      := '0';
            end if;
        else -- Se RUNNING_CS for diferente de 1 mas um Sinal de Evento foi atingido no DSP_COUNTER então os valores serão resetados
            if LENGTH_EVENT_v = '1' then
                RUNNING_ns_v        := '0';
                ADDRESS_LOAD_v      := '0';
                WEIGHT_READ_EN_ns_v := '0';
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                SIGNED_LOAD_v       := '0';
                SIGNED_RESET_v      := '1'; -- SINAL PARA RESET 
            else -- Caso contrario continua carregando pesos
                RUNNING_ns_v        := '1';
                ADDRESS_LOAD_v      := '0';            
                WEIGHT_READ_EN_ns_v := '1';
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                SIGNED_LOAD_v       := '0';
                SIGNED_RESET_v      := '0';
            end if;
        end if;
        
        RUNNING_ns <= RUNNING_ns_v;
        ADDRESS_LOAD <= ADDRESS_LOAD_v; -- SInal para zerar o contador (DSP_LOAD_COUNTER)
        WEIGHT_READ_EN_ns <= WEIGHT_READ_EN_ns_v; -- Sinal para leitura de pesos
        LENGTH_LOAD <= LENGTH_LOAD_v; -- SInal para o carregamento de um novo valor limite (DSP_COUNTER)
        LENGTH_RESET <= LENGTH_RESET_v; -- Sinal para resetar os valores no DSP_COUNTER e zerar o weight_address
        SIGNED_LOAD <= SIGNED_LOAD_v; -- Sinal para a busca de SINAL na Instrução
        SIGNED_RESET <= SIGNED_RESET_v; -- Sinal para zerar os pipes
    end process CONTROL;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                WEIGHT_READ_EN_cs   <= '0';
                LOAD_WEIGHT_cs      <= (others => '0');
                RUNNING_cs          <= '0';
                RUNNING_PIPE_cs     <= (others => '0');
                WEIGHT_PIPE0_cs     <= (others => '0');
                WEIGHT_PIPE1_cs     <= (others => '0');
                WEIGHT_PIPE2_cs     <= (others => '0');
                WEIGHT_PIPE3_cs     <= (others => '0');
                WEIGHT_PIPE4_cs     <= (others => '0');
                WEIGHT_PIPE5_cs     <= (others => '0');
                BUFFER_PIPE_cs      <= (others => '0');
                SIGNED_PIPE_cs      <= (others => '0');
            else
                if ENABLE = '1' then
                    WEIGHT_READ_EN_cs   <= WEIGHT_READ_EN_ns;
                    LOAD_WEIGHT_cs      <= LOAD_WEIGHT_ns;
                    RUNNING_cs          <= RUNNING_ns;
                    RUNNING_PIPE_cs     <= RUNNING_PIPE_ns;
                    WEIGHT_PIPE0_cs     <= WEIGHT_PIPE0_ns;
                    WEIGHT_PIPE1_cs     <= WEIGHT_PIPE1_ns;
                    WEIGHT_PIPE2_cs     <= WEIGHT_PIPE2_ns;
                    WEIGHT_PIPE3_cs     <= WEIGHT_PIPE3_ns;
                    WEIGHT_PIPE4_cs     <= WEIGHT_PIPE4_ns;
                    WEIGHT_PIPE5_cs     <= WEIGHT_PIPE5_ns;
                    BUFFER_PIPE_cs      <= BUFFER_PIPE_ns;
                    SIGNED_PIPE_cs      <= SIGNED_PIPE_ns;
                end if;
            end if;
            
            if LENGTH_RESET = '1' then -- Reseta o WEIGTH_ADDRESS
                WEIGHT_ADDRESS_cs <= (others => '0');
            else
                if ENABLE = '1' then
                    WEIGHT_ADDRESS_cs <= WEIGHT_ADDRESS_ns;
                end if;
            end if;
            
            if SIGNED_RESET = '1' then -- Reseta os pipes
                WEIGHT_SIGNED_cs    <= '0';
                READ_PIPE0_cs       <= '0';
                READ_PIPE1_cs       <= '0';
                READ_PIPE2_cs       <= '0';
            else
                if SIGNED_LOAD = '1' then -- carrega um novo sinal
                    WEIGHT_SIGNED_cs    <= WEIGHT_SIGNED_ns;
                end if;
                
                if ENABLE = '1' then
                    -- Pipeline que carregam o valor da flag WEIGHT_READ_EN
                    READ_PIPE0_cs       <= READ_PIPE0_ns;
                    READ_PIPE1_cs       <= READ_PIPE1_ns;
                    READ_PIPE2_cs       <= READ_PIPE2_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;