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

--! @file WEIGHT_BUFFER.vhdl
--! @author Jonas Fuhrmann
--! @brief This component includes the weight buffer, a buffer used for neural net weights.
--! @details The buffer can store data from the master (host system). The stored data can then be used for matrix multiplies.

-- O Weight FIFO é um Buffer circular que armazena os pesos da rede neural. Devido ao fato de ..
-- Para a Arquitetura Fermi, o Weight FIFO possui duas portas de leitura correspondente aos dois "WARPS" que estão sndo executados simultaneamente.
-- E cada porta fornece um pesso para 16 Unidades Logicas Aritimeticas.
-- A cada treinamento da rede neural, o peso ira se adaptar até conseguir chegar em um valor quase-otimo.
use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity WEIGHT_BUFFER is
    generic(
        MATRIX_WIDTH    : natural := 14;
        -- How many tiles can be saved
        TILE_WIDTH      : natural := 32768  --!< The depth of the buffer.
    );
    port(
        CLK, RESET      : in  std_logic;
        ENABLE          : in  std_logic;
        
        -- Port0
        ADDRESS0        : in  WEIGHT_ADDRESS_TYPE; -- Endereço da porta 0, vetor logico de tamanho 40
        EN0             : in  std_logic; -- ativação da porta 0.
        WRITE_EN0       : in  std_logic; -- ativação de escrita da porta 0.
        WRITE_PORT0     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Escrita de dados da porta 0.
        READ_PORT0      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Leitura de dados da porta 0.
        -- Port1
        ADDRESS1        : in  WEIGHT_ADDRESS_TYPE; -- Endereço da porta 1, vetor logico de tamanho 40
        EN1             : in  std_logic; -- Enable of porta 1.
        WRITE_EN1       : in  std_logic_vector(0 to MATRIX_WIDTH-1); -- ativação de escrita da porta 1. MODIFICADO <++++++++++++++++++++++++++++++++++++++++++++++++++++++++
        WRITE_PORT1     : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Escrita de dados da porta 1.
        READ_PORT1      : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) -- Leitura de dados da porta 1.
    );
end entity WEIGHT_BUFFER;

