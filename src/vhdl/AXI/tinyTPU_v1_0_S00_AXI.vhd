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

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;
    use IEEE.math_real.floor;

entity tinyTPU_v1_0_S00_AXI is
	generic (
            -- Inserção de parametros do usuario: Begin

            -- End

            -->> Não modifique os parametros depois desta linha

            -- Largura do S_AXI data bus
            C_S_AXI_DATA_WIDTH	: integer	:= 32;
            -- Largura do S_AXI address bus
            C_S_AXI_ADDR_WIDTH	: integer	:= 20
        );
	port (
		-- Inserção de portas do usuario: Begin
        SYNCHRONIZE       : out std_logic;
        LOAD_INTERRUPTION : out std_logic;
        -- End
        -->> Não modifique as portas apos esta linha

        ----------------------------- Global Signals ---------------------------------------

        -- Sinal de Clock Global
        S_AXI_ACLK	: in std_logic;

        -- Sinal de Reset Global: Ativo em LOW
        S_AXI_ARESETN	: in std_logic;
        -------------------------------------------------------------------------------------
        ----------------------------- Write Signals Address ---------------------------------

        -- Endereço de escrita (20 bits) da primeira transferencia de dados (beats)
            -- (Emitido pelo Master e aceito pelo Slave)
        S_AXI_AWADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);

        -- Canal de Escrita com proteção. Este sinal indica o:
            -- Privilegio e o Level de segurança da transação 
            -- e quando ela é Data Access ou uma Instruction Access 
        S_AXI_AWPROT	: in std_logic_vector(2 downto 0);

        -- Validação do Endereço de escrita (handshake). 
            -- Este sinal indica que o Master esta sinalizando que ambos o endereço de escrita 
            -- e o Controle de informação são validos.
        S_AXI_AWVALID	: in std_logic;

        -- Endereço de escrita pronto (handshake). 
            -- Este sinal indica que o Slave esta pronto para aceitar um endereço e 
            -- sinais de controle associados
        S_AXI_AWREADY	: out std_logic;

        ---------------------------------------------------------------------------------------------
        ----------------------------------- Write Signals  ------------------------------------------

        -- Escrita de dados (32 bits)
            -- (Emitido pelo Master, aceito pelo Slave)
        S_AXI_WDATA	: in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        
        -- Strobes de Escrita. 
            -- Este Sinal indica quais linhas de byte armazenam dados validos.
            -- Existe um Strobe de Escrita para cada 8 bits de Dados de escrita no barramento.  
        S_AXI_WSTRB	: in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        
        -- validação de escrita (handshake). 
            -- Este sinal indica que dados de escritas validos e seus Strobes estão disponiveis
        S_AXI_WVALID	: in std_logic;
        
        -- Escrita pronta (handshake).
            -- Este sinal indica que o Slave pode aceitar um dado para ser escrito.
        S_AXI_WREADY	: out std_logic;
        
        ----------------------------------------------------------------------------------------------
        -------------------------------- Write Response Signals  -------------------------------------
        
        -- Write Response. Este sinal indica o status do processo de escrita
        S_AXI_BRESP	: out std_logic_vector(1 downto 0);
        
        -- Validação do Write response (handshake). 
            -- Este sinal indica se o canal esta sinalizando uma Write Response Valida.
        S_AXI_BVALID	: out std_logic;
        
        -- Response ready.
            -- Este sinal indica que o Master pode aceitar um Write Response.
        S_AXI_BREADY	: in std_logic;

        ----------------------------------------------------------------------------------------------
        ----------------------------- Read Signals Address ---------------------------------

		-- Endereço de Leitura (Emitido pelo Master, aceito pelo Slave)
        S_AXI_ARADDR	: in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        
		-- Protection type. This signal indicates the privilege
    		-- and security level of the transaction, and whether the
    		-- transaction is a data access or an instruction access.
        S_AXI_ARPROT	: in std_logic_vector(2 downto 0);
        
        -- Endereço de Leitura valido (handshake). 
            -- Este sinal indica que o canal esta sinalizando 
            -- que o endereco de leitura e a informaçao de controle sao validos.
        S_AXI_ARVALID	: in std_logic;
        
		-- Endereço de leitura pronto (handshake). 
            -- Este sinal indica que o Slave esta pronto para aceitar um endereço e 
            -- sinais de controle associados
        S_AXI_ARREADY	: out std_logic;

        ----------------------------------------------------------------------------------------------
        ------------------------------------- Read Signals  ------------------------------------------

		-- Informaçao Lida (Emitido by slave)
        S_AXI_RDATA	: out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        
		-- Read response. Este sinal indica o status do read transfer (RDATA).
        S_AXI_RRESP	: out std_logic_vector(1 downto 0);
        
        -- Read valid (handshake). 
            -- Este sinal indica que o canal possui os dados de leitura requisitados
        S_AXI_RVALID	: out std_logic;
        
        -- Read ready (handshake). 
            -- Este sinal indica que o Master pode aceitar o Read Data e a Response Information
		S_AXI_RREADY	: in std_logic
	);
end tinyTPU_v1_0_S00_AXI;

