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

--! @file UNIFIED_BUFFER.vhdl
--! @author Jonas Fuhrmann

-- Este componente inclui o Unified Buffer, um buffer usado para Inputs da camada da rede neural
-- O buffer pode armazenar informações a partir do master (Host System). Os dados armazenados podem então serem usados para multiplicação de matrizes,
-- Apos ativação, o dado calculado pode ser re-armazenado para a proxima camada da rede neural.

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity UNIFIED_BUFFER is
    generic(
        MATRIX_WIDTH    : natural := 8;
        -- How many tiles can be saved
        TILE_WIDTH      : natural := 4096 --!< The depth of the buffer.
    );
    port(
        CLK, RESET      : in  std_logic;
        ENABLE          : in  std_logic;
        
        -- Master port - Possui maior importancia que outras portas
        MASTER_ADDRESS      : in  BUFFER_ADDRESS_TYPE; --!< Endereço do Mestre(host), Possui maior importancia que outros Endereçamentos.
        MASTER_EN           : in  std_logic; --!< Mestre(host) enable, Possui maior importancia que outras Ativações.
        MASTER_WRITE_EN     : in  std_logic_vector(0 to MATRIX_WIDTH-1); --!< Mestre(host) write enable, Possui maior importancia que outras ativações de escrita.
        MASTER_WRITE_PORT   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Mestre(host) write port, Possui maior importancia que outras Portas de Escrita.
        MASTER_READ_PORT    : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Mestre(host) read port, Possui maior importancia que outras Portas de Leitura.

        -- Port0, so é possivel a realização de leitura
        ADDRESS0        : in  BUFFER_ADDRESS_TYPE; --!< Endereço da porta 0.
        EN0             : in  std_logic; --!< Ativação da porta 0.
        READ_PORT0      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Leitura da porta 0.

        -- Port1, só é possivel a realização de escrita.
        ADDRESS1        : in  BUFFER_ADDRESS_TYPE; --!< Endereço da porta 1.
        EN1             : in  std_logic; --!< Ativação da porta 1.
        WRITE_EN1       : in  std_logic; --!< Ativação de escrita da porta 1.
        WRITE_PORT1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) --!< Escrita da porta 1.
    );
end entity UNIFIED_BUFFER;

