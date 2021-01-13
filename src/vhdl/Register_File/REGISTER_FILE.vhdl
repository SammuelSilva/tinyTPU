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

--! @file REGISTER_FILE.vhdl
--! @author Jonas Fuhrmann
--! @brief This component includes accumulator registers. Registers are accumulated or overwritten.
--! @details The register file constists of block RAM, which is redundant for a seperate accumulation port.

--! Carregando a blibioteca e os demais pacotes usados
--! ACUMULADORES SÃO REGISTROS, CUJO VALOR PODE SER SUBSTITUIDO OU SOMADO
--! OS BLOCOS DSP SÃO USADO PARA OS SOMADORES
--! A ENTRADA É ADICIONADA ATRAVES DO BLOCO DSP COM 0 OU COM O CONTEUDO DO "BRAM" NO MESMO ENDEREÇO E O RESULTADO SALVO NO ENDEREÇO TRANSFERIDO
--! COMO DUAS PORTAS (WRITE & READ) SAO NECESSARIAS PARA ISSO A MEMORIA PARA A SAIDA DOS ACUMULADORES DEVE SER REDUNDANTE, PARA SER POSSIVEL ADQUIRIR OUTRA PORTA.
--! BRAM -> BLOCK OF RAM
--! Criar condicional do chaveamento dos contadores de endereco

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

--! Criação da entidade Register File
entity REGISTER_FILE is
    -- Definiçao dos valores que definem a matrix 14x512 generica, ou seja, não possui modo (direction), que representa a memória
    generic(
        MATRIX_WIDTH    : natural := 14;
        REGISTER_DEPTH  : natural := 512
    );
    port(
        CLK, RESET          : in  std_logic; 
        ENABLE              : in  std_logic;
        
        WRITE_ADDRESS       : in  ACCUMULATOR_ADDRESS_TYPE; -- Vector do tipo logico que recebe o endereço de escrita
        WRITE_PORT          : in  WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Array que em conjunto com WORDTYPE (Vector do tipo logico) gera uma matriz
        WRITE_ENABLE        : in  std_logic;
        
        ACCUMULATE          : in  std_logic;
        
        READ_ADDRESS        : in  ACCUMULATOR_ADDRESS_TYPE;-- Vector do tipo logico que recebe o endereço de escrita
        READ_PORT           : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1)-- Array que em conjunto com WORDTYPE (Vector do tipo logico) gera uma matriz
    );
end entity REGISTER_FILE;

