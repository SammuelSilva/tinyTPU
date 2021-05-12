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

--! @file ACTIVATION_CONTROL.vhdl
--! @author Jonas Fuhrmann

--! Este componente inclui a Unidade de Controle para as operações de ativações.
--! Esta unidade controla o fluxo de dados dos acumuladores, passando-os pelo componente de ativação e armazena o resultado no Unified Buffer.
--! As instruções serao executadas com delay, para que a multiplicação de matrizes possa ser terminada em tempo.


use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity ACTIVATION_CONTROL is
    generic(
        MATRIX_WIDTH        : natural := 8
    );
    port(
        CLK, RESET          :  in std_logic;
        ENABLE              :  in std_logic;

        INSTRUCTION         :  in INSTRUCTION_TYPE; --!< A instrução de ativação a ser executada (TIPO MAIS COMPLEXO, LINHA 75 TPU_PACK)
        INSTRUCTION_EN      :  in std_logic; --!< Enable para a Instrução.
        
        ACC_TO_ACT_ADDR     : out ACCUMULATOR_ADDRESS_TYPE; --!< Endereço para os acumuladores (Tamanho 16)
        ACTIVATION_FUNCTION : out ACTIVATION_BIT_TYPE; --!< O tipo de função de ativação a ser calculada (Tamanho 4)
        
        ACT_TO_BUF_ADDR     : out BUFFER_ADDRESS_TYPE; --!< Endereço para o Unified Buffer
        BUF_WRITE_EN        : out std_logic; --!< Flag de ativação de escrita para o Unified Buffer
        
        BUSY                : out std_logic;  --!< Se a Control Unit está ocupada, uma nova instrução não deve ser inserida.
        RESOURCE_BUSY       : out std_logic --!< O recurso esta em uso e a instrução nao esta completamente acabada.
    );
end entity ACTIVATION_CONTROL;

