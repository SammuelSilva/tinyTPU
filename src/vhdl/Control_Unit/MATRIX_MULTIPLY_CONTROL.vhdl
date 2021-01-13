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

--! @file MATRIX_MULTIPLY_CONTROL.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui a Control Unit para a Matrix Multiply Operation
--! Systolic data vinda do Systolic data Setup é lida e "piped" para a Matrix Multiply Unit. Os pesos são ativados (preweights sao carregados em Registradores de peso)
--! Pesos são ativados em uma viagem ida e volta. Então as Weight Instructions e Matrix Multiply Instructions podem ser executadas em paralelo afim de calcula a sequencia de dados.
--! Os dados são armazenados nos acumuladores (Register File) e podem ser acumulados para dados consistentes ou sobrescritos.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;
    
entity MATRIX_MULTIPLY_CONTROL is
    generic(
        MATRIX_WIDTH    : natural := 14
    );
    port(
        CLK, RESET      :  in std_logic;
        ENABLE          :  in std_logic; 
        
        INSTRUCTION     :  in INSTRUCTION_TYPE; --!<  A instrução da Matrix Multiply a ser executada.
        INSTRUCTION_EN  :  in std_logic; --!< Flag da Instrução.
        
        BUF_TO_SDS_ADDR : out BUFFER_ADDRESS_TYPE; --!< Endereço para a leitura no Unified Buffer.
        BUF_READ_EN     : out std_logic; --!< Flag de ativação de leitura para o Unified Buffer.
        MMU_SDS_EN      : out std_logic; --!< Flag de ativação para Matrix Multiply Unit e o Systolic data Setup.
        MMU_SIGNED      : out std_logic; --!< Determina se o dado é Signed ou Unsigned.
        ACTIVATE_WEIGHT : out std_logic; --!< Flag de ativação para os PreWeights na Matrix Multiply Unit.
        
        ACC_ADDR        : out ACCUMULATOR_ADDRESS_TYPE; --!< Endereço para os Acumuladores (Register File).
        ACCUMULATE      : out std_logic; --!< Determina se um dado deve ser acumulado ou sobreescrito.
        ACC_ENABLE      : out std_logic; --!< Flag de ativação para acumuladores.
        
        BUSY                : out std_logic;  --!< Se a Control Unit está ocupada, uma nova instrução não deve ser inserida.
        RESOURCE_BUSY       : out std_logic --!< O recurso esta em uso e a instrução nao esta completamente acabada.
    );
end entity MATRIX_MULTIPLY_CONTROL;