--! @brief The architecture of the register file.
architecture BEH of REGISTER_FILE is
    -- Criação do tipo ACCUMULATOR_TYPE como um array de tamanho REGISTER_DEPHT do tipo "std_logic_vector" (E uma matriz: REGISTER_DEPTH x 4*BYTE_WIDTH*MATRIX_WIDTH-1)
    type ACCUMULATOR_TYPE is array(0 to REGISTER_DEPTH-1) of std_logic_vector(4*BYTE_WIDTH*MATRIX_WIDTH-1 downto 0);

    -- Criação das variaveis compartilhadas, que podem ser utilizadas em outros processos
    shared variable ACCUMULATORS        : ACCUMULATOR_TYPE;
    shared variable ACCUMULATORS_COPY   : ACCUMULATOR_TYPE;
    
    attribute ram_style                 : string;
    attribute ram_style of ACCUMULATORS : variable is "block"; --Variavel é bloqueada? Ou é chamado um bloco? é uma Chave? 
    attribute ram_style of ACCUMULATORS_COPY : variable is "block";
    
    -- Memory port signals
    -- WORD_ARRAY_TYPE: 32 bits
    signal ACC_WRITE_EN         : std_logic;
    signal ACC_WRITE_ADDRESS    : ACCUMULATOR_ADDRESS_TYPE; -- Vector do tipo logico que recebe o endereço de escrita 
    signal ACC_READ_ADDRESS     : ACCUMULATOR_ADDRESS_TYPE;  -- Vector do tipo logico que recebe o endereço de leitura 
    signal ACC_ACCU_ADDRESS     : ACCUMULATOR_ADDRESS_TYPE; 
    signal ACC_WRITE_PORT       : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Array que em conjunto com WORDTYPE (Vector do tipo logico) gera uma matriz
    signal ACC_READ_PORT        : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal ACC_ACCUMULATE_PORT  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- Digital Signal Processing (DSP) signals
    signal DSP_ADD_PORT0_cs     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal DSP_ADD_PORT0_ns     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal DSP_ADD_PORT1_cs     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal DSP_ADD_PORT1_ns     : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal DSP_RESULT_PORT_cs   : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal DSP_RESULT_PORT_ns   : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal DSP_PIPE0_cs         : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal DSP_PIPE0_ns         : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal DSP_PIPE1_cs         : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal DSP_PIPE1_ns         : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- Pipeline registers
    signal ACCUMULATE_PORT_PIPE0_cs : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal ACCUMULATE_PORT_PIPE0_ns : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal ACCUMULATE_PORT_PIPE1_cs : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal ACCUMULATE_PORT_PIPE1_ns : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- Sinais que definem qual porta sera ativada para escrita
    signal ACCUMULATE_PIPE_cs   : std_logic_vector(0 to 2) := (others => '0'); -- (0 to 2) == 00
    signal ACCUMULATE_PIPE_ns   : std_logic_vector(0 to 2);
    
    signal WRITE_PORT_PIPE0_cs  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal WRITE_PORT_PIPE0_ns  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WRITE_PORT_PIPE1_cs  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal WRITE_PORT_PIPE1_ns  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WRITE_PORT_PIPE2_cs  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    signal WRITE_PORT_PIPE2_ns  : WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    
    -- Sinais que definem qual pipeline sera ativado para escrita
    signal WRITE_ENABLE_PIPE_cs : std_logic_vector(0 to 5) := (others => '0'); -- (0 to 5) == 00000
    signal WRITE_ENABLE_PIPE_ns : std_logic_vector(0 to 5);
    
    -- Os Endereços onde, caso esteja ativado, sera escrito
    -- ACCUMULATOR_ADDRESS_TYPE: 16 bits
    signal WRITE_ADDRESS_PIPE0_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE0_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal WRITE_ADDRESS_PIPE1_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE1_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal WRITE_ADDRESS_PIPE2_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE2_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal WRITE_ADDRESS_PIPE3_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE3_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal WRITE_ADDRESS_PIPE4_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE4_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal WRITE_ADDRESS_PIPE5_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal WRITE_ADDRESS_PIPE5_ns : ACCUMULATOR_ADDRESS_TYPE;
    
    -- Os Endereços onde, caso esteja ativado, sera lido 
    signal READ_ADDRESS_PIPE0_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE0_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal READ_ADDRESS_PIPE1_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE1_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal READ_ADDRESS_PIPE2_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE2_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal READ_ADDRESS_PIPE3_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE3_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal READ_ADDRESS_PIPE4_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE4_ns : ACCUMULATOR_ADDRESS_TYPE;
    signal READ_ADDRESS_PIPE5_cs : ACCUMULATOR_ADDRESS_TYPE := (others => '0');
    signal READ_ADDRESS_PIPE5_ns : ACCUMULATOR_ADDRESS_TYPE;
    
    attribute use_dsp : string;
    attribute use_dsp of DSP_RESULT_PORT_ns : signal is "yes";