architecture arch_imp of tinyTPU_v1_0_S00_AXI is

    -- tinyTPU logic
    component TPU is
        generic(
            MATRIX_WIDTH            : natural := 8;
            WEIGHT_BUFFER_DEPTH     : natural := 32768;
            UNIFIED_BUFFER_DEPTH    : natural := 4096
        );  
        port(   
            CLK, RESET              : in  std_logic;
            ENABLE                  : in  std_logic;
            -- For calculation runtime check
            RUNTIME_COUNT           : out WORD_TYPE;
            -- Splitted instruction input
            LOWER_INSTRUCTION_WORD  : in  WORD_TYPE;
            MIDDLE_INSTRUCTION_WORD : in  WORD_TYPE;
            UPPER_INSTRUCTION_WORD  : in  HALFWORD_TYPE;
            INSTRUCTION_WRITE_EN    : in  std_logic_vector(0 to 2);
            -- Instruction buffer flags for interrupts
            INSTRUCTION_EMPTY       : out std_logic;
            INSTRUCTION_FULL        : out std_logic;
        
            WEIGHT_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_ADDRESS          : in  WEIGHT_ADDRESS_TYPE;
            WEIGHT_ENABLE           : in  std_logic;
            WEIGHT_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1);
                
            BUFFER_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_READ_PORT        : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_ADDRESS          : in  BUFFER_ADDRESS_TYPE;
            BUFFER_ENABLE           : in  std_logic;
            BUFFER_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            -- Memory synchronization flag for interrupt 
            SYNCHRONIZE             : out std_logic;
            LOAD_INTERRUPTION       : out std_logic
        );
    end component TPU;
    for all : TPU use entity WORK.TPU(BEH);
    
    --> Maquina de estado finita.
    type FSM_TYPE is (IDLE, WRITE_ADDRESS, WRITE_DATA, WRITE_RESPONSE, READ_ADDRESS, READ_DATA, READ_RESPONSE);
    
    constant MATRIX_WIDTH           : natural := 8;
    constant WEIGHT_BUFFER_DEPTH    : natural := 16;
    constant UNIFIED_BUFFER_DEPTH   : natural := 4096;
    
    constant MATRIX_ADDRESS_WIDTH       : natural := natural(ceil(log2(real(MATRIX_WIDTH) / 4.0 ))); -- Atomic range - LSBs (size 2)
    constant WEIGHT_ADDRESS_BASE        : natural := 0;
    constant WEIGHT_ADDRESS_END         : natural := WEIGHT_BUFFER_DEPTH-1;
    constant BUFFER_ADDRESS_BASE        : natural := WEIGHT_BUFFER_DEPTH;
    constant BUFFER_ADDRESS_END         : natural := WEIGHT_BUFFER_DEPTH + UNIFIED_BUFFER_DEPTH-1; -- 36.863
    constant BUFFER_BIT_POSITION        : natural := natural(log2(real(BUFFER_ADDRESS_BASE))); -- 15
    constant INSTRUCTION_ADDRESS_BASE   : natural := WEIGHT_BUFFER_DEPTH + UNIFIED_BUFFER_DEPTH; -- 36.864
    constant INSTRUCTION_ADDRESS_END    : natural := WEIGHT_BUFFER_DEPTH + UNIFIED_BUFFER_DEPTH; -- 36.864
    constant INSTRUCTION_BIT_POSITION   : natural := natural(log2(real(UNIFIED_BUFFER_DEPTH))); -- 12
    
    constant MATRIX_ADDRESS_SIZE        : natural := 2**MATRIX_ADDRESS_WIDTH; -- 4
    
    constant UPPER_ADDRESS_WIDTH        : natural := natural(ceil(log2(real(BUFFER_ADDRESS_END)))); -- MSBs (size 6) --16
    constant ADDRESS_WIDTH              : natural := UPPER_ADDRESS_WIDTH + MATRIX_ADDRESS_WIDTH; -- 10
    
    -- TPU signals
    signal Reset                    : std_logic;
    
    signal RUNTIME_COUNT            : WORD_TYPE;
        
    signal LOWER_INSTRUCTION_WORD   : WORD_TYPE;
    signal MIDDLE_INSTRUCTION_WORD  : WORD_TYPE;
    signal UPPER_INSTRUCTION_WORD   : HALFWORD_TYPE;
    signal INSTRUCTION_WRITE_EN     : std_logic_vector(0 to 2);
    signal INSTRUCTION_FULL         : std_logic;
            
    signal WEIGHT_WRITE_PORT        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_ADDRESS           : WEIGHT_ADDRESS_TYPE;
    signal WEIGHT_ENABLE            : std_logic;
    signal WEIGHT_WRITE_ENABLE      : std_logic_vector(0 to MATRIX_WIDTH-1);
            
    signal BUFFER_WRITE_PORT        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_READ_PORT         : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_ADDRESS           : BUFFER_ADDRESS_TYPE;
    signal BUFFER_ENABLE            : std_logic;
    signal BUFFER_WRITE_ENABLE      : std_logic_vector(0 to MATRIX_WIDTH-1);
        
    -- Address mux signals
    signal WEIGHT_WRITE_ADDRESS     : WEIGHT_ADDRESS_TYPE;
    signal BUFFER_WRITE_ADDRESS     : BUFFER_ADDRESS_TYPE;
    signal BUFFER_READ_ADDRESS      : BUFFER_ADDRESS_TYPE;
    
    signal BUFFER_ENABLE_ON_WRITE   : std_logic;
    signal BUFFER_ENABLE_ON_READ    : std_logic;
    
    -- Input registers for weight buffer
    signal WEIGHT_WRITE_PORT_REG0_cs    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal WEIGHT_WRITE_PORT_REG0_ns    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_WRITE_PORT_REG1_cs    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal WEIGHT_WRITE_PORT_REG1_ns    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_ADDRESS_REG0_cs       : WEIGHT_ADDRESS_TYPE := (others => '0');
    signal WEIGHT_ADDRESS_REG0_ns       : WEIGHT_ADDRESS_TYPE;
    signal WEIGHT_ADDRESS_REG1_cs       : WEIGHT_ADDRESS_TYPE := (others => '0');
    signal WEIGHT_ADDRESS_REG1_ns       : WEIGHT_ADDRESS_TYPE;
    signal WEIGHT_WRITE_ENABLE_REG0_cs  : std_logic_vector(0 to MATRIX_WIDTH-1) := (others => '0');
    signal WEIGHT_WRITE_ENABLE_REG0_ns  : std_logic_vector(0 to MATRIX_WIDTH-1);
    signal WEIGHT_WRITE_ENABLE_REG1_cs  : std_logic_vector(0 to MATRIX_WIDTH-1) := (others => '0');
    signal WEIGHT_WRITE_ENABLE_REG1_ns  : std_logic_vector(0 to MATRIX_WIDTH-1);
    signal WEIGHT_ENABLE_ON_WRITE_REG0_cs   : std_logic := '0';
    signal WEIGHT_ENABLE_ON_WRITE_REG0_ns   : std_logic;
    signal WEIGHT_ENABLE_ON_WRITE_REG1_cs   : std_logic := '0';
    signal WEIGHT_ENABLE_ON_WRITE_REG1_ns   : std_logic;
    
    -- Input registers for unified buffer
    signal BUFFER_WRITE_PORT_REG0_cs    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal BUFFER_WRITE_PORT_REG0_ns    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_WRITE_PORT_REG1_cs    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal BUFFER_WRITE_PORT_REG1_ns    : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_ADDRESS_REG0_cs       : BUFFER_ADDRESS_TYPE := (others => '0');
    signal BUFFER_ADDRESS_REG0_ns       : BUFFER_ADDRESS_TYPE;
    signal BUFFER_ADDRESS_REG1_cs       : BUFFER_ADDRESS_TYPE := (others => '0');
    signal BUFFER_ADDRESS_REG1_ns       : BUFFER_ADDRESS_TYPE;
    signal BUFFER_WRITE_ENABLE_REG0_cs  : std_logic_vector(0 to MATRIX_WIDTH-1) := (others => '0');
    signal BUFFER_WRITE_ENABLE_REG0_ns  : std_logic_vector(0 to MATRIX_WIDTH-1);
    signal BUFFER_WRITE_ENABLE_REG1_cs  : std_logic_vector(0 to MATRIX_WIDTH-1) := (others => '0');
    signal BUFFER_WRITE_ENABLE_REG1_ns  : std_logic_vector(0 to MATRIX_WIDTH-1);
    signal BUFFER_ENABLE_ON_WRITE_REG0_cs   : std_logic := '0';
    signal BUFFER_ENABLE_ON_WRITE_REG0_ns   : std_logic;
    signal BUFFER_ENABLE_ON_WRITE_REG1_cs   : std_logic := '0';
    signal BUFFER_ENABLE_ON_WRITE_REG1_ns   : std_logic;
    
    -- For read delays
    signal UPPER_READ_ADDRESS_DELAY0_cs : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal UPPER_READ_ADDRESS_DELAY0_ns : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0);
    signal UPPER_READ_ADDRESS_DELAY1_cs : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal UPPER_READ_ADDRESS_DELAY1_ns : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0);
    signal UPPER_READ_ADDRESS_DELAY2_cs : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal UPPER_READ_ADDRESS_DELAY2_ns : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0);
    
    signal LOWER_READ_ADDRESS_DELAY0_cs : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal LOWER_READ_ADDRESS_DELAY0_ns : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0);
    signal LOWER_READ_ADDRESS_DELAY1_cs : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal LOWER_READ_ADDRESS_DELAY1_ns : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0);
    signal LOWER_READ_ADDRESS_DELAY2_cs : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal LOWER_READ_ADDRESS_DELAY2_ns : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0);
    
    -- Signals from state machine
    signal STATE_cs         : FSM_TYPE := IDLE;
    signal STATE_ns         : FSM_TYPE;
    
    signal WRITE_ACCEPT     : std_logic;
    
    signal WRITE_ADDRESS_EN : std_logic;
    signal WRITE_ADDRESS_cs : std_logic_vector(C_S_AXI_ADDR_WIDTH-2-1 downto 0) := (others => '0');
    signal WRITE_ADDRESS_ns : std_logic_vector(C_S_AXI_ADDR_WIDTH-2-1 downto 0);
    signal READ_ADDRESS_EN  : std_logic;
    signal READ_ADDRESS_cs  : std_logic_vector(C_S_AXI_ADDR_WIDTH-2-1 downto 0) := (others => '0');
    signal READ_ADDRESS_ns  : std_logic_vector(C_S_AXI_ADDR_WIDTH-2-1 downto 0);
    signal WRITE_DATA_EN    : std_logic;
    signal WRITE_DATA_cs    : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal WRITE_DATA_ns    : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    signal READ_DATA_EN     : std_logic;
    signal READ_DATA_cs     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0) := (others => '0');
    signal READ_DATA_ns     : std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
    
    signal SLAVE_WRITE_EN   : std_logic;
    signal SLAVE_READ_EN    : std_logic;
    signal READ_DATA_ON_BUS : std_logic;
    signal READ_DATA_DELAY_cs   : std_logic_vector(0 to 2) := (others => '0');
    signal READ_DATA_DELAY_ns   : std_logic_vector(0 to 2);