--! @brief The architecture of the matric multiply unit.
architecture BEH of MATRIX_MULTIPLY_CONTROL is
    -- CONTROL: 3 clock cylces
    -- MATRIX_MULTPLY_UNIT: MATRIX_WIDTH+2 clock cycles

    --> DELAYED: CONTROL + MMU
    type ACCUMULATOR_ADDRESS_ARRAY_TYPE is array(0 to MATRIX_WIDTH-1 + 2 + 3) of ACCUMULATOR_ADDRESS_TYPE;
   
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
            COUNTER_WIDTH   : natural := 32;
            MATRIX_WIDTH    : natural := 14
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
    
    -- Registrador do Flag de ativação de leitura para o Unified Buffer.
    signal BUF_READ_EN_cs   : std_logic := '0';
    signal BUF_READ_EN_ns   : std_logic;
    
    -- Registrador do Flag de ativação para Matrix Multiply Unit e o Systolic data Setup.
    signal MMU_SDS_EN_cs    : std_logic := '0';
    signal MMU_SDS_EN_ns    : std_logic;
    
    -- Registrador para realizar um Delay nos dados para a Flag de ativação para Matrix Multiply Unit e o Systolic data Setup.
    signal MMU_SDS_DELAY_cs : std_logic_vector(0 to 2) := (others => '0');
    signal MMU_SDS_DELAY_ns : std_logic_vector(0 to 2);
    
    -- Registrador para determinar se o dado é Signed ou Unsigned.
    signal MMU_SIGNED_cs    : std_logic := '0';
    signal MMU_SIGNED_ns    : std_logic;
    
    -- ?????
    signal SIGNED_PIPE_cs   : std_logic_vector(0 to 2) := (others => '0');
    signal SIGNED_PIPE_ns   : std_logic_vector(0 to 2);
    
    -- WEIGHT_COUNTER_WIDTH é um valor natural maior que o log2 da MATRIX_WIDTH-1 (Caso MATRIX_WIDHT-1 = 13, então o valor é 4)
    constant WEIGHT_COUNTER_WIDTH   : natural := natural(ceil(log2(real(MATRIX_WIDTH-1))));

    constant ADD_ONE         : unsigned(WEIGHT_COUNTER_WIDTH-1 downto 0) := (WEIGHT_COUNTER_WIDTH-1 downto 1 => '0')&'1';
    -- Registradores que armazenam o Endereço do peso para a Matrix Multiply Unit
    signal WEIGHT_COUNTER_cs        : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0) := (others => '0');
    signal WEIGHT_COUNTER_ns        : std_logic_vector(WEIGHT_COUNTER_WIDTH-1 downto 0);
    
    -- ????
    signal WEIGHT_PIPE_cs   : std_logic_vector(0 to 2) := (others => '0');
    signal WEIGHT_PIPE_ns   : std_logic_vector(0 to 2);
    
    -- ????
    signal ACTIVATE_WEIGHT_DELAY_cs : std_logic_vector(0 to 2) := (others => '0');
    signal ACTIVATE_WEIGHT_DELAY_ns : std_logic_vector(0 to 2);
    
    -- Registrador para a Flag de ativação para acumuladores.
    signal ACC_ENABLE_cs    : std_logic := '0';
    signal ACC_ENABLE_ns    : std_logic;

    -- Sinal que armazena a informação se uma instrução está ou nao sendo executada ainda
    signal RUNNING_cs       : std_logic := '0';
    signal RUNNING_ns       : std_logic;
    
    -- Pipeline das instruções 
    signal RUNNING_PIPE_cs : std_logic_vector(0 to MATRIX_WIDTH+2+3-1) := (others => '0');
    signal RUNNING_PIPE_ns : std_logic_vector(0 to MATRIX_WIDTH+2+3-1);
    
    -- Registradores que Determina se um dado deve ser acumulado ou sobreescrito.
    signal ACCUMULATE_cs    : std_logic := '0';
    signal ACCUMULATE_ns    : std_logic;
        
    -- Pipeline para
    signal BUF_ADDR_PIPE_cs : BUFFER_ADDRESS_TYPE := (others => '0');
    signal BUF_ADDR_PIPE_ns : BUFFER_ADDRESS_TYPE;
    
    -- Pipeline para
    signal ACC_ADDR_PIPE_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal ACC_ADDR_PIPE_ns : ACCUMULATOR_ADDRESS_TYPE;
    
    -- Pipeline para
    signal BUF_READ_PIPE_cs : std_logic_vector(0 to 2) := (others => '0');
    signal BUF_READ_PIPE_ns : std_logic_vector(0 to 2);
    
    -- Pipeline para
    signal MMU_SDS_EN_PIPE_cs : std_logic_vector(0 to 2) := (others => '0');
    signal MMU_SDS_EN_PIPE_ns : std_logic_vector(0 to 2);
    
    -- Pipeline para
    signal ACC_EN_PIPE_cs : std_logic_vector(0 to 2) := (others => '0');
    signal ACC_EN_PIPE_ns : std_logic_vector(0 to 2);
    
    -- Pipeline para
    signal ACCUMULATE_PIPE_cs : std_logic_vector(0 to 2) := (others => '0');
    signal ACCUMULATE_PIPE_ns : std_logic_vector(0 to 2);
    
    signal ACC_LOAD  : std_logic;
    signal ACC_RESET : std_logic;
    
    signal ACC_ADDR_DELAY_cs : ACCUMULATOR_ADDRESS_ARRAY_TYPE := (others => (others => '0'));
    signal ACC_ADDR_DELAY_ns : ACCUMULATOR_ADDRESS_ARRAY_TYPE;
    
    signal ACCUMULATE_DELAY_cs : std_logic_vector(0 to MATRIX_WIDTH-1 + 2 + 3) := (others => '0');
    signal ACCUMULATE_DELAY_ns : std_logic_vector(0 to MATRIX_WIDTH-1 + 2 + 3);
    
    signal ACC_EN_DELAY_cs : std_logic_vector(0 to MATRIX_WIDTH-1 + 2 + 3) := (others => '0');
    signal ACC_EN_DELAY_ns : std_logic_vector(0 to MATRIX_WIDTH-1 + 2 + 3);
    
    -- LENGTH_COUNTER signals
    signal LENGTH_RESET     : std_logic;
    signal LENGTH_END_VAL   : LENGTH_TYPE;
    signal LENGTH_LOAD      : std_logic;
    signal LENGTH_EVENT     : std_logic;
    
    -- ADDRESS_COUNTER signals
    signal ADDRESS_LOAD     : std_logic;
    
    -- WEIGHT_COUNTER reset
    signal WEIGHT_RESET     : std_logic;
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
        COUNT_EVENT => LENGTH_EVENT -- Sinal de aviso se o processo de contagem terminou
    );

    -- Port Map para o DSP_LOAD_COUNTER
    ADDRESS_COUNTER0_i : entity work.DSP_LOAD_COUNTER(ACC_COUNTER)
    generic map(
        COUNTER_WIDTH => ACCUMULATOR_ADDRESS_WIDTH,
        MATRIX_WIDTH  => MATRIX_WIDTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        START_VAL   => INSTRUCTION.ACC_ADDRESS, -- Std_logic_vector que é o valor de inicio da contagem usando o endereço do acumulador
        LOAD        => ADDRESS_LOAD,  -- Sinal de carregamento do valor inicial
        COUNT_VAL   => ACC_ADDR_PIPE_ns -- Valor da contagem retornado que é o endereço para o Acumulador 
    
    );
    
    -- Port Map para o DSP_LOAD_COUNTER
    ADDRESS_COUNTER1_i : LOAD_COUNTER
    generic map(
        COUNTER_WIDTH => BUFFER_ADDRESS_WIDTH
    )
    port map(
        CLK         => CLK,
        RESET       => RESET,
        ENABLE      => ENABLE, -- Ativação do processo de contagem
        START_VAL   => INSTRUCTION.BUFFER_ADDRESS, -- Std_logic_vector que é o valor de inicio da contagem usando o endereço do peso, provavelmente o UNIFIED BUFFER
        LOAD        => ADDRESS_LOAD,  -- Sinal de carregamento do valor inicial
        COUNT_VAL   => BUF_ADDR_PIPE_ns -- Valor da contagem retornado que é o endereço para o UNIFIED BUFFER
    );
    
    -- Recebe o sinal se o valor no endereço de memoria deve ser acumulado ou sobrescrito
    ACCUMULATE_ns <= INSTRUCTION.OP_CODE(1);
    
    -- O Endereço do dado a ser lido do UNIFIED BUFFER vem do COUNT_VAL do DSP_LOAD_COUNTER
    BUF_TO_SDS_ADDR         <= BUF_ADDR_PIPE_cs;

    --Insere um novo Endereço para um acumulador na posição 0 do DELAY.
    ACC_ADDR_DELAY_ns(0)    <= ACC_ADDR_PIPE_cs;
    
    -- O Endereço para um acumulador da ultima posição do DELAY é enviado para a saida.
    ACC_ADDR <= ACC_ADDR_DELAY_cs(MATRIX_WIDTH-1 + 2 + 3);
  
    -- Atualização das posições dos dados na FIFO
    BUF_READ_PIPE_ns(1 to 2)    <= BUF_READ_PIPE_cs(0 to 1);
    MMU_SDS_EN_PIPE_ns(1 to 2)  <= MMU_SDS_EN_PIPE_cs(0 to 1);
    ACC_EN_PIPE_ns(1 to 2)      <= ACC_EN_PIPE_cs(0 to 1);
    ACCUMULATE_PIPE_ns(1 to 2)  <= ACCUMULATE_PIPE_cs(0 to 1);
    SIGNED_PIPE_ns(1 to 2)      <= SIGNED_PIPE_cs(0 to 1);
    WEIGHT_PIPE_ns(1 to 2)      <= WEIGHT_PIPE_cs(0 to 1);
    
    -- Inserção de novos valores na FIFO
    BUF_READ_PIPE_ns(0)    <= BUF_READ_EN_cs; -- O Endereço do dado a ser lido do UNIFIED BUFFER
    MMU_SDS_EN_PIPE_ns(0)  <= MMU_SDS_EN_cs; -- Flag de ativação para Matrix Multiply Unit e o Systolic data Setup.
    ACC_EN_PIPE_ns(0)      <= ACC_ENABLE_cs; -- Flag de ativação para acumuladores.
    ACCUMULATE_PIPE_ns(0)  <= ACCUMULATE_cs; -- Determina se um dado deve ser acumulado ou sobreescrito.
    SIGNED_PIPE_ns(0)      <= MMU_SIGNED_cs; --  Determina se o dado é Signed ou Unsigned.
    WEIGHT_PIPE_ns(0)      <= '1' when WEIGHT_COUNTER_cs = std_logic_vector(to_unsigned(0, WEIGHT_COUNTER_WIDTH)) else '0'; --  Flag de ativação para os PreWeights na Matrix Multiply Unit.
    
    MMU_SIGNED_ns <= INSTRUCTION.OP_CODE(0); -- Recebeo Sinal do Dado (Signed ou Unsigned)
    
    -- Carrega o endereço a ser lido do unified buffer (Se tiver instrução ativa)
    BUF_READ_EN             <= '0' when BUF_READ_EN_cs = '0' else BUF_READ_PIPE_cs(2);

    -- Carrega as demais flags (Descrição acima) para os registradores de DELAY (Se tiver instrução ativa)
    MMU_SDS_DELAY_ns(0)     <= '0' when MMU_SDS_EN_cs = '0' else MMU_SDS_EN_PIPE_cs(2);
    ACC_EN_DELAY_ns(0)      <= '0' when ACC_ENABLE_cs = '0' else ACC_EN_PIPE_cs(2);
    ACCUMULATE_DELAY_ns(0)  <= '0' when ACCUMULATE_cs = '0' else ACCUMULATE_PIPE_cs(2);

    -- Caso instruções estiverem sendo feitas carrega o sinal da instrução - INSTRUCTION.OP_CODE(0) -
    MMU_SIGNED <= '0' when MMU_SDS_DELAY_cs(2) = '0' else SIGNED_PIPE_cs(2);
    
    ACTIVATE_WEIGHT_DELAY_ns(0) <= WEIGHT_PIPE_cs(2); -- Carregamento da flag de ativação para os PreWeights nos registratores de DELAY
    -- FIFO DO ACTIVATE_WEIGHT_DELAY
    ACTIVATE_WEIGHT_DELAY_ns(1 to 2) <= ACTIVATE_WEIGHT_DELAY_cs(0 to 1);
    ACTIVATE_WEIGHT <= '0' when MMU_SDS_DELAY_cs(2) = '0' else ACTIVATE_WEIGHT_DELAY_cs(2); -- Caso instruções estiverem sendo feitas carrega a flag de ativação dos preweights
    
    -- Envia os Dados com "Atrasos" para a saida
    ACC_ENABLE <= ACC_EN_DELAY_cs(MATRIX_WIDTH-1 + 2 + 3);
    ACCUMULATE <= ACCUMULATE_DELAY_cs(MATRIX_WIDTH-1 + 2 + 3);
    MMU_SDS_EN <= MMU_SDS_DELAY_cs(2);
    
    BUSY <= RUNNING_cs; -- Sinal avisando se a control unit está ocupada
    -- Atualização dos valores do Running_pipe, o ultimo valor é descartado
    RUNNING_PIPE_ns(0) <= RUNNING_cs;
    RUNNING_PIPE_ns(1 to MATRIX_WIDTH+2+3-1) <= RUNNING_PIPE_cs(0 to MATRIX_WIDTH+2+2-1);
    
    -- Atualização dos valores da FIFO 
    ACC_ADDR_DELAY_ns(1 to MATRIX_WIDTH-1 + 2 + 3)      <= ACC_ADDR_DELAY_cs(0 to MATRIX_WIDTH-1 + 2 +2);
    ACCUMULATE_DELAY_ns(1 to MATRIX_WIDTH-1 + 2 + 3)    <= ACCUMULATE_DELAY_cs(0 to MATRIX_WIDTH-1 + 2 + 2);
    ACC_EN_DELAY_ns(1 to MATRIX_WIDTH-1 + 2 + 3)        <= ACC_EN_DELAY_cs(0 to MATRIX_WIDTH-1 + 2 + 2);
    MMU_SDS_DELAY_ns(1 to 2)                            <= MMU_SDS_DELAY_cs(0 to 1);
    
    -- Função para verificar se uma instruçao foi finalizada e o Recurso está liberado
    RESOURCE:
    process(RUNNING_cs, RUNNING_PIPE_cs) is
        variable RESOURCE_BUSY_v : std_logic;
    begin
        RESOURCE_BUSY_v := RUNNING_cs;
        --if RESOURCE_BUSY_v = '1' then
            for i in 0 to MATRIX_WIDTH+2+3-1 loop
                RESOURCE_BUSY_v := RESOURCE_BUSY_v or RUNNING_PIPE_cs(i);
            end loop;
        --end if;
        RESOURCE_BUSY <= RESOURCE_BUSY_v;
    end process RESOURCE;

    -- Anda pelo endereço do peso de "Um em Um" até MATRIX_WIDTH
    WEIGHT_COUNTER:
    process(WEIGHT_COUNTER_cs) is
    begin
        if WEIGHT_COUNTER_cs = std_logic_vector(to_unsigned(MATRIX_WIDTH-1, WEIGHT_COUNTER_WIDTH)) then
            WEIGHT_COUNTER_ns <= (others => '0');
        else
            WEIGHT_COUNTER_ns <= std_logic_vector(unsigned(WEIGHT_COUNTER_cs) + ADD_ONE);
        end if;
    end process WEIGHT_COUNTER;
    
    CONTROL:
    process(INSTRUCTION, INSTRUCTION_EN, RUNNING_cs, LENGTH_EVENT) is
        variable INSTRUCTION_v      : INSTRUCTION_TYPE;
        variable INSTRUCTION_EN_v   : std_logic;
        variable RUNNING_cs_v       : std_logic;
        variable LENGTH_EVENT_v     : std_logic;
        
        variable RUNNING_ns_v       : std_logic;
        variable ADDRESS_LOAD_v     : std_logic;
        variable BUF_READ_EN_ns_v   : std_logic;
        variable MMU_SDS_EN_ns_v    : std_logic;      
        variable ACC_ENABLE_ns_v    : std_logic;
        variable LENGTH_LOAD_v      : std_logic;
        variable LENGTH_RESET_v     : std_logic;
        variable ACC_LOAD_v         : std_logic;
        variable ACC_RESET_v        : std_logic;
        variable WEIGHT_RESET_v     : std_logic;
    begin
        INSTRUCTION_v       := INSTRUCTION; -- Instrução atual
        INSTRUCTION_EN_v    := INSTRUCTION_EN; -- Sinal de que possui uma instrução para ser carregada
        RUNNING_cs_v        := RUNNING_cs; -- Sinal de que uma instrução pode estar sendo executada
        LENGTH_EVENT_v      := LENGTH_EVENT; -- Sinal de que um evento de parada foi atingido
    
        if RUNNING_cs_v = '0' then -- Se nao tiver nenhuma instrução funcionando
            if INSTRUCTION_EN_v = '1' then -- Se uma nova instrução estiver pronta ativa ela
                RUNNING_ns_v    := '1';
                ADDRESS_LOAD_v  := '1';
                BUF_READ_EN_ns_v:= '1';
                MMU_SDS_EN_ns_v := '1';
                ACC_ENABLE_ns_v := '1';
                LENGTH_LOAD_v   := '1';
                LENGTH_RESET_v  := '1';
                ACC_LOAD_v      := '1';
                ACC_RESET_v     := '0';
                WEIGHT_RESET_v  := '1';
            else -- Senão não faz nada
                RUNNING_ns_v    := '0';
                ADDRESS_LOAD_v  := '0';
                BUF_READ_EN_ns_v:= '0';
                MMU_SDS_EN_ns_v := '0';
                ACC_ENABLE_ns_v := '0';
                LENGTH_LOAD_v   := '0';
                LENGTH_RESET_v  := '0';
                ACC_LOAD_v      := '0';
                ACC_RESET_v     := '0'; 
                WEIGHT_RESET_v  := '0';                
            end if;
        else -- Se a instrução não tiver terminado ainda
            if LENGTH_EVENT_v = '1' then -- E o valor maximo foi atingido pelo contador
                RUNNING_ns_v    := '0';
                ADDRESS_LOAD_v  := '0';
                BUF_READ_EN_ns_v:= '0';
                MMU_SDS_EN_ns_v := '0';
                ACC_ENABLE_ns_v := '0';
                LENGTH_LOAD_v   := '0';
                LENGTH_RESET_v  := '0';
                ACC_LOAD_v      := '0'; 
                ACC_RESET_v     := '1'; -- Reset é ativado
                WEIGHT_RESET_v  := '0';
            else -- Senão
                RUNNING_ns_v    := '1'; -- Continua executando a instruçao
                ADDRESS_LOAD_v  := '0';
                BUF_READ_EN_ns_v:= '1'; -- Ativacao de Endereço a ser lido
                MMU_SDS_EN_ns_v := '1'; -- Ativacao da Flag de ativação para Matrix Multiply Unit e o Systolic data Setup.
                ACC_ENABLE_ns_v := '1'; -- Ativacao da Flag de ativação para acumuladores
                LENGTH_LOAD_v   := '0';
                LENGTH_RESET_v  := '0';
                ACC_LOAD_v      := '0';
                ACC_RESET_v     := '0';
                WEIGHT_RESET_v  := '0';
            end if;
        end if;
        
        RUNNING_ns      <= RUNNING_ns_v;
        ADDRESS_LOAD    <= ADDRESS_LOAD_v; -- SInal para zerar o contador (DSP_LOAD_COUNTER)
        BUF_READ_EN_ns  <= BUF_READ_EN_ns_v;
        MMU_SDS_EN_ns   <= MMU_SDS_EN_ns_v;
        ACC_ENABLE_ns   <= ACC_ENABLE_ns_v;
        LENGTH_LOAD     <= LENGTH_LOAD_v; -- SInal para o carregamento de um novo valor limite (DSP_COUNTER)
        LENGTH_RESET    <= LENGTH_RESET_v; -- Sinal para resetar os valores no DSP_COUNTER
        ACC_LOAD        <= ACC_LOAD_v; -- Permite o Pipe do ACCUMATOR e do MMU_SIGNED
        ACC_RESET       <= ACC_RESET_v; -- Reseta os registradores
        WEIGHT_RESET    <= WEIGHT_RESET_v; -- Reseta o WEIGHT_COUNTER_cs
    end process CONTROL;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                BUF_READ_EN_cs  <= '0';
                MMU_SDS_EN_cs   <= '0';
                ACC_ENABLE_cs   <= '0';
                RUNNING_cs      <= '0';
                RUNNING_PIPE_cs <= (others => '0');
                BUF_ADDR_PIPE_cs    <= (others => '0');
                ACC_ADDR_PIPE_cs    <= (others => '0');
                ACC_ADDR_DELAY_cs   <= (others => (others => '0'));
                ACCUMULATE_DELAY_cs <= (others => '0');
                ACC_EN_DELAY_cs     <= (others => '0');
                MMU_SDS_DELAY_cs    <= (others => '0');
                SIGNED_PIPE_cs      <= (others => '0');
                WEIGHT_PIPE_cs      <= (others => '0');
                ACTIVATE_WEIGHT_DELAY_cs <= (others => '0');
            else
                if ENABLE = '1' then
                    BUF_READ_EN_cs  <= BUF_READ_EN_ns;
                    MMU_SDS_EN_cs   <= MMU_SDS_EN_ns;
                    ACC_ENABLE_cs   <= ACC_ENABLE_ns;
                    RUNNING_cs      <= RUNNING_ns;
                    RUNNING_PIPE_cs <= RUNNING_PIPE_ns;
                    BUF_ADDR_PIPE_cs    <= BUF_ADDR_PIPE_ns;
                    ACC_ADDR_PIPE_cs    <= ACC_ADDR_PIPE_ns;
                    ACC_ADDR_DELAY_cs   <= ACC_ADDR_DELAY_ns;
                    ACCUMULATE_DELAY_cs <= ACCUMULATE_DELAY_ns;
                    ACC_EN_DELAY_cs     <= ACC_EN_DELAY_ns;
                    MMU_SDS_DELAY_cs    <= MMU_SDS_DELAY_ns;
                    SIGNED_PIPE_cs      <= SIGNED_PIPE_ns;
                    WEIGHT_PIPE_cs      <= WEIGHT_PIPE_ns;
                    ACTIVATE_WEIGHT_DELAY_cs <= ACTIVATE_WEIGHT_DELAY_ns;
                end if;
            end if;
            
            if ACC_RESET = '1' then -- Reseta os registradores
                ACCUMULATE_cs   <= '0';
                BUF_READ_PIPE_cs    <= (others => '0');
                MMU_SDS_EN_PIPE_cs  <= (others => '0');
                ACC_EN_PIPE_cs      <= (others => '0');
                ACCUMULATE_PIPE_cs  <= (others => '0');
                MMU_SIGNED_cs       <= '0';
            else
                if ACC_LOAD = '1' then -- Carrega os valores dos dados(Acumular/Sobrescrever e Signed/Unsigned)
                    ACCUMULATE_cs   <= ACCUMULATE_ns;
                    MMU_SIGNED_cs   <= MMU_SIGNED_ns;
                end if;
                
                if ENABLE = '1' then -- Permite o trafego dos dados pelos pipes
                    BUF_READ_PIPE_cs    <= BUF_READ_PIPE_ns;
                    MMU_SDS_EN_PIPE_cs  <= MMU_SDS_EN_PIPE_ns;
                    ACC_EN_PIPE_cs      <= ACC_EN_PIPE_ns;
                    ACCUMULATE_PIPE_cs  <= ACCUMULATE_PIPE_ns;
                end if;
            end if;
            
            if WEIGHT_RESET = '1' then -- Reseta o contador da flag para carregamento do preweight
                WEIGHT_COUNTER_cs   <= (others => '0');
            else
                if ENABLE = '1' then -- Aumenta o contador para carregamento do preweight
                    WEIGHT_COUNTER_cs   <= WEIGHT_COUNTER_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;
