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

--! @file TPU_CORE.vhdl
--! @author Jonas Fuhrmann
--! Este componente é a principal parte da TPU
--! Esta parte contem todos os componentes, que sao necessarios para calculos e controles.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity TPU_CORE is
    generic(
        MATRIX_WIDTH            : natural := 8; --!< A Largura da MMU e dos barramentos
        WEIGHT_BUFFER_DEPTH     : natural := 32768; --!< A "profundidade" do Weight Buffer
        UNIFIED_BUFFER_DEPTH    : natural := 4096 --!< A "Profundidade" do Unified Buffer
    );
    port(
        CLK, RESET              : in  std_logic;
        ENABLE                  : in  std_logic;
    
        WEIGHT_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Porta de escrita do Host para weight buffer
        WEIGHT_ADDRESS          : in  WEIGHT_ADDRESS_TYPE; --!< Endereço do Host para o weight buffer.
        WEIGHT_ENABLE           : in  std_logic; --!< Ativador do Host para o weight buffer.
        WEIGHT_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Ativador do Host para escrita especifica no weight buffer.
            
        BUFFER_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Porta de escrita do Host para unified buffer.
        BUFFER_READ_PORT        : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Host read port for the unified buffer.
        BUFFER_ADDRESS          : in  BUFFER_ADDRESS_TYPE; --!< Endereço do Host para o unified buffer.
        BUFFER_ENABLE           : in  std_logic; --!< Ativador do Host para o unified buffer.
        BUFFER_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Ativador do Host para escrita especifica no unified buffer.
        
        INSTRUCTION_PORT        : in  INSTRUCTION_TYPE; --!< Porta de Escrita para as instruções
        INSTRUCTION_ENABLE      : in  std_logic; --!< Ativador de Escrita para instruções
        
        BUSY                    : out std_logic; --!< A TPU ainda está ocupada e não pode receber nenhuma instrução.
        SYNCHRONIZE             : out std_logic; --!< Interrupção de sincronização.
        LOAD_INTERRUPTION       : out std_logic
    );
end entity TPU_CORE;