--! @brief The architecture of the activation control unit.
architecture BEH of ACTIVATION_CONTROL is

    -- CONTROL: 3 clock cylces
    -- MATRIX_MULTPLY_UNIT: MATRIX_WIDTH+2 clock cycles
    -- REGISTER_FILE: 7 clock cycles
    -- ACTIVATION: 3 clock cycles

    --> DELAYED: CONTROL + MMU
    type ACCUMULATOR_ADDRESS_ARRAY_TYPE is array(0 to 3+MATRIX_WIDTH+2-1) of ACCUMULATOR_ADDRESS_TYPE; -- Tipo com um conjunto de 18 std_logic_vector de tamanho 16
    --> DELAYED: CONTROL + MMU + REGISTER_FILE
    type ACTIVATION_BIT_ARRAY_TYPE is array(0 to 3+MATRIX_WIDTH+2+7-1) of ACTIVATION_BIT_TYPE; -- Tipo com um conjunto de 25 std_logic_vector de tamanho 4
    --> DELAYED: CONTROL + MMU + REGISTER_FILE + ACTIVATION
    type BUFFER_ADDRESS_ARRAY_TYPE is array(0 to 3+MATRIX_WIDTH+2+7+3-1) of BUFFER_ADDRESS_TYPE;-- Tipo com um conjunto de 28 std_logic_vector de tamanho 24

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
    for all : COUNTER use entity WORK.DSP_COUNTER_BUFF_ACC(BEH);
    
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
    for all : LOAD_COUNTER use entity WORK.DSP_LOAD_COUNTER_BUFF_ACC(BEH);
    

    -- Registradores temporarios para os Endereço dos acumuladores (tamanho 16)
    signal ACC_TO_ACT_ADDR_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal ACC_TO_ACT_ADDR_ns : ACCUMULATOR_ADDRESS_TYPE;
    
    -- Registradores temporarios para os Endereços no Unified buffer (Tamanho 24)
    signal ACT_TO_BUF_ADDR_cs : BUFFER_ADDRESS_TYPE := (others => '0');
    signal ACT_TO_BUF_ADDR_ns : BUFFER_ADDRESS_TYPE;
    
    -- Registradores temporarios para os Endereço dos acumuladores (tamnho 4)
    signal ACTIVATION_FUNCTION_cs : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_FUNCTION_ns : ACTIVATION_BIT_TYPE;
    
    -- Registradores temporarios para Flag de ativação de escrita para o Unified Buffer
    signal BUF_WRITE_EN_cs : std_logic := '0';
    signal BUF_WRITE_EN_ns : std_logic;
    
    -- Sinal que armazena a informação se uma instrução está ou nao sendo executada ainda
    signal RUNNING_cs : std_logic := '0';
    signal RUNNING_ns : std_logic;
    
    -- Pipeline das instruções 
    signal RUNNING_PIPE_cs : std_logic_vector(0 to 3+MATRIX_WIDTH+2+7+3-1) := (others => '0');
    signal RUNNING_PIPE_ns : std_logic_vector(0 to 3+MATRIX_WIDTH+2+7+3-1);
    
    -- Flags para ativaca de carregamento e Reset
    signal ACT_LOAD  : std_logic;
    signal ACT_RESET : std_logic;
    
    -- Delay do buffer para escrit no Weight Buffer, para os Sinais (Signed e Unsigned) e para o pipeline dos tipo de função de ativação a ser calculada
    signal BUF_WRITE_EN_DELAY_cs : std_logic_vector(0 to 2) := (others => '0');
    signal BUF_WRITE_EN_DELAY_ns : std_logic_vector(0 to 2);
    
    signal SIGNED_DELAY_cs : std_logic_vector(0 to 2) := (others => '0');
    signal SIGNED_DELAY_ns : std_logic_vector(0 to 2);
    
    signal ACTIVATION_PIPE0_cs : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_PIPE0_ns : ACTIVATION_BIT_TYPE;
    
    signal ACTIVATION_PIPE1_cs : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_PIPE1_ns : ACTIVATION_BIT_TYPE;
    
    signal ACTIVATION_PIPE2_cs : ACTIVATION_BIT_TYPE := (others => '0');
    signal ACTIVATION_PIPE2_ns : ACTIVATION_BIT_TYPE;
    
    -- LENGTH_COUNTER signals
    signal LENGTH_RESET     : std_logic;
    signal LENGTH_END_VAL   : LENGTH_TYPE;
    signal LENGTH_LOAD      : std_logic;
    signal LENGTH_EVENT     : std_logic;
    
    -- ADDRESS_COUNTER signals
    signal ADDRESS_LOAD     : std_logic;
    
    -- delay Registradores
    signal ACC_ADDRESS_DELAY_cs : ACCUMULATOR_ADDRESS_ARRAY_TYPE := (others => (others => '0'));
    signal ACC_ADDRESS_DELAY_ns : ACCUMULATOR_ADDRESS_ARRAY_TYPE;
    
    signal ACTIVATION_DELAY_cs  : ACTIVATION_BIT_ARRAY_TYPE := (others => (others => '0'));
    signal ACTIVATION_DELAY_ns  : ACTIVATION_BIT_ARRAY_TYPE;
    
    signal ACT_TO_BUF_DELAY_cs  : BUFFER_ADDRESS_ARRAY_TYPE := (others => (others => '0'));
    signal ACT_TO_BUF_DELAY_ns  : BUFFER_ADDRESS_ARRAY_TYPE;
        
    signal WRITE_EN_DELAY_cs    : std_logic_vector(0 to 3+MATRIX_WIDTH+2+7+3-1) := (others => '0');
    signal WRITE_EN_DELAY_ns    : std_logic_vector(0 to 3+MATRIX_WIDTH+2+7+3-1);

