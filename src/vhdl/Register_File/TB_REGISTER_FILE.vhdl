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
    
entity TB_REGISTER_FILE is
end entity TB_REGISTER_FILE;

architecture BEH of TB_REGISTER_FILE is
    component DUT is
        generic(
            MATRIX_WIDTH    : natural := 256;
            REGISTER_DEPTH  : natural := 4096
        );
        port(
            CLK, RESET          : in  std_logic;
            ENABLE              : in  std_logic;
            
            WRITE_ADDRESS       : in  HALFWORD_TYPE;
            WRITE_PORT          : in  WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WRITE_ENABLE        : in  std_logic;
            
            ACCUMULATE          : in  std_logic;
            
            READ_ADDRESS        : in  HALFWORD_TYPE;
            READ_PORT           : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1)
        );
    end component DUT;
    for all : DUT use entity WORK.REGISTER_FILE(BEH);
    
    constant MATRIX_WIDTH   : natural := 8;
    signal CLK, RESET       : std_logic;
    signal ENABLE           : std_logic;
    signal WRITE_ADDRESS    : HALFWORD_TYPE;
    signal WRITE_PORT       : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WRITE_ENABLE     : std_logic;
    signal ACCUMULATE       : std_logic;
    signal READ_ADDRESS     : HALFWORD_TYPE;
    signal READ_PORT        : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- for clock gen
    constant clock_period   : time := 10 ns; -- O chaveamento do clock ocorre a cada 10ns
    signal stop_the_clock   : boolean; 
begin
    DUT_i : DUT
    generic map(
        MATRIX_WIDTH => MATRIX_WIDTH,
        REGISTER_DEPTH => MATRIX_WIDTH
    )
    port map(
        CLK             => CLK,
        RESET           => RESET,
        ENABLE          => ENABLE,
        WRITE_ADDRESS   => WRITE_ADDRESS,
        WRITE_PORT      => WRITE_PORT,
        WRITE_ENABLE    => WRITE_ENABLE,
        ACCUMULATE      => ACCUMULATE,
        READ_ADDRESS    => READ_ADDRESS,
        READ_PORT       => READ_PORT
    );
    
    -- Processo de ativação do clock, ele fica 5ns ativado e 5ns desativado
    CLOCK_GEN: 
    process
    begin
        while not stop_the_clock loop
          CLK <= '0', '1' after clock_period / 2; -- Clock iniciado com 0, muda para 1 apos 5ns
          wait for clock_period; -- Esoera por 10ns
        end loop;
        CLK <= '0';
        wait; 
    end process CLOCK_GEN;

    STIMULUS:
    process is
    begin
        -- Inicialização dos registros e sinais 
        -- Espera ate que ocorra um evento de clock e o sinal do clock seja 1
        stop_the_clock <= false;
        RESET <= '0';
        ENABLE <= '0'; -- Impede que os acumuladores ativem
        WRITE_ADDRESS <= (others => '0');
        WRITE_PORT <= (others => (others => '0'));
        WRITE_ENABLE <= '1';
        ACCUMULATE <= '0';
        READ_ADDRESS <= (others => '0');
        wait until '1'=CLK and CLK'event;

        -- Operação de Reset
        -- O Teste inicia com RESET ativado, impedindo de ocorrer operações.
        RESET <= '1';
        wait until '1'=CLK and CLK'event;
        RESET <= '0';
        wait until '1'=CLK and CLK'event;
        ENABLE <= '1'; -- Permite que os acumuladores recebam informações

        -- Teste de armazenamento de valores
        for i in 0 to MATRIX_WIDTH-1 loop
            for j in 0 to MATRIX_WIDTH-1 loop
                report "inside";
                -- WritePort recebe um barramento de valor "i" convertido para unsigned no tamanho 32bits
                WRITE_PORT(j) <= std_logic_vector(to_unsigned(i, 4*BYTE_WIDTH));
            end loop;
            -- Recebe o endereço onde sera escrito no acumulador, tamanho 16 bits
            WRITE_ADDRESS <= std_logic_vector(to_unsigned(i, 2*BYTE_WIDTH)); 
            WRITE_ENABLE <= '1'; -- Ativa a permissao de escrita
            wait until '1'=CLK and CLK'event;
        end loop;
        
        WRITE_ENABLE <= '0'; -- Desativa a permissao de escrita
        
        -- Le os dados que acabaram de ser colocados no barramento dos acumuladores
        for i in 0 to MATRIX_WIDTH-1 loop
            -- Lê o endereço onde sera escrito no acumulador, tamanho 16 bits
            READ_ADDRESS <= std_logic_vector(to_unsigned(i, 2*BYTE_WIDTH));
            for j in 0 to MATRIX_WIDTH-1 loop
                wait for 1 ns;
                if READ_PORT(j) /= std_logic_vector(to_unsigned(i, 4*BYTE_WIDTH)) then
                    report "Test failed at saving!" severity ERROR;
                    --stop_the_clock <= true;
                    --wait;
                end if;
            end loop;
            wait until '1'=CLK and CLK'event;
        end loop;
        
        -- Teste dos valores acumulados
        ACCUMULATE <= '1'; -- Permite que os dados das portas sejam acumulados

        -- Inserção dos dados no barramento que serao testados
        for i in 0 to MATRIX_WIDTH-1 loop
            for j in 0 to MATRIX_WIDTH-1 loop
                -- WritePort recebe um barramento de valor "j" convertido para unsigned no tamanho 32bits
                WRITE_PORT(j) <= std_logic_vector(to_unsigned(j, 4*BYTE_WIDTH));
            end loop;
            -- Recebe o endereço onde sera escrito no acumulador, tamanho 16 bits
            WRITE_ADDRESS <= std_logic_vector(to_unsigned(i, 2*BYTE_WIDTH));
            WRITE_ENABLE <= '1';
            wait until '1'=CLK and CLK'event;
            --WRITE_PORT <= (others => (others => '0')); -- accumulate 0 - register will count up on checking otherwise
        end loop;
        WRITE_ENABLE <= '0';
        
        --Verifica se os dados colocados estão corretos
        for i in 0 to MATRIX_WIDTH-1 loop
            READ_ADDRESS <= std_logic_vector(to_unsigned(i, 2*BYTE_WIDTH));
            for j in 0 to MATRIX_WIDTH-1 loop
                wait for 1 ns;
                if READ_PORT(j) /= std_logic_vector(to_unsigned(i+j, 4*BYTE_WIDTH)) then
                    report "Test failed at accumulation!" severity ERROR;
                    --stop_the_clock <= true;
                    --wait;
                end if;
            end loop;
            wait until '1'=CLK and CLK'event;
        end loop;
                
        report "Test was successful!" severity NOTE;
        
        stop_the_clock <= true;
        wait;
    end process STIMULUS;
    
end architecture BEH;