begin
    RESET <= not S_AXI_ARESETN; -- Sinal de Reset para TPU
    
    TPU_i : TPU
    generic map(
        MATRIX_WIDTH            => MATRIX_WIDTH,
        WEIGHT_BUFFER_DEPTH     => WEIGHT_BUFFER_DEPTH,
        UNIFIED_BUFFER_DEPTH    => UNIFIED_BUFFER_DEPTH
    )
    port map(
        CLK                     => S_AXI_ACLK, -- Clock Global
        RESET                   => RESET,
        ENABLE                  => '1', -- Enable always for now
        RUNTIME_COUNT           => RUNTIME_COUNT,
        LOWER_INSTRUCTION_WORD  => LOWER_INSTRUCTION_WORD,
        MIDDLE_INSTRUCTION_WORD => MIDDLE_INSTRUCTION_WORD,
        UPPER_INSTRUCTION_WORD  => UPPER_INSTRUCTION_WORD,
        INSTRUCTION_WRITE_EN    => INSTRUCTION_WRITE_EN,
        INSTRUCTION_EMPTY       => open,
        INSTRUCTION_FULL        => INSTRUCTION_FULL,
        WEIGHT_WRITE_PORT       => WEIGHT_WRITE_PORT,
        WEIGHT_ADDRESS          => WEIGHT_ADDRESS,
        WEIGHT_ENABLE           => WEIGHT_ENABLE,
        WEIGHT_WRITE_ENABLE     => WEIGHT_WRITE_ENABLE,
        BUFFER_WRITE_PORT       => BUFFER_WRITE_PORT,
        BUFFER_READ_PORT        => BUFFER_READ_PORT,
        BUFFER_ADDRESS          => BUFFER_ADDRESS,
        BUFFER_ENABLE           => BUFFER_ENABLE,
        BUFFER_WRITE_ENABLE     => BUFFER_WRITE_ENABLE,
        SYNCHRONIZE             => SYNCHRONIZE,
        LOAD_INTERRUPTION       => LOAD_INTERRUPTION
    );

    -- Registradores para inserção de dados no processo TPU_READ
    UPPER_READ_ADDRESS_DELAY1_ns <= UPPER_READ_ADDRESS_DELAY0_cs;
    UPPER_READ_ADDRESS_DELAY2_ns <= UPPER_READ_ADDRESS_DELAY1_cs;
    LOWER_READ_ADDRESS_DELAY1_ns <= LOWER_READ_ADDRESS_DELAY0_cs;
    LOWER_READ_ADDRESS_DELAY2_ns <= LOWER_READ_ADDRESS_DELAY1_cs;
    
    -- Inserção dos Endereços 
    WEIGHT_ADDRESS <= WEIGHT_WRITE_ADDRESS; -- (Processo TPU_WRITE)
    BUFFER_ADDRESS <= BUFFER_WRITE_ADDRESS when BUFFER_ENABLE_ON_WRITE = '1' else BUFFER_READ_ADDRESS; -- Se for '1' Buffer para escrita, se '0' para leitura
    
    BUFFER_ENABLE <= BUFFER_ENABLE_ON_WRITE or BUFFER_ENABLE_ON_READ; -- Ativação do Buffer para Escrita/Leitura
    
    -- Sinal que permite a leitura de dados do barramento
    READ_DATA_DELAY_ns(0) <= SLAVE_READ_EN;
    READ_DATA_DELAY_ns(1 to 2) <= READ_DATA_DELAY_cs(0 to 1);
    READ_DATA_ON_BUS <= READ_DATA_DELAY_cs(2);
    
    -- Align on 32 Bit
    WRITE_ADDRESS_ns <= S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto 2); --Endereço de Escrita (18 bits) (Processo TPU_WRITE)
    READ_ADDRESS_ns  <= S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH-1 downto 2); --Endereço de Leitura (18 bits) (Processo TPU_READ)
    
    WRITE_DATA_ns    <= S_AXI_WDATA; -- Dado a ser escrito (Processo TPU_WRITE)
    S_AXI_RDATA      <= READ_DATA_cs; -- Informação que foi lida para saida (processo TPU_READ)
    
    FSM:
    process(STATE_cs, WRITE_ACCEPT, S_AXI_AWVALID, S_AXI_ARVALID, S_AXI_WVALID, S_AXI_BREADY, S_AXI_RREADY, READ_DATA_ON_BUS) is
        variable AWVALID_ARVALID : std_logic_vector(1 downto 0);
    begin
        AWVALID_ARVALID := S_AXI_AWVALID & S_AXI_ARVALID; -- Concatena os sinais se pode realizar Escrita e se pode realizar leitura
    
        case STATE_cs is
            when IDLE =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '1';
                S_AXI_ARREADY <= '1';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                SLAVE_WRITE_EN <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                WRITE_DATA_EN <= '0';
                case AWVALID_ARVALID is
                    when "10" =>
                        WRITE_ADDRESS_EN    <= '1';
                        READ_ADDRESS_EN     <= '0';
                        STATE_ns <= WRITE_ADDRESS;
                    when "01" =>
                        WRITE_ADDRESS_EN    <= '0';
                        READ_ADDRESS_EN     <= '1';
                        STATE_ns <= READ_ADDRESS;
                    when others =>
                        WRITE_ADDRESS_EN    <= '0';
                        READ_ADDRESS_EN     <= '0';
                        STATE_ns <= IDLE;
                end case;
            when WRITE_ADDRESS =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '1';
                -- Enable flags
                SLAVE_WRITE_EN <= '0';
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                case S_AXI_WVALID is
                    when '0' =>
                        WRITE_DATA_EN <= '0';
                        STATE_ns <= WRITE_ADDRESS;
                    when '1' =>
                        WRITE_DATA_EN <= '1';
                        STATE_ns <= WRITE_DATA;
                    when others => -- for simulation
                        WRITE_DATA_EN <= '0';
                        STATE_ns <= WRITE_ADDRESS;
                end case;
            when WRITE_DATA =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                WRITE_DATA_EN <= '0';
                SLAVE_WRITE_EN <= '1';
                case WRITE_ACCEPT is
                    when '0' => -- wait for the device to accept
                        STATE_ns <= WRITE_DATA;
                    when '1' => -- write is accepted
                        STATE_ns <= WRITE_RESPONSE;
                    when others =>
                        STATE_ns <= WRITE_DATA;
                end case;
            when WRITE_RESPONSE =>
                -- Response
                S_AXI_BRESP <= "00"; -- OK
                S_AXI_BVALID <= '1';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                SLAVE_WRITE_EN <= '0';
                WRITE_DATA_EN <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                case S_AXI_BREADY is
                    when '0' =>
                        STATE_ns <= WRITE_RESPONSE;
                    when '1' =>
                        STATE_ns <= IDLE;
                    when others =>
                        STATE_ns <= WRITE_RESPONSE;
                end case;
            when READ_ADDRESS =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                SLAVE_WRITE_EN <= '0';
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                WRITE_DATA_EN <= '0';
                READ_DATA_EN <= '0';
                case S_AXI_RREADY is
                    when '0' =>
                        SLAVE_READ_EN <= '0';
                        STATE_ns <= READ_ADDRESS;
                    when '1' =>
                        SLAVE_READ_EN <= '1';
                        STATE_ns <= READ_DATA;
                    when others =>
                        SLAVE_READ_EN <= '0';
                        STATE_ns <= READ_ADDRESS;
                end case;
            when READ_DATA =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                WRITE_DATA_EN <= '0';
                SLAVE_WRITE_EN <= '0';
                SLAVE_READ_EN <= '0';
                case READ_DATA_ON_BUS is
                    when '0' =>
                        READ_DATA_EN <= '0';
                        STATE_ns <= READ_DATA;
                    when '1' =>
                        READ_DATA_EN <= '1';
                        STATE_ns <= READ_RESPONSE;
                    when others =>
                        READ_DATA_EN <= '0';
                        STATE_ns <= READ_DATA;
                end case;
            when READ_RESPONSE =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '1';
                S_AXI_RRESP  <= "00"; -- OK
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                SLAVE_WRITE_EN <= '0';
                WRITE_DATA_EN <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                STATE_ns <= IDLE;
            when others =>
                -- Response
                S_AXI_BRESP <= "10"; -- Slave error
                S_AXI_BVALID <= '0';
                S_AXI_RVALID <= '0';
                S_AXI_RRESP  <= "10"; -- Slave error
                -- Address ready
                S_AXI_AWREADY <= '0';
                S_AXI_ARREADY <= '0';
                -- Data ready
                S_AXI_WREADY  <= '0';
                -- Enable flags
                WRITE_ADDRESS_EN <= '0';
                READ_ADDRESS_EN  <= '0';
                SLAVE_WRITE_EN <= '0';
                WRITE_DATA_EN <= '0';
                READ_DATA_EN <= '0';
                SLAVE_READ_EN <= '0';
                STATE_ns <= IDLE;
        end case;
    end process FSM;