--! @brief The architecture of the unified buffer component.
architecture BEH of UNIFIED_BUFFER is
    -- Arrays de registradores 8x8 para leitura das portas 0
    signal READ_PORT0_REG0_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (0 to MATRIX_WIDTH-1 => (BYTE_WIDTH-1 downto 0 => '0'));
    signal READ_PORT0_REG0_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal READ_PORT0_REG1_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (0 to MATRIX_WIDTH-1 => (BYTE_WIDTH-1 downto 0 => '0'));
    signal READ_PORT0_REG1_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- Arrays de registradores 8x8 para leitura das portas Mestre
    signal MASTER_READ_PORT_REG0_cs : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (0 to MATRIX_WIDTH-1 => (BYTE_WIDTH-1 downto 0 => '0'));
    signal MASTER_READ_PORT_REG0_ns : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal MASTER_READ_PORT_REG1_cs : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (0 to MATRIX_WIDTH-1 => (BYTE_WIDTH-1 downto 0 => '0'));
    signal MASTER_READ_PORT_REG1_ns : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);

    -- Escrita da Porta 1 e Leitura da Porta 0 convertidos para bits
    signal WRITE_PORT1_BITS : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    signal READ_PORT0_BITS  : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);

    -- Escrita e Leitura da Porta Mestre convertidos para bits
    signal MASTER_WRITE_PORT_BITS   : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    signal MASTER_READ_PORT_BITS    : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    
    -- Endereços de maior importancia array de 24bits e flags 
    signal ADDRESS0_OVERRIDE    : BUFFER_ADDRESS_TYPE; -- Somente algumas partes do dado é modificada
    signal ADDRESS1_OVERRIDE    : BUFFER_ADDRESS_TYPE; -- todo endereço é modificado
    
    signal EN0_OVERRIDE : std_logic;
    signal EN1_OVERRIDE : std_logic;
    
    type RAM_TYPE is array(0 to TILE_WIDTH-1) of std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    
    constant TILE_WIDTH_TEST : natural := 4095;
    constant TRASH_DATA : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0) := (others => '0');
    shared variable RAM  : RAM_TYPE
    --synthesis translate_off
        :=
        -- Test values
        (
            BYTE_ARRAY_TO_BITS((x"7F", x"7E", x"7D", x"7C", x"7B", x"7A", x"79", x"78")),
            BYTE_ARRAY_TO_BITS((x"71", x"70", x"6F", x"6E", x"6D", x"6C", x"6B", x"6A")),
            BYTE_ARRAY_TO_BITS((x"63", x"62", x"61", x"60", x"5F", x"5E", x"5D", x"5C")),
            BYTE_ARRAY_TO_BITS((x"55", x"54", x"53", x"52", x"51", x"50", x"4F", x"4E")),
            BYTE_ARRAY_TO_BITS((x"47", x"46", x"45", x"44", x"43", x"42", x"41", x"40")),
            BYTE_ARRAY_TO_BITS((x"39", x"38", x"37", x"36", x"35", x"34", x"33", x"32")),
            BYTE_ARRAY_TO_BITS((x"2B", x"2A", x"29", x"28", x"27", x"26", x"25", x"24")),
            BYTE_ARRAY_TO_BITS((x"1D", x"1C", x"1B", x"1A", x"19", x"18", x"17", x"16")),
            BYTE_ARRAY_TO_BITS((x"0F", x"0E", x"0D", x"0C", x"0B", x"0A", x"09", x"08")),
            BYTE_ARRAY_TO_BITS((x"01", x"00", x"FF", x"FE", x"FD", x"FC", x"FB", x"FA")),
            BYTE_ARRAY_TO_BITS((x"F3", x"F2", x"F1", x"F0", x"EF", x"EE", x"ED", x"EC")),
            BYTE_ARRAY_TO_BITS((x"E5", x"E4", x"E3", x"E2", x"E1", x"E0", x"DF", x"DE")),
            BYTE_ARRAY_TO_BITS((x"D7", x"D6", x"D5", x"D4", x"D3", x"D2", x"D1", x"D0")),
            BYTE_ARRAY_TO_BITS((x"C9", x"C8", x"C7", x"C6", x"C5", x"C4", x"C3", x"C2")),
            others => (others => '0')
        )
    --synthesis translate_on
    ;
    attribute ram_style        : string;
    attribute ram_style of RAM : variable is "block";