--! @brief The architecture of the weight buffer component.
architecture BEH of WEIGHT_BUFFER is
   -- Matriz de sinais logicos de tamanho 14 x 8: INICIO
    signal READ_PORT0_REG0_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal READ_PORT0_REG0_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal READ_PORT0_REG1_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal READ_PORT0_REG1_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    signal READ_PORT1_REG0_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal READ_PORT1_REG0_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal READ_PORT1_REG1_cs   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal READ_PORT1_REG1_ns   : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
   -- FIM

   -- Vetor de contendo os bits do dado a ser inserido, armazena o total de (MATRIX_WIDTH*BYTE_WIDTH-1) => 112 bits: INICIO
    signal WRITE_PORT0_BITS : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0); 
    signal WRITE_PORT1_BITS : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
   -- FIM

   -- Vetor de contendo os bits do dado a ser lido: INICIO
    signal READ_PORT0_BITS  : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    signal READ_PORT1_BITS  : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
   -- FIM

    constant TILE_WIDTH_TEST : natural := 32767;
    constant TRASH_DATA : std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0) := (others => '0');
   -- Memoria onde o dado será armazenado, sendo um array de Tile_WIDTH x ((MATRIX_WIDTH*BYTE_WIDTH-1) => 32768 x 112 bits
    type RAM_TYPE is array(0 to TILE_WIDTH-1) of std_logic_vector(MATRIX_WIDTH*BYTE_WIDTH-1 downto 0);
    shared variable RAM  : RAM_TYPE
    --synthesis translate_off
        :=
        -- Test values - Identity
        (
            0  => BYTE_ARRAY_TO_BITS((x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            1  => BYTE_ARRAY_TO_BITS((x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            2  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            3  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            4  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            5  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            6  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00", x"00")),
            7  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00", x"00")),
            8  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00", x"00")),
            9  => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00", x"00")),
            10 => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00", x"00")),
            11 => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00", x"00")),
            12 => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80", x"00")),
            13 => BYTE_ARRAY_TO_BITS((x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"00", x"80")),
            14 to TILE_WIDTH_TEST => TRASH_DATA
        )
    --synthesis translate_on
    ;
    
    attribute ram_style        : string;
    attribute ram_style of RAM : variable is "block";
begin
    -- Write_Port0 e Write_Port1 recebe o dado. O dado esta no formato 14 Byte e é convertido para um array de bits antes de ser atribuido
    WRITE_PORT0_BITS    <= BYTE_ARRAY_TO_BITS(WRITE_PORT0);
    WRITE_PORT1_BITS    <= BYTE_ARRAY_TO_BITS(WRITE_PORT1);
    
    -- Read_Port0 e Read_Port1 é recebe a saida da funcao BITS_TO_BYTE (o dado). O dado esta no formato 112 bits e é convertido para um array de bits antes de ser atribuido
    READ_PORT0_REG0_ns  <= BITS_TO_BYTE_ARRAY(READ_PORT0_BITS); 
    READ_PORT1_REG0_ns  <= BITS_TO_BYTE_ARRAY(READ_PORT1_BITS);
    -- Demais registros fazem o resto da FIFO para leitura da PORt0 e PORT1
    READ_PORT0_REG1_ns  <= READ_PORT0_REG0_cs;
    READ_PORT1_REG1_ns  <= READ_PORT1_REG0_cs;
    READ_PORT0          <= READ_PORT0_REG1_cs; -- Ultimo Registro da Port0
    READ_PORT1          <= READ_PORT1_REG1_cs; -- Ultimo Registro da Port1

    -- A Inserção de dados ocorre se, e somente se: O Endereço for valido e Tanto o Enable da port0 (EN0) e o Enable de Escrita (WRITE_EN0) estiverem ativados.
    -- A Leitura de dados ocorre se, e somente se: O Endereço for valido e o Enable da port0 (EN0) estiver ativado.
    PORT0:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if EN0 = '1' then --Se estiver ativado o ENABLE da port0
                --synthesis translate_off
                if to_integer(unsigned(ADDRESS0)) < TILE_WIDTH then --Se o endereço for menor que o tamanho do buffer
                --synthesis translate_on
                    if WRITE_EN0 = '1' then -- Se o ENABLE de escrita da port0 estiver ativado
                        RAM(to_integer(unsigned(ADDRESS0))) := WRITE_PORT0_BITS; -- É escrito na memoria na posição ADDRESS os bits do dado.
                    end if;
                    READ_PORT0_BITS <= RAM(to_integer(unsigned(ADDRESS0))); -- É Atribuido a READ_PORT0 os bits que estavam na memoria na posição ADDRESS0
                --synthesis translate_off
                end if;
                --synthesis translate_on
            end if;
        end if;
    end process PORT0;
    
    -- A Inserção de dados ocorre se, e somente se:
    -- A Leitura de dados ocorre se, e somente se: O Endereço for valido e o Enable da port0 (EN0) estiver ativado.
    PORT1:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if EN1 = '1' then --Se estiver ativado o ENABLE da port0
                --synthesis translate_off
                if to_integer(unsigned(ADDRESS1)) < TILE_WIDTH then --Se o endereço for menor que o tamanho do buffer
                --synthesis translate_on
                    for i in 0 to MATRIX_WIDTH-1 loop
                        if WRITE_EN1(i) = '1' then -- Se o ENABLE de escrita da port0 estiver ativado
                            RAM(to_integer(unsigned(ADDRESS1)))((i + 1) * BYTE_WIDTH - 1 downto i * BYTE_WIDTH) := WRITE_PORT1_BITS((i + 1) * BYTE_WIDTH - 1 downto i * BYTE_WIDTH);
                        end if;
                    end loop;
                    READ_PORT1_BITS <= RAM(to_integer(unsigned(ADDRESS1))); -- É Atribuido a READ_PORT1 os bits que estavam na memoria na posição ADDRESS1
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
                READ_PORT1_REG0_cs <= (others => (others => '0'));
                READ_PORT1_REG1_cs <= (others => (others => '0'));
            else
                if ENABLE = '1' then -- Se o WEIGHT_BUFFER estiver ativo
                    --FIFO dos Registradores de leitura 0 e 1
                     -- Dados lidos no processo PORT1 e PORT0
                    READ_PORT0_REG0_cs <= READ_PORT0_REG0_ns;
                    READ_PORT0_REG1_cs <= READ_PORT0_REG1_ns;
                     -- Dados nos registradores que serão levados para saida
                    READ_PORT1_REG0_cs <= READ_PORT1_REG0_ns;
                    READ_PORT1_REG1_cs <= READ_PORT1_REG1_ns;
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;