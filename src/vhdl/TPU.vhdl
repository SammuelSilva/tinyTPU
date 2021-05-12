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

--! @file TPU.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui toda a TPU
--! A TPU usa a TPU CORE e a Instruction FIFO

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity TPU is
    generic(
        MATRIX_WIDTH            : natural := 8; --!< A Largura da MMU e dos barramentos
        WEIGHT_BUFFER_DEPTH     : natural := 16; --!< A "profundidade" do Weight Buffer
        UNIFIED_BUFFER_DEPTH    : natural := 4096 --!< A "Profundidade" do Unified Buffer
    );  
    port(   
        CLK, RESET              : in  std_logic;
        ENABLE                  : in  std_logic;
        -- Para o calculo do verificador do tempo de execu��o 
        RUNTIME_COUNT           : out WORD_TYPE; --!< Conta o tempo de execu��o desde a primeira instru��o ativada at� o sinal de sincroniza��o.
        
        -- Entrada de instru��es para a FIFO
        LOWER_INSTRUCTION_WORD  : in  WORD_TYPE; --!< A palavra mais baixa da instru��o.
        MIDDLE_INSTRUCTION_WORD : in  WORD_TYPE; --!< A palavra do meio da instru��o.
        UPPER_INSTRUCTION_WORD  : in  HALFWORD_TYPE; --!< A meia-palavra (16 Bit) superior da instru��o.
        INSTRUCTION_WRITE_EN    : in  std_logic_vector(0 to 2); --!< Ativadores de escrita para cada palavra.
        
        -- Flags de interrup��es de Instru��es
        INSTRUCTION_EMPTY       : out std_logic; --!< Determina se a FIFO esta vazia . Usada para interromper o Sistema Host.
        INSTRUCTION_FULL        : out std_logic; --!< Determina se a FIFO esta cheia . Usada para interromper o Sistema Host.
    
        WEIGHT_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Porta de escrita do Host para weight buffer
        WEIGHT_ADDRESS          : in  WEIGHT_ADDRESS_TYPE; --!< Endere�o do Host para o weight buffer.
        WEIGHT_ENABLE           : in  std_logic; --!< Ativador do Host para o weight buffer.
        WEIGHT_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Ativador do Host para escrita especifica no weight buffer.
            
        BUFFER_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Porta de escrita do Host para unified buffer.
        BUFFER_READ_PORT        : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Host read port for the unified buffer.
        BUFFER_ADDRESS          : in  BUFFER_ADDRESS_TYPE; --!< Endere�o do Host para o unified buffer.
        BUFFER_ENABLE           : in  std_logic; --!< Ativador do Host para o unified buffer.
        BUFFER_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Ativador do Host para escrita especifica no unified buffer.
        -- Memory synchronization flag for interrupt 
        SYNCHRONIZE             : out std_logic; --!< Synchronization interrupt.
        LOAD_INTERRUPTION       : out std_logic
    );
end entity TPU;

--! @brief The architecture of the TPU.
architecture BEH of TPU is
    -- Contador de tempo de execu��o das Instru��es realizadas
    component RUNTIME_COUNTER is
        port(
            CLK, RESET      :  in std_logic;
            
            INSTRUCTION_EN  :  in std_logic;
            SYNCHRONIZE     :  in std_logic;
            COUNTER_VAL     : out WORD_TYPE
        );
    end component RUNTIME_COUNTER;
    for all : RUNTIME_COUNTER use entity WORK.RUNTIME_COUNTER(BEH);

    -- Instru��es que ser�o enviadas a FIFO quebradas em 3 partes (U,M,L)
    component INSTRUCTION_FIFO is
        generic(
            FIFO_DEPTH  : natural := 32
        );
        port(
            CLK, RESET  : in  std_logic;
            LOWER_WORD  : in  WORD_TYPE;
            MIDDLE_WORD : in  WORD_TYPE;
            UPPER_WORD  : in  HALFWORD_TYPE;
            WRITE_EN    : in  std_logic_vector(0 to 2);
            
            OUTPUT      : out INSTRUCTION_TYPE;
            NEXT_EN     : in  std_logic;
            
            EMPTY       : out std_logic;
            FULL        : out std_logic
        );
    end component INSTRUCTION_FIFO;
    for all : INSTRUCTION_FIFO use entity WORK.INSTRUCTION_FIFO(BEH);
    
    signal INSTRUCTION      : INSTRUCTION_TYPE;
    signal EMPTY            : std_logic;
    signal FULL             : std_logic;
    
    -- ?????
    component TPU_CORE is
        generic(
            MATRIX_WIDTH            : natural := 8;
            WEIGHT_BUFFER_DEPTH     : natural := 32768;
            UNIFIED_BUFFER_DEPTH    : natural := 4096
        );
        port(
            CLK, RESET          : in  std_logic;
            ENABLE              : in  std_logic;
        
            WEIGHT_WRITE_PORT   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_ADDRESS      : in  WEIGHT_ADDRESS_TYPE;
            WEIGHT_ENABLE       : in  std_logic;
            WEIGHT_WRITE_ENABLE : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            
            BUFFER_WRITE_PORT   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_READ_PORT    : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_ADDRESS      : in  BUFFER_ADDRESS_TYPE;
            BUFFER_ENABLE       : in  std_logic;
            BUFFER_WRITE_ENABLE : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            
            INSTRUCTION_PORT    : in  INSTRUCTION_TYPE;
            INSTRUCTION_ENABLE  : in  std_logic;
            
            BUSY                : out std_logic;
            SYNCHRONIZE         : out std_logic;
            LOAD_INTERRUPTION   : out std_logic
        );
    end component TPU_CORE;
    for all : TPU_CORE use entity WORK.TPU_CORE(BEH);
    
    signal INSTRUCTION_ENABLE   : std_logic;
    signal BUSY                 : std_logic;
    signal SYNCHRONIZE_IN       : std_logic;
    signal LOAD_INTERRUPTION_IN : std_logic;