begin
    --< FIFO
    -- Os dados passam pelos registradores Delay, não passando a ultima posição vinda do "cs" e não modificando a primeira posição do receptor "ns".
    ACC_ADDRESS_DELAY_ns(1 to 3+MATRIX_WIDTH+2-1) <= ACC_ADDRESS_DELAY_cs(0 to 3+MATRIX_WIDTH+2-2);
    ACTIVATION_DELAY_ns(1 to 3+MATRIX_WIDTH+2+7-1) <= ACTIVATION_DELAY_cs(0 to 3+MATRIX_WIDTH+2+7-2);
    ACT_TO_BUF_DELAY_ns(1 to 3+MATRIX_WIDTH+2+7+3-1) <= ACT_TO_BUF_DELAY_cs(0 to 3+MATRIX_WIDTH+2+7+3-2);
    WRITE_EN_DELAY_ns(1 to 3+MATRIX_WIDTH+2+7+3-1) <= WRITE_EN_DELAY_cs(0 to 3+MATRIX_WIDTH+2+7+3-2);
    
    -- Os dados da ultima posição do Registradores Delay "cs" são enviados para saida, onde serão usados.
    ACC_TO_ACT_ADDR <= ACC_ADDRESS_DELAY_cs(3+MATRIX_WIDTH+2-1);
    ACTIVATION_FUNCTION <=ACTIVATION_DELAY_cs(3+MATRIX_WIDTH+2+7-1);
    ACT_TO_BUF_ADDR <= ACT_TO_BUF_DELAY_cs(3+MATRIX_WIDTH+2+7+3-1);
    BUF_WRITE_EN <= WRITE_EN_DELAY_cs(3+MATRIX_WIDTH+2+7+3-1);
    --< END 

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
        COUNT_EVENT => LENGTH_EVENT -- Sinal de aviso se o processo de contagem terminou
    );
    
    -- Port Map para o DSP_LOAD_COUNTER
    ADDRESS_COUNTER0_i : LOAD_COUNTER
    generic map(
        COUNTER_WIDTH => ACCUMULATOR_ADDRESS_WIDTH -- Tamanho 16
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        START_VAL   => INSTRUCTION.ACC_ADDRESS, -- Std_logic_vector que é o valor de inicio da contagem usando o endereço do acumulador
        LOAD        => ADDRESS_LOAD, -- Sinal de carregamento do valor inicial
        COUNT_VAL   => ACC_TO_ACT_ADDR_ns -- Valor da contagem retornado que é o endereço para um acumulador
    );
    
    ADDRESS_COUNTER1_i : LOAD_COUNTER
    generic map(
        COUNTER_WIDTH => BUFFER_ADDRESS_WIDTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        START_VAL   => INSTRUCTION.BUFFER_ADDRESS, -- Std_logic_vector que é o valor de inicio da contagem usando o endereço do buffer, provavelmente o UNIFIED BUFFER
        LOAD        => ADDRESS_LOAD,  -- Sinal de carregamento do valor inicial
        COUNT_VAL   => ACT_TO_BUF_ADDR_ns -- Valor da contagem retornado que é o endereço para o UNIFIED BUFFER
    );
    
    ACTIVATION_FUNCTION_ns <= INSTRUCTION.OP_CODE(3 downto 0); -- Carrega o restante da operação no activation_function
    
    -- Se o Activation_Function_cs for "0000" o valor inserido na posicao inicial da FIFO de ativação é "0000" senão é o valor que passou por 6 pipes (ACTIVATION_PIPE2_cs)
    -- Se  for "0" então o valor inserido em S_not_U_Delay_ns(0) é "0" senão o valor sera o ultimo do registrador SIGNED_DELAY_cs.
    -- Se o Buf_write_en_cs for "0" então o valor inserido em Write_EN-Delay_ns é "0" senão é o ultimo valor do registrador BUF_WRITE_EN_DELAY_cs.
    ACTIVATION_DELAY_ns(0)  <= "0000" when ACTIVATION_FUNCTION_cs = "0000" else ACTIVATION_PIPE2_cs; -- ACTIVATION_FUNCTION_cs <- ACTIVATION_FUNCTION_ns
    WRITE_EN_DELAY_ns(0)    <= '0' when BUF_WRITE_EN_cs = '0' else BUF_WRITE_EN_DELAY_cs(2); -- BUF_WRITE_EN_DELAY_cs <- BUF_WRITE_EN_DELAY_ns <- BUF_WRITE_EN_cs


    BUSY <= RUNNING_cs; -- Sinal avisando se a control unit está ocupada
    -- Atualização dos valores do Running_pipe, o ultimo valor é descartado
    RUNNING_PIPE_ns(0) <= RUNNING_cs;
    RUNNING_PIPE_ns(1 to 3+MATRIX_WIDTH+2+7+3-1) <= RUNNING_PIPE_cs(0 to 3+MATRIX_WIDTH+2+7+2-1);
    
    -- Inserção de um novo endereço de acumulador e do Unified Buffer na ultima posição das suas respectivas FIFO
    ACC_ADDRESS_DELAY_ns(0) <= ACC_TO_ACT_ADDR_cs;
    ACT_TO_BUF_DELAY_ns(0) <= ACT_TO_BUF_ADDR_cs;
    
    -- Os dados posteriores são passados para frente na FIFO
    BUF_WRITE_EN_DELAY_ns(1 to 2)   <= BUF_WRITE_EN_DELAY_cs(0 to 1);
    --SIGNED_DELAY_ns(1 to 2)         <= SIGNED_DELAY_cs(0 to 1);
    ACTIVATION_PIPE1_ns             <= ACTIVATION_PIPE0_cs;
    ACTIVATION_PIPE2_ns             <= ACTIVATION_PIPE1_cs;
    -- Os novos dados são inseridos em nas posiçoes inicias da suas FIFO
    BUF_WRITE_EN_DELAY_ns(0)        <= BUF_WRITE_EN_cs;
    ACTIVATION_PIPE0_ns             <= ACTIVATION_FUNCTION_cs;
    
    -- Função para verificar se uma instruçao foi finalizada e o Resource está liberado
    RESOURCE:
    process(RUNNING_cs, RUNNING_PIPE_cs) is
        variable RESOURCE_BUSY_v : std_logic;
    begin
        RESOURCE_BUSY_v := RUNNING_cs; -- Receb o sinal da instrução atual
            for i in 0 to 3+MATRIX_WIDTH+2+7+3-1 loop
                RESOURCE_BUSY_v := RESOURCE_BUSY_v or RUNNING_PIPE_cs(i);
            end loop;
        RESOURCE_BUSY <= RESOURCE_BUSY_v; -- Atualiza se o Resource está liberado ou nao
    end process RESOURCE;
    
    -- Recebe uma instrução, a flag da instrução, a flag que informa se a instrução esta terminada, e o sinal de aviso se a contagem terminou (DSP_COUNTER)
    CONTROL:
    process(INSTRUCTION, INSTRUCTION_EN, RUNNING_cs, LENGTH_EVENT) is
        variable INSTRUCTION_v      : INSTRUCTION_TYPE;
        variable INSTRUCTION_EN_v   : std_logic;
        variable RUNNING_cs_v       : std_logic;
        variable LENGTH_EVENT_v     : std_logic;
        
        variable RUNNING_ns_v       : std_logic;
        variable ADDRESS_LOAD_v     : std_logic;
        variable BUF_WRITE_EN_ns_v  : std_logic;
        variable LENGTH_LOAD_v      : std_logic;
        variable LENGTH_RESET_v     : std_logic;
        variable ACT_LOAD_v         : std_logic;
        variable ACT_RESET_v        : std_logic;
    begin
        INSTRUCTION_v       := INSTRUCTION;
        INSTRUCTION_EN_v    := INSTRUCTION_EN;
        RUNNING_cs_v        := RUNNING_cs;
        LENGTH_EVENT_v      := LENGTH_EVENT;
    
        -- Se a instrução tiver terminada
        if RUNNING_cs_v = '0' then
            if INSTRUCTION_EN_v = '1' then -- E o sinal para uma nova instrução estiver ativado
                RUNNING_ns_v        := '1'; -- A Flag de instrução sendo feita é ativada
                ADDRESS_LOAD_v      := '1'; -- A Flag para carregamento de um novo valor inicial para contagem é ativada (DSP_LOAD_COUNTER)
                BUF_WRITE_EN_ns_v   := '1'; -- A Flag para escrita no Unified Buffer é ativada
                LENGTH_LOAD_v       := '1'; -- A Flag para carregamento de um novo valor limite para contagem é ativada (DSP_COUNTER)
                LENGTH_RESET_v      := '1'; -- A Flag para resetar os registradores do DSP_COUNTER é ativada
                ACT_LOAD_v          := '1'; -- Ativa o carregamento de valores para ACTIVATION_FUNCTION_cs 
                ACT_RESET_v         := '0';
            else
                RUNNING_ns_v        := '0';
                ADDRESS_LOAD_v      := '0';
                BUF_WRITE_EN_ns_v   := '0';
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                ACT_LOAD_v          := '0';
                ACT_RESET_v         := '0';
            end if;
        else -- Caso a instrução não tenha terminado
            if LENGTH_EVENT_v = '1' then -- Caso o sinal de aviso da contagem ter terminado (DSP_COUNTER)
                RUNNING_ns_v        := '0';
                ADDRESS_LOAD_v      := '0';
                BUF_WRITE_EN_ns_v   := '0';
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                ACT_LOAD_v          := '0';
                ACT_RESET_v         := '1'; -- Reseta os registradores ACTIVATION_FUNCTION_cs 
            else -- Caso nao tenha
                RUNNING_ns_v        := '1'; -- A instrução nao foi terminada ainda
                ADDRESS_LOAD_v      := '0';
                BUF_WRITE_EN_ns_v   := '1'; -- E o Buffer de escrita é ativado
                LENGTH_LOAD_v       := '0';
                LENGTH_RESET_v      := '0';
                ACT_LOAD_v          := '0';
                ACT_RESET_v         := '0';
            end if;
        end if;
        
        RUNNING_ns          <=  RUNNING_ns_v;
        ADDRESS_LOAD        <=  ADDRESS_LOAD_v;
        BUF_WRITE_EN_ns     <=  BUF_WRITE_EN_ns_v;
        LENGTH_LOAD         <=  LENGTH_LOAD_v;
        LENGTH_RESET        <=  LENGTH_RESET_v;
        ACT_LOAD            <=  ACT_LOAD_v;
        ACT_RESET           <=  ACT_RESET_v;
    end process CONTROL;

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                BUF_WRITE_EN_cs <= '0';
                RUNNING_cs      <= '0';
                RUNNING_PIPE_cs <= (others => '0');
                ACC_TO_ACT_ADDR_cs <= (others => '0');
                ACT_TO_BUF_ADDR_cs <= (others => '0');
                BUF_WRITE_EN_DELAY_cs   <= (others => '0');
                ACTIVATION_PIPE0_cs     <= (others => '0');
                ACTIVATION_PIPE1_cs     <= (others => '0');
                ACTIVATION_PIPE2_cs     <= (others => '0');
                -- delay register
                ACC_ADDRESS_DELAY_cs    <= (others => (others => '0'));
                ACTIVATION_DELAY_cs     <= (others => (others => '0'));
                ACT_TO_BUF_DELAY_cs     <= (others => (others => '0'));
                WRITE_EN_DELAY_cs       <= (others => '0');
            else
                if ENABLE = '1' then
                    -- INICIO: Caminho da flag de ativação de escrita para o Unified Buffer
                    BUF_WRITE_EN_cs <= BUF_WRITE_EN_ns;
                    BUF_WRITE_EN_DELAY_cs   <= BUF_WRITE_EN_DELAY_ns;
                    WRITE_EN_DELAY_cs       <= WRITE_EN_DELAY_ns; -- delay register, responsavel pelo atraso
                    -- FIM

                    -- INICIO: Caminho para determinar se o recurso está indisponivel e se a control unit pode receber novas instruções
                    RUNNING_cs      <= RUNNING_ns;
                    RUNNING_PIPE_cs <= RUNNING_PIPE_ns;
                    -- FIM.

                    -- INICIO: Caminho para obter o Endereço para os acumuladores
                    ACC_TO_ACT_ADDR_cs <= ACC_TO_ACT_ADDR_ns;
                    ACC_ADDRESS_DELAY_cs    <= ACC_ADDRESS_DELAY_ns; -- delay register, responsavel pelo atraso
                    -- FIM.

                    -- INICIO: Caminho para obter o Endereço para o Unified Buffer
                    ACT_TO_BUF_ADDR_cs <= ACT_TO_BUF_ADDR_ns;
                    ACT_TO_BUF_DELAY_cs     <= ACT_TO_BUF_DELAY_ns;
                    -- FIM.
                    
                    -- INICIO: Pipeline para O tipo de função de ativação a ser calculada
                    ACTIVATION_PIPE0_cs     <= ACTIVATION_PIPE0_ns;
                    ACTIVATION_PIPE1_cs     <= ACTIVATION_PIPE1_ns;
                    ACTIVATION_PIPE2_cs     <= ACTIVATION_PIPE2_ns;
                    ACTIVATION_DELAY_cs     <= ACTIVATION_DELAY_ns; -- delay register, responsavel pelo atraso
                    -- FIM
                end if;
            end if;
            
            --  Caso o sinal de aviso da contagem ter terminado (DSP_COUNTER) os registradores devem ser zerados
            if ACT_RESET = '1' then
                ACTIVATION_FUNCTION_cs  <= (others => '0');
            else -- Senão continua carregando novos pedidos de função de ativação e se é signed ou nao.
                if ACT_LOAD = '1' then
                    ACTIVATION_FUNCTION_cs  <= ACTIVATION_FUNCTION_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;