--! @brief The architecture of the TPU core.
architecture BEH of TPU_CORE is
    component WEIGHT_BUFFER is
        generic(
            MATRIX_WIDTH    : natural := 8;
            -- How many tiles can be saved
            TILE_WIDTH      : natural := 32768
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            -- Port0
            ADDRESS0        : in  WEIGHT_ADDRESS_TYPE;
            EN0             : in  std_logic;
            WRITE_EN0       : in  std_logic;
            WRITE_PORT0     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            READ_PORT0      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            -- Port1
            ADDRESS1        : in  WEIGHT_ADDRESS_TYPE;
            EN1             : in  std_logic;
            WRITE_EN1       : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            WRITE_PORT1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            READ_PORT1      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component WEIGHT_BUFFER;
    for all : WEIGHT_BUFFER use entity WORK.WEIGHT_BUFFER(BEH);
    
    signal WEIGHT_ADDRESS0      : WEIGHT_ADDRESS_TYPE;
    signal WEIGHT_EN0           : std_logic;
    signal WEIGHT_READ_PORT0    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_READ_PORT1    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    component UNIFIED_BUFFER is
        generic(
            MATRIX_WIDTH    : natural := 8;
            -- How many tiles can be saved
            TILE_WIDTH      : natural := 4096
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            -- Master port - overrides other ports
            MASTER_ADDRESS      : in  BUFFER_ADDRESS_TYPE;
            MASTER_EN           : in  std_logic;
            MASTER_WRITE_EN     : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            MASTER_WRITE_PORT   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            MASTER_READ_PORT    : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            -- Port0
            ADDRESS0        : in  BUFFER_ADDRESS_TYPE;
            EN0             : in  std_logic;
            READ_PORT0      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            -- Port1
            ADDRESS1        : in  BUFFER_ADDRESS_TYPE;
            EN1             : in  std_logic;
            WRITE_EN1       : in  std_logic;
            WRITE_PORT1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component UNIFIED_BUFFER;
    for all : UNIFIED_BUFFER use entity WORK.UNIFIED_BUFFER(BEH);
    
    signal BUFFER_ADDRESS0      : BUFFER_ADDRESS_TYPE;
    signal BUFFER_EN0           : std_logic;
    signal BUFFER_READ_PORT0    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal BUFFER_ADDRESS1      : BUFFER_ADDRESS_TYPE;
    signal BUFFER_WRITE_EN1     : std_logic;
    signal BUFFER_WRITE_PORT1   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    component SYSTOLIC_DATA_SETUP is
        generic(
            MATRIX_WIDTH  : natural := 8
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            DATA_INPUT      : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            SYSTOLIC_OUTPUT : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component SYSTOLIC_DATA_SETUP;
    for all : SYSTOLIC_DATA_SETUP use entity WORK.SYSTOLIC_DATA_SETUP(BEH);
    
    signal SDS_SYSTOLIC_OUTPUT  : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    component MATRIX_MULTIPLY_UNIT is
        generic(
            MATRIX_WIDTH    : natural := 8
        );
        port(
            CLK, RESET      : in  std_logic;
            ENABLE          : in  std_logic;
            
            WEIGHT_DATA0    : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_DATA1    : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            --WEIGHT_SIGNED   : in  std_logic;
            SYSTOLIC_DATA   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            --SYSTOLIC_SIGNED : in  std_logic;
            
            ACTIVATE_WEIGHT : in  std_logic; -- Activates the loaded weights sequentially
            LOAD_WEIGHT     : in  std_logic; -- Preloads one column of weights with WEIGHT_DATA
            WEIGHT_ADDRESS  : in  BYTE_TYPE; -- Addresses up to 256 columns of preweights
            
            RESULT_DATA     : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component MATRIX_MULTIPLY_UNIT;
    for all : MATRIX_MULTIPLY_UNIT use entity WORK.MATRIX_MULTIPLY_UNIT(BEH);
    
    --signal MMU_WEIGHT_SIGNED    : std_logic;
    --signal MMU_SYSTOLIC_SIGNED  : std_logic;
    
    signal MMU_ACTIVATE_WEIGHT  : std_logic;
    signal MMU_LOAD_WEIGHT      : std_logic;
    signal MMU_WEIGHT_ADDRESS   : BYTE_TYPE;
    
    signal MMU_RESULT_DATA      : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    component REGISTER_FILE is
        generic(
            MATRIX_WIDTH    : natural := 8;
            REGISTER_DEPTH  : natural := 512
        );
        port(
            CLK, RESET          : in  std_logic;
            ENABLE              : in  std_logic;
            
            WRITE_ADDRESS       : in  ACCUMULATOR_ADDRESS_TYPE;
            WRITE_PORT          : in  WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WRITE_ENABLE        : in  std_logic;
            
            ACCUMULATE          : in  std_logic;
            
            READ_ADDRESS        : in  ACCUMULATOR_ADDRESS_TYPE;
            READ_PORT           : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component REGISTER_FILE;
    for all : REGISTER_FILE use entity WORK.REGISTER_FILE(BEH);
    
    signal REG_WRITE_ADDRESS    : ACCUMULATOR_ADDRESS_TYPE;
    signal REG_WRITE_EN         : std_logic;
    
    signal REG_ACCUMULATE       : std_logic;
    signal REG_READ_ADDRESS     : ACCUMULATOR_ADDRESS_TYPE;
    signal REG_READ_PORT        : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    component ACTIVATION is
        generic(
            MATRIX_WIDTH        : natural := 8
        );
        port(
            CLK, RESET          : in  std_logic;
            ENABLE              : in  std_logic;
            
            ACTIVATION_FUNCTION : in  ACTIVATION_BIT_TYPE;
            --SIGNED_NOT_UNSIGNED : in  std_logic;
            
            ACTIVATION_INPUT    : in  WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            ACTIVATION_OUTPUT   : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component ACTIVATION;
    for all : ACTIVATION use entity WORK.ACTIVATION(BEH);
    
    signal ACTIVATION_FUNCTION  : ACTIVATION_BIT_TYPE;
    signal ACTIVATION_SIGNED    : std_logic;
        
    component WEIGHT_CONTROL is
        generic(
            MATRIX_WIDTH            : natural := 8
        );
        port(
            CLK, RESET              :  in std_logic;
            ENABLE                  :  in std_logic;
        
            INSTRUCTION             :  in WEIGHT_INSTRUCTION_TYPE;
            INSTRUCTION_EN          :  in std_logic;
            
            WEIGHT_READ_EN          : out std_logic;
            WEIGHT_BUFFER_ADDRESS   : out WEIGHT_ADDRESS_TYPE;
            
            LOAD_WEIGHT             : out std_logic;
            WEIGHT_ADDRESS          : out BYTE_TYPE;
            
            --WEIGHT_SIGNED           : out std_logic;
                        
            BUSY                    : out std_logic;
            RESOURCE_BUSY           : out std_logic
        );
    end component WEIGHT_CONTROL;
    for all : WEIGHT_CONTROL use entity WORK.WEIGHT_CONTROL(BEH);
    
    signal WEIGHT_INSTRUCTION       : WEIGHT_INSTRUCTION_TYPE;
    signal WEIGHT_INSTRUCTION_EN    : std_logic;
    
    signal WEIGHT_READ_EN           : std_logic;
    
    signal WEIGHT_RESOURCE_BUSY     : std_logic;
    
    component MATRIX_MULTIPLY_CONTROL is
        generic(
            MATRIX_WIDTH    : natural := 8
        );
        port(
            CLK, RESET      :  in std_logic;
            ENABLE          :  in std_logic; 
            
            INSTRUCTION     :  in INSTRUCTION_TYPE;
            INSTRUCTION_EN  :  in std_logic;
            
            BUF_TO_SDS_ADDR : out BUFFER_ADDRESS_TYPE;
            BUF_READ_EN     : out std_logic;
            MMU_SDS_EN      : out std_logic;
            --MMU_SIGNED      : out std_logic;
            ACTIVATE_WEIGHT : out std_logic;
            
            ACC_ADDR        : out ACCUMULATOR_ADDRESS_TYPE;
            ACCUMULATE      : out std_logic;
            ACC_ENABLE      : out std_logic;
            
            BUSY            : out std_logic;
            RESOURCE_BUSY   : out std_logic
        );
    end component MATRIX_MULTIPLY_CONTROL;
    for all : MATRIX_MULTIPLY_CONTROL use entity WORK.MATRIX_MULTIPLY_CONTROL(BEH);
    
    signal MMU_INSTRUCTION      : INSTRUCTION_TYPE;
    signal MMU_INSTRUCTION_EN   : std_logic;
    
    signal BUF_READ_EN          : std_logic;
    signal MMU_SDS_EN           : std_logic;    

    signal MMU_RESOURCE_BUSY    : std_logic;
    
    component ACTIVATION_CONTROL is
        generic(
            MATRIX_WIDTH        : natural := 8
        );
        port(
            CLK, RESET          :  in std_logic;
            ENABLE              :  in std_logic;
            
            INSTRUCTION         :  in INSTRUCTION_TYPE;
            INSTRUCTION_EN      :  in std_logic;
            
            ACC_TO_ACT_ADDR     : out ACCUMULATOR_ADDRESS_TYPE;
            ACTIVATION_FUNCTION : out ACTIVATION_BIT_TYPE;
            --SIGNED_NOT_UNSIGNED : out std_logic;
            
            ACT_TO_BUF_ADDR     : out BUFFER_ADDRESS_TYPE;
            BUF_WRITE_EN        : out std_logic;
            
            BUSY                : out std_logic;
            RESOURCE_BUSY       : out std_logic
        );
    end component ACTIVATION_CONTROL;
    for all : ACTIVATION_CONTROL use entity WORK.ACTIVATION_CONTROL(BEH);
    
    signal ACTIVATION_INSTRUCTION       : INSTRUCTION_TYPE;
    signal ACTIVATION_INSTRUCTION_EN    : std_logic;
    
    signal ACTIVATION_RESOURCE_BUSY     : std_logic;
    
    component LOOK_AHEAD_BUFFER is
        port(
            CLK, RESET          :  in std_logic;
            ENABLE              :  in std_logic;
            
            INSTRUCTION_BUSY    :  in std_logic;
            
            INSTRUCTION_INPUT   :  in INSTRUCTION_TYPE;
            INSTRUCTION_WRITE   :  in std_logic;
            
            INSTRUCTION_OUTPUT  : out INSTRUCTION_TYPE;
            INSTRUCTION_READ    : out std_logic
        );
    end component LOOK_AHEAD_BUFFER;
    for all : LOOK_AHEAD_BUFFER use entity WORK.LOOK_AHEAD_BUFFER(BEH);
    
    signal INSTRUCTION_BUSY     : std_logic;
    
    signal INSTRUCTION_OUTPUT   : INSTRUCTION_TYPE;
    signal INSTRUCTION_READ     : std_logic;
    
    component LOAD_INTERRUPTION_CONTROL is
        generic(
            MATRIX_WIDTH            :  natural := 8;
            WEIGHT_BUFFER_DEPTH     :  natural := 32768
        );
        port(
            CLK, RESET              :  in std_logic;
            ENABLE                  :  in std_logic;
    
            INSTRUCTION_EN          :  in std_logic;
    
            BUSY                    :  out std_logic;
            RESOURCE_BUSY           :  out std_logic
        );
    end component LOAD_INTERRUPTION_CONTROL;
    for all : LOAD_INTERRUPTION_CONTROL use entity WORK.LOAD_INTERRUPTION_CONTROL(BEH);

    signal LOAD_INT_RESOURCE_BUSY   : std_logic;

    component CONTROL_COORDINATOR is
        port(
            CLK, RESET                  :  in std_logic;
            ENABLE                      :  in std_logic;
                
            INSTRUCTION                 :  in INSTRUCTION_TYPE;
            INSTRUCTION_EN              :  in std_logic;
            
            BUSY                        : out std_logic;
            
            WEIGHT_BUSY                 :  in std_logic;
            WEIGHT_RESOURCE_BUSY        :  in std_logic;
            WEIGHT_INSTRUCTION          : out WEIGHT_INSTRUCTION_TYPE;
            WEIGHT_INSTRUCTION_EN       : out std_logic;
            
            MATRIX_BUSY                 :  in std_logic;
            MATRIX_RESOURCE_BUSY        :  in std_logic;
            MATRIX_INSTRUCTION          : out INSTRUCTION_TYPE;
            MATRIX_INSTRUCTION_EN       : out std_logic;
            
            ACTIVATION_BUSY             :  in std_logic;
            ACTIVATION_RESOURCE_BUSY    :  in std_logic;
            ACTIVATION_INSTRUCTION      : out INSTRUCTION_TYPE;
            ACTIVATION_INSTRUCTION_EN   : out std_logic;
            
            LOAD_INT_BUSY               :  in std_logic;
            LOAD_INT_RESOURCE_BUSY      :  in std_logic;
            LOAD_INTERRUPTION_EN        : out std_logic;

            SYNCHRONIZE                 : out std_logic
        );
    end component CONTROL_COORDINATOR;
    for all : CONTROL_COORDINATOR use entity WORK.CONTROL_COORDINATOR(BEH);
    
    signal CONTROL_BUSY             : std_logic;
    signal WEIGHT_BUSY              : std_logic;
    signal MATRIX_BUSY              : std_logic;
    signal ACTIVATION_BUSY          : std_logic;
    signal LOAD_INT_BUSY            : std_logic;
    signal LOAD_INTERRUPTION_EN     : std_logic;
begin

    WEIGHT_BUFFER_i : WEIGHT_BUFFER
    generic map(
        MATRIX_WIDTH    => MATRIX_WIDTH, --< Tamanho 8
        TILE_WIDTH      => WEIGHT_BUFFER_DEPTH --< Tamanho 69632
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
            
        -- Port0    
        ADDRESS0        => WEIGHT_ADDRESS0, -- Recebe o endereço que vem de WEIGHT_BUFFER_ADDRESS (Componente WEIGHT_CONTROL)
        EN0             => WEIGHT_EN0, -- Recebe o ativador de leitura do endereço que vem de WEIGHT_READ_EN (Componente WEIGHT_CONTROL)
        WRITE_EN0       => '0', -- Inicia com 0 o ativador de escrita
        WRITE_PORT0     => (others => (others => '0')), -- Na porta do 0 do endereço de escrita
        READ_PORT0      => WEIGHT_READ_PORT0, -- Saida da com o endereço de leitura do WEIGHT_BUFFER 
        -- Port1    
        ADDRESS1        => WEIGHT_ADDRESS, -- Recebe endereço do Input do TPU_CORE
        EN1             => WEIGHT_ENABLE, -- Recebe o ativador do Input do TPU_CORE
        WRITE_EN1       => WEIGHT_WRITE_ENABLE, -- Recebe o ativador do Input do TPU_CORE
        WRITE_PORT1     => WEIGHT_WRITE_PORT, -- Recebe o endereço de escrita do Input do TPU_CORE
        READ_PORT1      => WEIGHT_READ_PORT1 -- Porta Ignorada pois não é usada
        );
    
    UNIFIED_BUFFER_i : UNIFIED_BUFFER
    generic map(
        MATRIX_WIDTH    => MATRIX_WIDTH,
        TILE_WIDTH      => UNIFIED_BUFFER_DEPTH
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
        
        -- Master port - overrides other ports
        MASTER_ADDRESS      => BUFFER_ADDRESS, -- Recebe o Endereço do Input do TPU_CORE
        MASTER_EN           => BUFFER_ENABLE, -- Recebe o Ativador do Input do TPU_CORE
        MASTER_WRITE_EN     => BUFFER_WRITE_ENABLE, -- Recebe o Ativador do Input do TPU_CORE
        MASTER_WRITE_PORT   => BUFFER_WRITE_PORT, -- Recebe o Endereço do Input do TPU_CORE
        MASTER_READ_PORT    => BUFFER_READ_PORT, -- A saida do Endereço do Unified Buffer esta conectada com a porta de saida da TPU
        -- Port0
        ADDRESS0        => BUFFER_ADDRESS0, -- Recebe o endereço de leitura da saida do BUF_TO_SDS_ADDR (Componente MATRIX_MULTIPLY_CONTROL)
        EN0             => BUFFER_EN0, -- Recebe o ativador de leitura do BUF_READ_EN (Componente MATRIX_MULTIPLY_CONTROL)
        READ_PORT0      => BUFFER_READ_PORT0, -- Saida do dado lido que sera levado para o Systolic Data Setup
        -- Port1
        ADDRESS1        => BUFFER_ADDRESS1, -- Recebe o endereço para os acumuladores da saida da porta ACT_TO_BUF_ADDR (Componente Activation Control)
        EN1             => BUFFER_WRITE_EN1, -- Recebe o ativador de escrita na porta 1 do unified buffer da porta de saida BUF_WRITE_EN (Componente Activation Control)
        WRITE_EN1       => BUFFER_WRITE_EN1, -- Recebe o ativador de escrita no unified buffer da porta de saida BUF_WRITE_EN (Componente Activation Control)
        WRITE_PORT1     => BUFFER_WRITE_PORT1 -- Recebe do ACTIVATION_OUTPUT a resposta depois da aplicacao da funçao de ativação feita (Componente Activation) e escreve na memoria
    );
    
    SYSTOLIC_DATA_SETUP_i : SYSTOLIC_DATA_SETUP
    generic map(
        MATRIX_WIDTH
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,      
        ENABLE          => ENABLE,

        DATA_INPUT      => BUFFER_READ_PORT0, -- Recebe o Output READ_PORT0 (Componente UNIFIED_BUFFER) a ser atrasado
        SYSTOLIC_OUTPUT => SDS_SYSTOLIC_OUTPUT -- Saida do dado Diagonalizado (Atrasado)
    );
    
    MATRIX_MULTIPLY_UNIT_i : MATRIX_MULTIPLY_UNIT
    generic map(
        MATRIX_WIDTH   
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,         
        
        WEIGHT_DATA0    => WEIGHT_READ_PORT0, -- Recebe o peso do READ_PORT0 (Componente WEIGHT_BUFFER)
        WEIGHT_DATA1    => WEIGHT_READ_PORT1,
        --WEIGHT_SIGNED   => MMU_WEIGHT_SIGNED, -- Recebe a flag se o peso tem sinal ou nao do WEIGHT_SIGNED (Componente WEIGHT BUFFER)
        SYSTOLIC_DATA   => SDS_SYSTOLIC_OUTPUT, -- Recebe o dado Diagonalizado (Atrasado) do SYSTOLIC_OUTPUT (Componente SYSTOLIC_DATA_SETUP)
        --SYSTOLIC_SIGNED => MMU_SYSTOLIC_SIGNED, -- Recebe se o dado diagonalizado tem sinal ou nao do MMU_SIGNED (Componente MATRIX_MULTIPLY_CONTROL)
        
        ACTIVATE_WEIGHT => MMU_ACTIVATE_WEIGHT, -- Recebe o Ativador (ACTIVATE_WEIGHT) para carregar os pesos de forma sequencial (Componente MATRIX_MULTIPLY_CONTROL)
        LOAD_WEIGHT     => MMU_LOAD_WEIGHT, -- Recebe o Ativador para pre-carregar uma coluna de pesos (Componente MATRIX_MULTIPLY_CONTROL)
        WEIGHT_ADDRESS  => MMU_WEIGHT_ADDRESS, -- Recebe o Endereço (ate 256) de "pre-pesos" (Componente MATRIX_MULTIPLY_CONTROL)
        
        RESULT_DATA     => MMU_RESULT_DATA -- Resultado da multiplicação das matrizes
    );
    
    REGISTER_FILE_i : REGISTER_FILE
    generic map(
        MATRIX_WIDTH    => MATRIX_WIDTH,
        REGISTER_DEPTH  => 512
    )
    port map(  
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
           
        WRITE_ADDRESS   => REG_WRITE_ADDRESS, -- Recebe ACC_ADDR o endereço da memoria dos acumuladores  (Componente MATRIX_MULTIPLY_CONTROL)
        WRITE_PORT      => MMU_RESULT_DATA, -- Recebe RESULT_DATA o dado a ser escrito na memoria de acumuladores  (Componente MATRIX_MULTIPLY_UNIT)
        WRITE_ENABLE    => REG_WRITE_EN, -- Recebe ACC_ENABLE o ativador para os acumuladores (Componente MATRIX_MULTIPLY_CONTROL)
           
        ACCUMULATE      => REG_ACCUMULATE, -- Recebe o ACCUMULATE para determinar se um dado ira ser acumulado ou sobrescrito (Componente MATRIX_MULTIPLY_CONTROL)
           
        READ_ADDRESS    => REG_READ_ADDRESS, -- Recebe o ACC_TO_ACT_ADDR o endereço do acumulador (Componente ACTIVATION_CONTROL)
        READ_PORT       => REG_READ_PORT -- Output de um dado da memoria de acumuladores
    );
    
    ACTIVATION_i : ACTIVATION
    generic map(
        MATRIX_WIDTH        => MATRIX_WIDTH
    )
    port map(
        CLK                 => CLK,
        RESET               => RESET,
        ENABLE              => ENABLE,      
        
        ACTIVATION_FUNCTION => ACTIVATION_FUNCTION, -- Recebe  ACTIVATION_FUNCTION a função a ser usada nos calculos (Componente ACTIVATION_CONTROL)
        --SIGNED_NOT_UNSIGNED => ACTIVATION_SIGNED, -- Recebe ACTIVATION_SIGNED o sinal que determina se os calculos tem sinal ou nao (Componente ACTIVATION_CONTROL)
        
        ACTIVATION_INPUT    => REG_READ_PORT, -- Recebe READ_PORT os dados depois de acumulados e calculados para aplicação da função de ativação (Componente REGISTER_FILE)
        ACTIVATION_OUTPUT   => BUFFER_WRITE_PORT1 -- Saida dos dados apos aplicação da função de ativação (Enviado para o UNIFIED BUFFER)
    );
    
    WEIGHT_CONTROL_i : WEIGHT_CONTROL
    generic map(
        MATRIX_WIDTH            => MATRIX_WIDTH
    )
    port map(
        CLK                     => CLK,
        RESET                   => RESET,
        ENABLE                  => ENABLE,
    
        INSTRUCTION             => WEIGHT_INSTRUCTION, -- Recebe a instrução de peso (Componente CONTROL CORDINATOR)
        INSTRUCTION_EN          => WEIGHT_INSTRUCTION_EN, -- Recebe o ativador da instrução de peso (Componente CONTROL CORDINATOR)
        
        WEIGHT_READ_EN          => WEIGHT_EN0, -- Output do ativador de leitura do peso
        WEIGHT_BUFFER_ADDRESS   => WEIGHT_ADDRESS0, -- Output do endereço do peso no Weight Buffer
        
        LOAD_WEIGHT             => MMU_LOAD_WEIGHT, -- Output do Ativador do Peso pra ser carregado
        WEIGHT_ADDRESS          => MMU_WEIGHT_ADDRESS, -- Output do Endereço do peso a ser carregado
        
        --WEIGHT_SIGNED           => MMU_WEIGHT_SIGNED, -- Output do Ativador se o Peso tem sinal ou nao
                
        BUSY                    => WEIGHT_BUSY, -- Output do Sinal se a Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        RESOURCE_BUSY           => WEIGHT_RESOURCE_BUSY -- Output do sinal se o recurso esta em uso e a instrução não esta totalmente terminada.
    );
    
    MATRIX_MULTIPLY_CONTROL_i : MATRIX_MULTIPLY_CONTROL
    generic map(
        MATRIX_WIDTH   
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
        
        INSTRUCTION     => MMU_INSTRUCTION, -- Recebe a Instrução da MMU a ser executada (Componente CONTROL CORDINATOR)
        INSTRUCTION_EN  => MMU_INSTRUCTION_EN, -- Recebe o ativador da instrução a ser executada (Componente CONTROL CORDINATOR)
        
        BUF_TO_SDS_ADDR => BUFFER_ADDRESS0, -- Output do Endereço de Leitura do Unified Buffer
        BUF_READ_EN     => BUFFER_EN0, -- Output do Ativadro do endereço de Leitura do Unified Buffer
        MMU_SDS_EN      => MMU_SDS_EN, -- Output da Flag de ativação para Matrix Multiply Unit e o Systolic data Setup
        --MMU_SIGNED      => MMU_SYSTOLIC_SIGNED, -- Output que informa se o SDS tem sinal ou nao para a MMU
        ACTIVATE_WEIGHT => MMU_ACTIVATE_WEIGHT, -- Output do ativador para carregar os pesos MMU
        
        ACC_ADDR        => REG_WRITE_ADDRESS, -- Output do endereço de memoria do acumulador para o REGISTER FILE
        ACCUMULATE      => REG_ACCUMULATE, -- Output do sinal se o dado ira ser acumulado ou sobrescrito no REGISTER FILE
        ACC_ENABLE      => REG_WRITE_EN, -- Output do sinal para os acumuladores
        
        BUSY            => MATRIX_BUSY, -- Output do Sinal se a Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        RESOURCE_BUSY   => MMU_RESOURCE_BUSY -- Output do sinal se o recurso esta em uso e a instrução não esta totalmente terminada. 
    );
    
    ACTIVATION_CONTROL_i : ACTIVATION_CONTROL
    generic map(
        MATRIX_WIDTH        
    )
    port map(
        CLK                 => CLK,
        RESET               => RESET,
        ENABLE              => ENABLE,
        
        INSTRUCTION         => ACTIVATION_INSTRUCTION, -- Recebe a Instrução da função de Ativação (Componente CONTROL CORDINATOR)
        INSTRUCTION_EN      => ACTIVATION_INSTRUCTION_EN, -- Recebe o ativador para a função de ativação (Componente CONTROL CORDINATOR)
        
        ACC_TO_ACT_ADDR     => REG_READ_ADDRESS, -- Output do endereço do acumulador a ser usado no REGISTER FILE
        ACTIVATION_FUNCTION => ACTIVATION_FUNCTION, -- Output da função de ativação que será usada nos calculos no ACTIVATION
        --SIGNED_NOT_UNSIGNED => ACTIVATION_SIGNED, -- Output se a função de ativação tera sinal ou nao
        
        ACT_TO_BUF_ADDR     => BUFFER_ADDRESS1, -- Output do endereço para dos acumuladores a serem escritos no Unified Buffer
        BUF_WRITE_EN        => BUFFER_WRITE_EN1, -- Output do Ativador de Escrita no Unified Buffer
        
        BUSY                => ACTIVATION_BUSY, -- Output do Sinal se a Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        RESOURCE_BUSY       => ACTIVATION_RESOURCE_BUSY -- Output do sinal se o recurso esta em uso e a instrução não esta totalmente terminada.
    );
    
    LOOK_AHEAD_BUFFER_i : LOOK_AHEAD_BUFFER
    port map(
        CLK                 => CLK,
        RESET               => RESET,
        ENABLE              => ENABLE,
        
        INSTRUCTION_BUSY    => INSTRUCTION_BUSY,-- Busy feedback do control coordinator para parar o pipeline.
        
        INSTRUCTION_INPUT   => INSTRUCTION_PORT, -- Entrada resultante do INSTRUCTION_FIFO, entrada de instrução
        INSTRUCTION_WRITE   => INSTRUCTION_ENABLE, -- Entrada resultante do processo INSTRUCTION_FEED (TPU)
        
        INSTRUCTION_OUTPUT  => INSTRUCTION_OUTPUT, -- Output de uma instrução a ser executada no COntrol Cordintor
        INSTRUCTION_READ    => INSTRUCTION_READ -- Output de uma nova instrução para ser executada
    );

    LOAD_INTERRUPTION_CONTROL_i : LOAD_INTERRUPTION_CONTROL
    generic map(
        MATRIX_WIDTH            => MATRIX_WIDTH,
        WEIGHT_BUFFER_DEPTH     => WEIGHT_BUFFER_DEPTH
    )
    port map(
        CLK                     => CLK,
        RESET                   => RESET,         
        ENABLE                  => ENABLE,           
    
        INSTRUCTION_EN          => LOAD_INTERRUPTION_EN,         
    
        BUSY                    => LOAD_INT_BUSY,                  
        RESOURCE_BUSY           => LOAD_INT_RESOURCE_BUSY           
    );

    CONTROL_COORDINATOR_i : CONTROL_COORDINATOR
    port map(
        CLK                         => CLK,
        RESET                       => RESET,
        ENABLE                      => ENABLE,
        
        INSTRUCTION                 => INSTRUCTION_OUTPUT, -- Instrução a ser executada
        INSTRUCTION_EN              => INSTRUCTION_READ, -- Ativador da instrução a ser executada

        BUSY                        => INSTRUCTION_BUSY, -- Output do Sinal se a Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.

        WEIGHT_BUSY                 => WEIGHT_BUSY, -- Recebe o Sinal se a respectiva Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        WEIGHT_RESOURCE_BUSY        => WEIGHT_RESOURCE_BUSY, -- Recebe o sinal se o recurso esta em uso e a instrução não esta totalmente terminada.
        WEIGHT_INSTRUCTION          => WEIGHT_INSTRUCTION, -- Output das instruções a serem usadas nas respectivas unidades de controle
        WEIGHT_INSTRUCTION_EN       => WEIGHT_INSTRUCTION_EN, -- Output da ativação das instruções

        MATRIX_BUSY                 => MATRIX_BUSY, -- Recebe o Sinal se a respectiva Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        MATRIX_RESOURCE_BUSY        => MMU_RESOURCE_BUSY, -- Recebe o sinal se o recurso esta em uso e a instrução não esta totalmente terminada.
        MATRIX_INSTRUCTION          => MMU_INSTRUCTION, -- Output das instruções a serem usadas nas respectivas unidades de controle
        MATRIX_INSTRUCTION_EN       => MMU_INSTRUCTION_EN, -- Output da ativação das instruções

        ACTIVATION_BUSY             => ACTIVATION_BUSY, -- Recebe o Sinal se a respectiva Control Unit esta ocupada, uma nova instrução nao deve ser adicionada.
        ACTIVATION_RESOURCE_BUSY    => ACTIVATION_RESOURCE_BUSY, -- Recebe o sinal se o recurso esta em uso e a instrução não esta totalmente terminada.
        ACTIVATION_INSTRUCTION      => ACTIVATION_INSTRUCTION, -- Output das instruções a serem usadas nas respectivas unidades de controle
        ACTIVATION_INSTRUCTION_EN   => ACTIVATION_INSTRUCTION_EN, -- Output da ativação das instruções
        
        LOAD_INT_BUSY               => LOAD_INT_BUSY,
        LOAD_INT_RESOURCE_BUSY      => LOAD_INT_RESOURCE_BUSY,
        LOAD_INTERRUPTION_EN        => LOAD_INTERRUPTION_EN,

        SYNCHRONIZE                 => SYNCHRONIZE -- Sera TRUE, quando uma instrução síncrona foi inserida e todas as unidades estão finalizada (MESMA SaIDA QUE O TPU_CORE USA)
    );
    
    BUSY              <= INSTRUCTION_BUSY;
    LOAD_INTERRUPTION <= LOAD_INTERRUPTION_EN;
end architecture BEH;