--------------------- TPU_WRITE OUTPUT --------------------------

    -- Peso a ser escrito
    WEIGHT_WRITE_PORT_REG1_ns <= WEIGHT_WRITE_PORT_REG0_cs;
    WEIGHT_WRITE_PORT <= WEIGHT_WRITE_PORT_REG1_cs;
    
    -- Endereço de escrita
    WEIGHT_ADDRESS_REG1_ns <= WEIGHT_ADDRESS_REG0_cs;
    WEIGHT_WRITE_ADDRESS <= WEIGHT_ADDRESS_REG1_cs;
    
    -- Ativador de escrita por byte
    WEIGHT_WRITE_ENABLE_REG1_ns <= WEIGHT_WRITE_ENABLE_REG0_cs;
    WEIGHT_WRITE_ENABLE <= WEIGHT_WRITE_ENABLE_REG1_cs;
    
    -- Ativador de escrita  principal
    WEIGHT_ENABLE_ON_WRITE_REG1_ns <= WEIGHT_ENABLE_ON_WRITE_REG0_cs;
    WEIGHT_ENABLE <= WEIGHT_ENABLE_ON_WRITE_REG1_cs;
    
    -- Dado a ser escrito no buffer
    BUFFER_WRITE_PORT_REG1_ns <= BUFFER_WRITE_PORT_REG0_cs;
    BUFFER_WRITE_PORT <= BUFFER_WRITE_PORT_REG1_cs;
    
    -- Endereço de escrita
    BUFFER_ADDRESS_REG1_ns <= BUFFER_ADDRESS_REG0_cs;
    BUFFER_WRITE_ADDRESS <= BUFFER_ADDRESS_REG1_cs;
    
    -- Ativador de escrita por byte
    BUFFER_WRITE_ENABLE_REG1_ns <= BUFFER_WRITE_ENABLE_REG0_cs;
    BUFFER_WRITE_ENABLE <= BUFFER_WRITE_ENABLE_REG1_cs;
    
    -- Ativadro de escrita de toda palavra
    BUFFER_ENABLE_ON_WRITE_REG1_ns <= BUFFER_ENABLE_ON_WRITE_REG0_cs;
    BUFFER_ENABLE_ON_WRITE <= BUFFER_ENABLE_ON_WRITE_REG1_cs;
    
    --Inputs
        -- Slave_Write_EN <-- FSM
        -- WRITE_ADDRESS_cs <-- S_AXI_AWADDR(C_S_AXI_ADDR_WIDTH-1 downto 2) (input)
        -- WRITE_DATA_cs <-- S_AXI_WDATA (input)
        -- S_AXI_WSTRB <-- (input)
        -- INSTRUCTION_FULL <-- TPU_i
    -- Funcionamento: Carrega as instruções, os dados de peso e do buffer e os endereços para as portas de entrada e registradores temporarios
    -- Caso o Slave_Write_EN esteja ativo, primeiramente ele irá carregar as instruções na FIFO
        -- Depois, caso seja uma instrução de Weight/Unified que será feita é setado os bits para as respectivas escritas
    TPU_WRITE:
    process(SLAVE_WRITE_EN, WRITE_ADDRESS_cs, WRITE_DATA_cs, S_AXI_WSTRB, INSTRUCTION_FULL) is
        variable UPPER_WRITE_ADDRESS_v : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0);
        variable LOWER_WRITE_ADDRESS_v : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0);
        variable LOWER_INSTRUCTION_ADDRESS_v : std_logic_vector(MATRIX_ADDRESS_WIDTH downto 0);
    begin
        UPPER_WRITE_ADDRESS_v := WRITE_ADDRESS_cs(ADDRESS_WIDTH-1 downto MATRIX_ADDRESS_WIDTH); -- (9 downto 2)
        LOWER_WRITE_ADDRESS_v := WRITE_ADDRESS_cs(MATRIX_ADDRESS_WIDTH-1 downto 0); -- (1 downto 0)
        LOWER_INSTRUCTION_ADDRESS_v := WRITE_ADDRESS_cs(MATRIX_ADDRESS_WIDTH downto 0);

        -- Connect write data to instruction ports
        LOWER_INSTRUCTION_WORD  <= WRITE_DATA_cs;
        MIDDLE_INSTRUCTION_WORD <= WRITE_DATA_cs;
        UPPER_INSTRUCTION_WORD  <= WRITE_DATA_cs(2*BYTE_WIDTH-1 downto 0);
        
        -- Connect write data to weight buffer and unified buffer write port
            -- If mod is equal to 0, then both registers: (byte_width-1 downto 0)
            -- If mod is equal to 1, then: (2*byte_widht-1 downto 8)
        for i in 0 to MATRIX_WIDTH-1 loop
            WEIGHT_WRITE_PORT_REG0_ns(i) <= WRITE_DATA_cs(((i mod 4)+1)*BYTE_WIDTH-1 downto (i mod 4)*BYTE_WIDTH);
            BUFFER_WRITE_PORT_REG0_ns(i) <= WRITE_DATA_cs(((i mod 4)+1)*BYTE_WIDTH-1 downto (i mod 4)*BYTE_WIDTH);
        end loop;
        
        -- (4 downto 0) will receive UPPER_WRITE_ADDRESS and (39 downto 5) will receive '0'
        WEIGHT_ADDRESS_REG0_ns(BUFFER_BIT_POSITION-1 downto 0) <= UPPER_WRITE_ADDRESS_v(BUFFER_BIT_POSITION-1 downto 0);
        WEIGHT_ADDRESS_REG0_ns(WEIGHT_ADDRESS_WIDTH-1 downto BUFFER_BIT_POSITION) <= (others => '0');
        
        -- (11 downto 0) will receive UPPER_WRITE_ADDRESS and (24 downto 12) will receive '0'        
        BUFFER_ADDRESS_REG0_ns(INSTRUCTION_BIT_POSITION-1 downto 0) <= UPPER_WRITE_ADDRESS_v(INSTRUCTION_BIT_POSITION-1 downto 0);
        BUFFER_ADDRESS_REG0_ns(BUFFER_ADDRESS_WIDTH-1 downto INSTRUCTION_BIT_POSITION) <= (others => '0');
        
        if SLAVE_WRITE_EN = '1' then
            if UPPER_WRITE_ADDRESS_v(BUFFER_BIT_POSITION) = '0' then -- Weight space (Escrita do peso)
                WEIGHT_ENABLE_ON_WRITE_REG0_ns <= '1'; -- Permite a escrita byte por byte 
                
                for i in 0 to MATRIX_WIDTH-1 loop
                        if i/4 = to_integer(unsigned(LOWER_WRITE_ADDRESS_v)) then
                            if S_AXI_WSTRB(i mod 4) = '1' then -- Preenchimento dos bits de permiçao de escrita por byte
                                WEIGHT_WRITE_ENABLE_REG0_ns(i) <= '1';
                            else
                                WEIGHT_WRITE_ENABLE_REG0_ns(i) <= '0';
                            end if;
                        else
                            WEIGHT_WRITE_ENABLE_REG0_ns(i) <= '0';
                        end if;
                end loop;
                
                INSTRUCTION_WRITE_EN <= "000"; -- Desativa a escrita na fifo
                BUFFER_ENABLE_ON_WRITE_REG0_ns <= '0'; -- Sinaliza que o buffer nao esta ativo em escrita
                BUFFER_WRITE_ENABLE_REG0_ns <= (others => '0'); -- Escrita no Unified Buffer é desativada
                WRITE_ACCEPT <= '1'; -- Ativa para passar para proxima fase na FSM: WRITE_RESPONSE

            elsif UPPER_WRITE_ADDRESS_v(INSTRUCTION_BIT_POSITION) = '0' then -- Buffer space (Escrita BUFFER)
                BUFFER_ENABLE_ON_WRITE_REG0_ns <= '1'; -- Sinaliza que o Buffer esta ativo em escrita
                
                for i in 0 to MATRIX_WIDTH-1 loop
                        if i/4 = to_integer(unsigned(LOWER_WRITE_ADDRESS_v)) then
                            if S_AXI_WSTRB(i mod 4) = '1' then -- Preenchimento dos bits de permiçao de escrita por byte
                                BUFFER_WRITE_ENABLE_REG0_ns(i) <= '1';
                            else
                                BUFFER_WRITE_ENABLE_REG0_ns(i) <= '0';
                            end if;
                        else
                            BUFFER_WRITE_ENABLE_REG0_ns(i) <= '0';
                        end if;
                end loop;
                
                WEIGHT_ENABLE_ON_WRITE_REG0_ns <= '0'; -- A Escrita de peso e desativada
                WEIGHT_WRITE_ENABLE_REG0_ns <= (others => '0'); -- Escrita no Weight buffer e desativada
                INSTRUCTION_WRITE_EN <= "000"; -- Desativa a escrita na fifo
                WRITE_ACCEPT <= '1';-- Ativa para passar para proxima fase na FSM: WRITE_RESPONSE
            else -- Instruction space
                case to_integer(unsigned(LOWER_INSTRUCTION_ADDRESS_v)) is
                    when 1 => -- Carrega the Lower Instruction
                        if INSTRUCTION_FULL = '1' then
                            INSTRUCTION_WRITE_EN <= "000";
                            WRITE_ACCEPT <= '0';
                        else
                            INSTRUCTION_WRITE_EN <= "100";
                            WRITE_ACCEPT <= '1';
                        end if;
                    when 2 => -- Carrega the Middle instruction
                        if INSTRUCTION_FULL = '1' then
                            INSTRUCTION_WRITE_EN <= "000";
                            WRITE_ACCEPT <= '0';
                        else
                            INSTRUCTION_WRITE_EN <= "010";
                            WRITE_ACCEPT <= '1';
                        end if;
                    when 3 => -- Carrega the Upper instruction
                        if INSTRUCTION_FULL = '1' then
                            INSTRUCTION_WRITE_EN <= "000";
                            WRITE_ACCEPT <= '0';
                        else
                            INSTRUCTION_WRITE_EN <= "001";
                            WRITE_ACCEPT <= '1';
                        end if;
                    when others =>
                        INSTRUCTION_WRITE_EN <= "000";
                        WRITE_ACCEPT <= '1';
                end case;
                
                -- Tanto a escrita do Weight quanto do buffer sao desativadas
                WEIGHT_ENABLE_ON_WRITE_REG0_ns <= '0';
                WEIGHT_WRITE_ENABLE_REG0_ns <= (others => '0');
                BUFFER_ENABLE_ON_WRITE_REG0_ns <= '0';
                BUFFER_WRITE_ENABLE_REG0_ns <= (others => '0');
            end if;
        else
            INSTRUCTION_WRITE_EN <= "000";
            WEIGHT_ENABLE_ON_WRITE_REG0_ns <= '0';
            WEIGHT_WRITE_ENABLE_REG0_ns <= (others => '0');
            BUFFER_ENABLE_ON_WRITE_REG0_ns <= '0';
            BUFFER_WRITE_ENABLE_REG0_ns <= (others => '0');
            WRITE_ACCEPT <= '1';
        end if;
    end process TPU_WRITE;


    --Inputs
        -- Slave_Read_EN <-- FSM
        -- Read_ADDRESS_cs <-- S_AXI_ARADDR(C_S_AXI_ADDR_WIDTH-1 downto 2);
        -- UPPER_READ_ADDRESS_DELAY2_cs <-- (inicia com 0) <-- TPU_READ
        -- LOWER_READ_ADDRESS_DELAY2_cs <-- (inicia com 0) <-- TPU_READ
        -- BUFFER_READ_PORT <-- TPU_i
        -- RUNTIME_COUNT <-- TPU_i
    TPU_READ:
	process (SLAVE_READ_EN, READ_ADDRESS_cs, UPPER_READ_ADDRESS_DELAY2_cs, LOWER_READ_ADDRESS_DELAY2_cs, BUFFER_READ_PORT, RUNTIME_COUNT)
        variable UPPER_READ_ADDRESS_v : std_logic_vector(ADDRESS_WIDTH-MATRIX_ADDRESS_WIDTH-1 downto 0);
        variable LOWER_READ_ADDRESS_v : std_logic_vector(MATRIX_ADDRESS_WIDTH-1 downto 0);
    begin
        UPPER_READ_ADDRESS_v := READ_ADDRESS_cs(ADDRESS_WIDTH-1 downto MATRIX_ADDRESS_WIDTH); -- (9 downto 2)
        LOWER_READ_ADDRESS_v := READ_ADDRESS_cs(MATRIX_ADDRESS_WIDTH-1 downto 0); -- (1 downto 0)
        
        -- Os endereços de leitura mais atuais sao mandados para um DELAY
        UPPER_READ_ADDRESS_DELAY0_ns <= UPPER_READ_ADDRESS_v;
        LOWER_READ_ADDRESS_DELAY0_ns <= LOWER_READ_ADDRESS_v;
        
        -- (11 downto 0) will receive UPPER_WRITE_ADDRESS and (24 downto 12) will receive '0'        
        BUFFER_READ_ADDRESS(INSTRUCTION_BIT_POSITION-1 downto 0) <= UPPER_READ_ADDRESS_v(INSTRUCTION_BIT_POSITION-1 downto 0);
        BUFFER_READ_ADDRESS(BUFFER_ADDRESS_WIDTH-1 downto INSTRUCTION_BIT_POSITION) <= (others => '0');
        
        if SLAVE_READ_EN = '1' then
            if UPPER_READ_ADDRESS_v(BUFFER_BIT_POSITION) = '1' and UPPER_READ_ADDRESS_v(INSTRUCTION_BIT_POSITION) = '0' then
                BUFFER_ENABLE_ON_READ <= '1'; -- Buffer estara sendo lido
            else
                BUFFER_ENABLE_ON_READ <= '0';
            end if;
        else
            BUFFER_ENABLE_ON_READ <= '0';
        end if;
        
        -- Read
        if UPPER_READ_ADDRESS_DELAY2_cs(BUFFER_BIT_POSITION) = '0' then -- Weight space
            READ_DATA_ns <= (others => '0'); -- Weights are write-only (so são lidos na arquitetura da TPU)
        elsif UPPER_READ_ADDRESS_DELAY2_cs(INSTRUCTION_BIT_POSITION) = '0' then -- Buffer space
            for i in 0 to 3 loop
                if to_integer(unsigned(LOWER_READ_ADDRESS_DELAY2_cs)) * 4 + i > MATRIX_WIDTH-1 then
                    READ_DATA_ns((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH) <= (others => '0'); -- Passou do tamanho (ERRO)
                else
                    READ_DATA_ns((i+1)*BYTE_WIDTH-1 downto i*BYTE_WIDTH) <= BUFFER_READ_PORT(to_integer(unsigned(LOWER_READ_ADDRESS_DELAY2_cs)) * 4 + i); -- Le os dados 
                end if;
            end loop;
        else -- Instruction space
            case to_integer(unsigned(LOWER_READ_ADDRESS_DELAY2_cs)) is
                when 0 =>
                    READ_DATA_ns <= RUNTIME_COUNT;
                when others =>
                    READ_DATA_ns <= (others => '0');
            end case;
        end if;
	end process TPU_READ; 
    
    
    SEQ_LOG:
    process(S_AXI_ACLK) is
    begin
        if S_AXI_ACLK'event and S_AXI_ACLK = '1' then
            if S_AXI_ARESETN = '0' then
                STATE_cs <= IDLE;
                READ_DATA_DELAY_cs  <= (others => '0');
                WRITE_ADDRESS_cs    <= (others => '0');
                READ_ADDRESS_cs     <= (others => '0');
                WRITE_DATA_cs       <= (others => '0');
                READ_DATA_cs        <= (others => '0');
                UPPER_READ_ADDRESS_DELAY0_cs <= (others => '0');
                UPPER_READ_ADDRESS_DELAY1_cs <= (others => '0');
                UPPER_READ_ADDRESS_DELAY2_cs <= (others => '0');
                LOWER_READ_ADDRESS_DELAY0_cs <= (others => '0');
                LOWER_READ_ADDRESS_DELAY1_cs <= (others => '0');
                LOWER_READ_ADDRESS_DELAY2_cs <= (others => '0');
                WEIGHT_WRITE_PORT_REG0_cs   <= (others => (others => '0'));
                WEIGHT_WRITE_PORT_REG1_cs   <= (others => (others => '0'));
                WEIGHT_ADDRESS_REG0_cs      <= (others => '0');
                WEIGHT_ADDRESS_REG1_cs      <= (others => '0');
                WEIGHT_WRITE_ENABLE_REG0_cs <= (others => '0');
                WEIGHT_WRITE_ENABLE_REG1_cs <= (others => '0');
                WEIGHT_ENABLE_ON_WRITE_REG0_cs <= '0';
                WEIGHT_ENABLE_ON_WRITE_REG1_cs <= '0';
                BUFFER_WRITE_PORT_REG0_cs   <= (others => (others => '0'));
                BUFFER_WRITE_PORT_REG1_cs   <= (others => (others => '0'));
                BUFFER_ADDRESS_REG0_cs      <= (others => '0');
                BUFFER_ADDRESS_REG1_cs      <= (others => '0');
                BUFFER_WRITE_ENABLE_REG0_cs <= (others => '0');
                BUFFER_WRITE_ENABLE_REG1_cs <= (others => '0');
                BUFFER_ENABLE_ON_WRITE_REG0_cs <= '0';
                BUFFER_ENABLE_ON_WRITE_REG1_cs <= '0';
            else
                if WRITE_ADDRESS_EN = '1' then
                    WRITE_ADDRESS_cs <= WRITE_ADDRESS_ns;
                end if;
                
                if READ_ADDRESS_EN = '1' then
                    READ_ADDRESS_cs <= READ_ADDRESS_ns;
                end if;
                
                if WRITE_DATA_EN = '1' then
                    WRITE_DATA_cs <= WRITE_DATA_ns;
                end if;
                
                if READ_DATA_EN = '1' then
                    READ_DATA_cs <= READ_DATA_ns;
                end if;
            
                STATE_cs <= STATE_ns;
                READ_DATA_DELAY_cs <= READ_DATA_DELAY_ns;
                
                UPPER_READ_ADDRESS_DELAY0_cs <= UPPER_READ_ADDRESS_DELAY0_ns;
                UPPER_READ_ADDRESS_DELAY1_cs <= UPPER_READ_ADDRESS_DELAY1_ns;
                UPPER_READ_ADDRESS_DELAY2_cs <= UPPER_READ_ADDRESS_DELAY2_ns;

                LOWER_READ_ADDRESS_DELAY0_cs <= LOWER_READ_ADDRESS_DELAY0_ns;
                LOWER_READ_ADDRESS_DELAY1_cs <= LOWER_READ_ADDRESS_DELAY1_ns;
                LOWER_READ_ADDRESS_DELAY2_cs <= LOWER_READ_ADDRESS_DELAY2_ns;
                
                -- Peso a ser a escrito
                WEIGHT_WRITE_PORT_REG0_cs   <= WEIGHT_WRITE_PORT_REG0_ns;
                WEIGHT_WRITE_PORT_REG1_cs   <= WEIGHT_WRITE_PORT_REG1_ns;
                
                -- Endereço onde sera escrito
                WEIGHT_ADDRESS_REG0_cs      <= WEIGHT_ADDRESS_REG0_ns;
                WEIGHT_ADDRESS_REG1_cs      <= WEIGHT_ADDRESS_REG1_ns;
                
                -- Ativador de escrita por byte
                WEIGHT_WRITE_ENABLE_REG0_cs <= WEIGHT_WRITE_ENABLE_REG0_ns;
                WEIGHT_WRITE_ENABLE_REG1_cs <= WEIGHT_WRITE_ENABLE_REG1_ns;
                
                -- Ativador de escrita  principal
                WEIGHT_ENABLE_ON_WRITE_REG0_cs <= WEIGHT_ENABLE_ON_WRITE_REG0_ns;
                WEIGHT_ENABLE_ON_WRITE_REG1_cs <= WEIGHT_ENABLE_ON_WRITE_REG1_ns;
                
                -- Dado a ser a escrito
                BUFFER_WRITE_PORT_REG0_cs   <= BUFFER_WRITE_PORT_REG0_ns;
                BUFFER_WRITE_PORT_REG1_cs   <= BUFFER_WRITE_PORT_REG1_ns;
                
                -- Endereço onde sera escrito
                BUFFER_ADDRESS_REG0_cs      <= BUFFER_ADDRESS_REG0_ns;
                BUFFER_ADDRESS_REG1_cs      <= BUFFER_ADDRESS_REG1_ns;
                
                -- Ativador de escrita por byte
                BUFFER_WRITE_ENABLE_REG0_cs <= BUFFER_WRITE_ENABLE_REG0_ns;
                BUFFER_WRITE_ENABLE_REG1_cs <= BUFFER_WRITE_ENABLE_REG1_ns;
                
                -- Ativador de escrita toda palavra
                BUFFER_ENABLE_ON_WRITE_REG0_cs <= BUFFER_ENABLE_ON_WRITE_REG0_ns;
                BUFFER_ENABLE_ON_WRITE_REG1_cs <= BUFFER_ENABLE_ON_WRITE_REG1_ns;
            end if;
        end if;
    end process SEQ_LOG;
end arch_imp;