begin
    -- Fila do pipeline
    WRITE_PORT_PIPE0_ns <= WRITE_PORT; -- A porta 0 do pipeline_ns (Acho que é next) recebe com a primeira "entrada"
    WRITE_PORT_PIPE1_ns <= WRITE_PORT_PIPE0_cs; -- A porta 1 do pipeline_ns (Acho que é next) recebe com endereço em 0cs
    WRITE_PORT_PIPE2_ns <= WRITE_PORT_PIPE1_cs; -- A porta 2 do pipeline_ns (Acho que é next) recebe com endereço em 1cs
    DSP_ADD_PORT0_ns <= WRITE_PORT_PIPE2_cs; -- O DSP 0 recebe com o endereço em 2cs
    
    ACC_WRITE_PORT <= DSP_RESULT_PORT_cs; -- A porta de escrita se recebe o dado acumulado entre (DSP_PIPE0_cs, DSP_PIPE1_cs) com o resultado do processamento do sinal digital
    
    ACCUMULATE_PORT_PIPE0_ns <= ACC_ACCUMULATE_PORT; -- A porta 0 do Accumulate_pipeline_ns (Acho que é next) recebe com a primeira "entrada"
    ACCUMULATE_PORT_PIPE1_ns <= ACCUMULATE_PORT_PIPE0_cs; -- A porta 1 do Accumulate_pipeline_ns (Acho que é next) recebe com a proxima "Entrada"
    
    ACCUMULATE_PIPE_ns(1 to 2) <= ACCUMULATE_PIPE_cs(0 to 1); -- Chave que verifica se um endereço podera ou nao ser somado
    ACCUMULATE_PIPE_ns(0) <= ACCUMULATE; -- A porta 0 da chave Accumulate_pipeline_ns (Acho que é next) recebe o valor em accumulate (TRUE OU FALSE)

    ACC_ACCU_ADDRESS <= WRITE_ADDRESS; -- Recebe a primeira palavra (ou porta) de 16 bits no acumulador

    -- Fila de endereços onde sera escrito 
    WRITE_ADDRESS_PIPE0_ns <= WRITE_ADDRESS; -- Recebe a primeira palavra (ou porta) de 16 bits no proximo item do pipeline a ser escrito
    WRITE_ADDRESS_PIPE1_ns <= WRITE_ADDRESS_PIPE0_cs;
    WRITE_ADDRESS_PIPE2_ns <= WRITE_ADDRESS_PIPE1_cs;
    WRITE_ADDRESS_PIPE3_ns <= WRITE_ADDRESS_PIPE2_cs;
    WRITE_ADDRESS_PIPE4_ns <= WRITE_ADDRESS_PIPE3_cs;
    WRITE_ADDRESS_PIPE5_ns <= WRITE_ADDRESS_PIPE4_cs;
    ACC_WRITE_ADDRESS <= WRITE_ADDRESS_PIPE5_cs; -- Recebe o local onde sera escrito na memoria
    
    WRITE_ENABLE_PIPE_ns(1 to 5) <= WRITE_ENABLE_PIPE_cs(0 to 4); -- Recebe se os nexts de escrita podem ser utilizados (TRUE) 
    WRITE_ENABLE_PIPE_ns(0) <= WRITE_ENABLE; -- Recebe o sinal da porta de escrita para inicio
    ACC_WRITE_EN <= WRITE_ENABLE_PIPE_cs(5); -- Caso o - WRITE_ENABLE_PIPE_cs(5) - esteja ativado é feita a atribuição no local - WRITE_ADDRESS_PIPE5_cs - de memoria

    -- Fila de endereços onde sera lido 
    READ_ADDRESS_PIPE0_ns <= READ_ADDRESS;
    READ_ADDRESS_PIPE1_ns <= READ_ADDRESS_PIPE0_cs;
    READ_ADDRESS_PIPE2_ns <= READ_ADDRESS_PIPE1_cs;
    READ_ADDRESS_PIPE3_ns <= READ_ADDRESS_PIPE2_cs;
    READ_ADDRESS_PIPE4_ns <= READ_ADDRESS_PIPE3_cs;
    READ_ADDRESS_PIPE5_ns <= READ_ADDRESS_PIPE4_cs;
    ACC_READ_ADDRESS <= READ_ADDRESS_PIPE5_cs; -- Endereço onde sera realizada a leitura
    
    READ_PORT <= ACC_READ_PORT; -- Verifica se tem permissão pra leitura (Chave ativada)
    
    -- Os dados que vem do pipeline para fazer a soma entre os dados
    DSP_PIPE0_ns <= DSP_ADD_PORT0_cs; -- DSP_PIPE0_cs
    DSP_PIPE1_ns <= DSP_ADD_PORT1_cs; -- DSP_PIPE1_cs
    
    -- Processo de soma do Processamento do Sinal Digital
    DSP_ADD:
    process(DSP_PIPE0_cs, DSP_PIPE1_cs) is
    begin
         -- DSP_RESULT_PORT resulta no ACC_WRITE_PORT que é usado no processo ACC_PORT0
        for i in 0 to MATRIX_WIDTH-1 loop
            DSP_RESULT_PORT_ns(i) <= std_logic_vector(unsigned(DSP_PIPE0_cs(i)) + unsigned(DSP_PIPE1_cs(i)));
        end loop;
    end process DSP_ADD;

    -- Processo MUX, onde as portas usadas no PROCESSO DSP_ADD são definidas
    ACC_MUX:
    process(ACCUMULATE_PORT_PIPE1_cs, ACCUMULATE_PIPE_cs(2)) is
    begin
        if ACCUMULATE_PIPE_cs(2) = '1' then
            DSP_ADD_PORT1_ns <= ACCUMULATE_PORT_PIPE1_cs;
        else
            DSP_ADD_PORT1_ns <= (others => (others => '0'));
        end if;
    end process ACC_MUX;
    
    -- Escrita de barramentos nos acumuladores
    ACC_PORT0:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if ENABLE = '1' then
                --synthesis translate_off
                if to_integer(unsigned(ACC_WRITE_ADDRESS)) < REGISTER_DEPTH then
                --synthesis translate_on
                    if ACC_WRITE_EN = '1' then
                        ACCUMULATORS(to_integer(unsigned(ACC_WRITE_ADDRESS))) := WORD_ARRAY_TO_BITS(ACC_WRITE_PORT);
                        ACCUMULATORS_COPY(to_integer(unsigned(ACC_WRITE_ADDRESS))) := WORD_ARRAY_TO_BITS(ACC_WRITE_PORT);
                    end if;
                --synthesis translate_off
                end if;
                --synthesis translate_on
            end if;
        end if;
    end process ACC_PORT0;

    -- Leitura de barramentos dos acumuladores
    ACC_PORT1:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if ENABLE = '1' then
                --synthesis translate_off
                if to_integer(unsigned(ACC_READ_ADDRESS)) < REGISTER_DEPTH then
                --synthesis translate_on
                    ACC_READ_PORT <= BITS_TO_WORD_ARRAY(ACCUMULATORS(to_integer(unsigned(ACC_READ_ADDRESS))));
                    ACC_ACCUMULATE_PORT <= BITS_TO_WORD_ARRAY(ACCUMULATORS_COPY(to_integer(unsigned(ACC_ACCU_ADDRESS))));
                --synthesis translate_off
                end if;
                --synthesis translate_on
            end if;
        end if;
    end process ACC_PORT1;
    
    -- Processo de Sequencia logica
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                DSP_ADD_PORT0_cs    <= (others => (others => '0'));
                DSP_ADD_PORT1_cs    <= (others => (others => '0'));
                DSP_RESULT_PORT_cs  <= (others => (others => '0'));
                DSP_PIPE0_cs        <= (others => (others => '0'));
                DSP_PIPE1_cs        <= (others => (others => '0'));
                
                ACCUMULATE_PORT_PIPE0_cs <= (others => (others => '0'));
                ACCUMULATE_PORT_PIPE1_cs <= (others => (others => '0'));
                
                ACCUMULATE_PIPE_cs <= (others => '0');
                
                WRITE_PORT_PIPE0_cs <= (others => (others => '0'));
                WRITE_PORT_PIPE1_cs <= (others => (others => '0'));
                WRITE_PORT_PIPE2_cs <= (others => (others => '0'));
                
                WRITE_ENABLE_PIPE_cs <= (others => '0');
                
                WRITE_ADDRESS_PIPE0_cs <= (others => '0');
                WRITE_ADDRESS_PIPE1_cs <= (others => '0');
                WRITE_ADDRESS_PIPE2_cs <= (others => '0');
                WRITE_ADDRESS_PIPE3_cs <= (others => '0');
                WRITE_ADDRESS_PIPE4_cs <= (others => '0');
                WRITE_ADDRESS_PIPE5_cs <= (others => '0');
                
                READ_ADDRESS_PIPE0_cs <= (others => '0');
                READ_ADDRESS_PIPE1_cs <= (others => '0');
                READ_ADDRESS_PIPE2_cs <= (others => '0');
                READ_ADDRESS_PIPE3_cs <= (others => '0');
                READ_ADDRESS_PIPE4_cs <= (others => '0');
                READ_ADDRESS_PIPE5_cs <= (others => '0');
            else
                if ENABLE = '1' then
                    -- Fila de soma do processo DSP_ADD
                    DSP_ADD_PORT0_cs    <= DSP_ADD_PORT0_ns;
                    DSP_ADD_PORT1_cs    <= DSP_ADD_PORT1_ns; -- Porta resultante do processo "ACC_MUX" derivada do sinal "ACCUMULATE_PORT_PIPE1_cs"
                    DSP_RESULT_PORT_cs  <= DSP_RESULT_PORT_ns; -- Resultado que será escrito no acumulador
                    -- As duas portas a serem somada no processo
                    DSP_PIPE0_cs        <= DSP_PIPE0_ns;
                    DSP_PIPE1_cs        <= DSP_PIPE1_ns;
                    
                    -- Fila de portas que poderao ser somadas ou nao
                    ACCUMULATE_PORT_PIPE0_cs <= ACCUMULATE_PORT_PIPE0_ns;
                    ACCUMULATE_PORT_PIPE1_cs <= ACCUMULATE_PORT_PIPE1_ns; -- Ultima linha, que sera uma das portas a ser somada no processo DSP_ADD: Porta == "DSP_PIPE1_cs"
                    
                    ACCUMULATE_PIPE_cs <= ACCUMULATE_PIPE_ns; -- Chave que verifica se uma palavra (ou porta) podera ser somada ou nao
                    
                    -- Fila de Portas que irão ser somadas no DSP_ADD
                    WRITE_PORT_PIPE0_cs <= WRITE_PORT_PIPE0_ns;
                    WRITE_PORT_PIPE1_cs <= WRITE_PORT_PIPE1_ns;
                    WRITE_PORT_PIPE2_cs <= WRITE_PORT_PIPE2_ns; -- Ultima linha, que sera uma das portas que somada no processo DSP_ADD: Porta == "DSP_PIPE0_cs"
                    
                    WRITE_ENABLE_PIPE_cs <= WRITE_ENABLE_PIPE_ns; -- Caso receba o 5 elemento como true a palavra (ou porta) da memoria e escrita no acumulador
                
                    -- Fila de endereços até serem escritas no acumulador (Daqui sai o endereço de onde sera escrita no acumulador)
                    WRITE_ADDRESS_PIPE0_cs <= WRITE_ADDRESS_PIPE0_ns;
                    WRITE_ADDRESS_PIPE1_cs <= WRITE_ADDRESS_PIPE1_ns;
                    WRITE_ADDRESS_PIPE2_cs <= WRITE_ADDRESS_PIPE2_ns;
                    WRITE_ADDRESS_PIPE3_cs <= WRITE_ADDRESS_PIPE3_ns;
                    WRITE_ADDRESS_PIPE4_cs <= WRITE_ADDRESS_PIPE4_ns;
                    WRITE_ADDRESS_PIPE5_cs <= WRITE_ADDRESS_PIPE5_ns; -- Ultima linha, que sera ou nao escrita no acumulador
                
                    -- Fila de endereços até serem lidas do acumulador (Daqui sai o endereço de onde sera lida a palavra (ou porta) no acumulador)
                    READ_ADDRESS_PIPE0_cs <= READ_ADDRESS_PIPE0_ns;
                    READ_ADDRESS_PIPE1_cs <= READ_ADDRESS_PIPE1_ns;
                    READ_ADDRESS_PIPE2_cs <= READ_ADDRESS_PIPE2_ns;
                    READ_ADDRESS_PIPE3_cs <= READ_ADDRESS_PIPE3_ns;
                    READ_ADDRESS_PIPE4_cs <= READ_ADDRESS_PIPE4_ns;
                    READ_ADDRESS_PIPE5_cs <= READ_ADDRESS_PIPE5_ns; -- Ultima linha, que sera ou nao lida no acumulador
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;