begin
    -- Carregamento do dado para escrita apos converção para binário
    WRITE_PORT1_BITS        <= BYTE_ARRAY_TO_BITS(WRITE_PORT1); 
    MASTER_WRITE_PORT_BITS  <= BYTE_ARRAY_TO_BITS(MASTER_WRITE_PORT);

    -- Fila do processo de leitura
    READ_PORT0_REG0_ns  <= BITS_TO_BYTE_ARRAY(READ_PORT0_BITS); -- Leitura de dados da memoria e converção para byte
    READ_PORT0_REG1_ns  <= READ_PORT0_REG0_cs; -- READ_PORT0_REG1_ns <- READ_PORT0_REG0_cs <- READ_PORT0_REG0_ns
    READ_PORT0          <= READ_PORT0_REG1_cs; -- READ_PORT0 (SAIDA) <- READ_PORT0_REG1_cs <- READ_PORT0_REG1_ns <- READ_PORT0_REG0_cs <- READ_PORT0_REG0_ns

    MASTER_READ_PORT_REG0_ns    <= BITS_TO_BYTE_ARRAY(MASTER_READ_PORT_BITS); -- Leitura de dados da memoria e converção para byte
    MASTER_READ_PORT_REG1_ns    <= MASTER_READ_PORT_REG0_cs; -- MASTER_READ_PORT_REG1_ns <- MASTER_READ_PORT_REG0_cs <- MASTER_READ_PORT_REG0_ns
    MASTER_READ_PORT            <= MASTER_READ_PORT_REG1_cs; -- MASTER_READ_PORT <- MASTER_READ_PORT_REG1_cs <- MASTER_READ_PORT_REG1_ns <- MASTER_READ_PORT_REG0_cs <- MASTER_READ_PORT_REG0_ns
    
    OVERRIDE:
    process(MASTER_EN, EN0, EN1, MASTER_ADDRESS, ADDRESS0, ADDRESS1) is
    begin
        -- Se MASTER_EN esta ativo então os sinais de OVERRIDE de EN0 e EN1 são ativados e o endereço Prioritario é copiado para utilização
        -- Senão o processo de escrita e/ou leitura continuam com os endereços nao prioritarios
        if MASTER_EN = '1' then
            EN0_OVERRIDE <= MASTER_EN; -- 1
            EN1_OVERRIDE <= MASTER_EN; -- 1
            ADDRESS0_OVERRIDE <= MASTER_ADDRESS;
            ADDRESS1_OVERRIDE <= MASTER_ADDRESS;
        else
            EN0_OVERRIDE <= EN0; -- 0
            EN1_OVERRIDE <= EN1; -- 1
            ADDRESS0_OVERRIDE <= ADDRESS0;
            ADDRESS1_OVERRIDE <= ADDRESS1;
        end if;
    end process OVERRIDE;
    

    PORT0:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if EN0_OVERRIDE = '1' then
                --synthesis translate_off
                if to_integer(unsigned(ADDRESS0_OVERRIDE)) < TILE_WIDTH then
                --synthesis translate_on
                    for i in 0 to MATRIX_WIDTH-1 loop
                        if MASTER_WRITE_EN(i) = '1' then
                            RAM(to_integer(unsigned(ADDRESS0_OVERRIDE)))((i + 1) * BYTE_WIDTH - 1 downto i * BYTE_WIDTH) := MASTER_WRITE_PORT_BITS((i + 1) * BYTE_WIDTH - 1 downto i * BYTE_WIDTH);
                        end if;
                    end loop;
                    READ_PORT0_BITS <= RAM(to_integer(unsigned(ADDRESS0_OVERRIDE)));
                --synthesis translate_off
                end if;
                --synthesis translate_on
            end if;
        end if;
    end process PORT0;
    
    -- Processo de escrita/leitura de dados, a modificação ocorre, caso as flags estejam ativas, em todo o dado contido no endereço.
    -- O dado é lido para MASTER_READ_PORT_BITS
    PORT1:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if EN1_OVERRIDE = '1' then
                --synthesis translate_off
                if to_integer(unsigned(ADDRESS1_OVERRIDE)) < TILE_WIDTH then
                --synthesis translate_on
                    if WRITE_EN1 = '1' then
                        RAM(to_integer(unsigned(ADDRESS1_OVERRIDE))) := WRITE_PORT1_BITS;
                    end if;
                    MASTER_READ_PORT_BITS <= RAM(to_integer(unsigned(ADDRESS1_OVERRIDE)));
                --synthesis translate_off
                end if;
                --synthesis translate_on
            end if;
        end if;
    end process PORT1;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                READ_PORT0_REG0_cs <= (others => (others => '0'));
                READ_PORT0_REG1_cs <= (others => (others => '0'));
                MASTER_READ_PORT_REG0_cs <= (others => (others => '0'));
                MASTER_READ_PORT_REG1_cs <= (others => (others => '0'));
            else
                if ENABLE = '1' then
                    READ_PORT0_REG0_cs <= READ_PORT0_REG0_ns;
                    READ_PORT0_REG1_cs <= READ_PORT0_REG1_ns;
                    MASTER_READ_PORT_REG0_cs <= MASTER_READ_PORT_REG0_ns;
                    MASTER_READ_PORT_REG1_cs <= MASTER_READ_PORT_REG1_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;