begin
    -- Atribui�ao das portas com seus respectivos inputs e outputs
    RUNTIME_COUNTER_i : RUNTIME_COUNTER
    port map(
        CLK             => CLK,
        RESET           => RESET,
        INSTRUCTION_EN  => INSTRUCTION_ENABLE, -- Entrada resultante do processo INSTRUCTION_FEED
        SYNCHRONIZE     => SYNCHRONIZE_IN, -- Entrada resultante da saida do SYNCHRONIZE do TPU_CORE
        COUNTER_VAL     => RUNTIME_COUNT -- OUTPUT: Saida com o resultado do contador
    );

    INSTRUCTION_FIFO_i : INSTRUCTION_FIFO
    port map(
        CLK         => CLK,
        RESET       => RESET,
        LOWER_WORD  => LOWER_INSTRUCTION_WORD, -- A palavra mais baixa da instru��o (32 bits).
        MIDDLE_WORD => MIDDLE_INSTRUCTION_WORD, -- A palavra do meio da instru��o (32 bits).
        UPPER_WORD  => UPPER_INSTRUCTION_WORD, -- A palavra mais alta da instru��o (16 bits).
        WRITE_EN    => INSTRUCTION_WRITE_EN,  -- Ativadores de escrita para cada palavra.
        OUTPUT      => INSTRUCTION,
        NEXT_EN     => INSTRUCTION_ENABLE, -- Entrada resultante do processo INSTRUCTION_FEED
        EMPTY       => EMPTY, -- OUTPUT: Fifo vazia
        FULL        => FULL -- OUTPUT: Fifo Cheia
    );
    
    INSTRUCTION_EMPTY <= EMPTY;
    INSTRUCTION_FULL  <= FULL;
    
    TPU_CORE_i : TPU_CORE
    generic map(
        MATRIX_WIDTH            => MATRIX_WIDTH,
        WEIGHT_BUFFER_DEPTH     => WEIGHT_BUFFER_DEPTH,
        UNIFIED_BUFFER_DEPTH    => UNIFIED_BUFFER_DEPTH
    )
    port map(
        CLK                 => CLK,
        RESET               => RESET,
        ENABLE              => ENABLE,            

        -- Entradas para o TPU_CORE
        WEIGHT_WRITE_PORT   => WEIGHT_WRITE_PORT,
        WEIGHT_ADDRESS      => WEIGHT_ADDRESS,
        WEIGHT_ENABLE       => WEIGHT_ENABLE, 
        WEIGHT_WRITE_ENABLE => WEIGHT_WRITE_ENABLE,
        
        BUFFER_WRITE_PORT   => BUFFER_WRITE_PORT,
        BUFFER_READ_PORT    => BUFFER_READ_PORT, -- Porta de saida da TPU � a porta de saida da TPU_CORE que � a porta de saida do MASTER_READ_PORT do UNIFIED_BUFFER
        BUFFER_ADDRESS      => BUFFER_ADDRESS,
        BUFFER_ENABLE       => BUFFER_ENABLE,
        BUFFER_WRITE_ENABLE => BUFFER_WRITE_ENABLE,
        
        INSTRUCTION_PORT    => INSTRUCTION, -- Entrada resultante do INSTRUCTION_FIFO
        INSTRUCTION_ENABLE  => INSTRUCTION_ENABLE, -- Entrada resultante do processo INSTRUCTION_FEED
        
        BUSY                => BUSY, -- OUTPUT: Se o Control Cordinator esta ocupado
        SYNCHRONIZE         => SYNCHRONIZE_IN, -- OUTPUT: Se as instru��es est�o sincronizadas
        LOAD_INTERRUPTION   => LOAD_INTERRUPTION_IN
    );
    
    SYNCHRONIZE       <= SYNCHRONIZE_IN;
    LOAD_INTERRUPTION <= LOAD_INTERRUPTION_IN;
    -- Verifica se a FIFO esta vazia e n�o h� instru��es sendo executadas para inserir uma nova instru��o na TPU
    INSTRUCTION_FEED:
    process(EMPTY, BUSY) is
    begin
        if BUSY = '0' and EMPTY = '0' then
            INSTRUCTION_ENABLE <= '1';
        else
            INSTRUCTION_ENABLE <= '0';
        end if;
    end process INSTRUCTION_FEED;
end architecture BEH;