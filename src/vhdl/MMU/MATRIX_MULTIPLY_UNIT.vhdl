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

--! @file MATRIX_MULTIPLY_UNIT.vhdl
--! @author Jonas Fuhrmann
--! @brief This is the matrix multiply unit. It has inputs to load weights to it's MACC components and inputs for the matrix multiply operation.
--! @details The matrix multiply unit is a systolic array consisting of identical MACC components. The MACCs are layed to an 2 dimensional grid.
--! The input has to be feeded diagonally, because of the delays caused by the MACC registers. The partial sums are 'flowing down' the array and the input has to be delayed.
--!
--!  
use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity MATRIX_MULTIPLY_UNIT is
    generic(
        MATRIX_WIDTH    : natural := 8;
        MATRIX_HALF     : natural := ((8-1)/NUMBER_OF_MULT)
    );
    port(
        CLK, RESET      : in  std_logic;
        ENABLE          : in  std_logic;
        
        WEIGHT_DATA0    : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Input dos pesos, conectados com a entrada de pesos no MACC.
        WEIGHT_DATA1    : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Input dos pesos, conectados com a entrada de pesos no MACC.
        WEIGHT_SIGNED   : in  std_logic; --!< Determina se o valor do Peso da entrada é "Signed" ou "Unsigned"
        SYSTOLIC_DATA   : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); --!< Os dados de entrada na diagonal.
        SYSTOLIC_SIGNED : in  std_logic; --!< Determina se o valor dos dados Sistolicos da entrada é "Signed" ou "Unsigned"
        
        ACTIVATE_WEIGHT : in  std_logic; --!< Ativa os pesos carregados de forma sequenciais.
        LOAD_WEIGHT     : in  std_logic; --!< Realiza o pre-carregamento de uma coluna com o WEIGHT_DATA.
        WEIGHT_ADDRESS  : in  BYTE_TYPE; --!< Endereça ate o total de 256 preweights.
        
        RESULT_DATA     : out WORD_ARRAY_TYPE(0 to MATRIX_WIDTH-1) --!< Resultado da multiplicação das matrizes
    );
end entity MATRIX_MULTIPLY_UNIT;

--! @brief Architecture of the matrix multiply unit.
architecture BEH of MATRIX_MULTIPLY_UNIT is
    component MACC is
        generic(
            -- O tamanho da ultima entrada de soma
            LAST_SUM_WIDTH      : natural   := 0;
            -- O Tamanho do registrador de saida
            PARTIAL_SUM_WIDTH   : natural   := 2*EXTENDED_BYTE_WIDTH -- Valor inicial = 18
        );
        port(
            CLK, RESET      : in std_logic;
            ENABLE          : in std_logic;
           -- Weights - Atual e Pre-carregado
            WEIGHT_INPUT_FIRST    : in EXTENDED_BYTE_TYPE; --!< Entrada do primeiro registro de peso.
            WEIGHT_INPUT_LAST     : in EXTENDED_BYTE_TYPE;
            PRELOAD_WEIGHT        : in std_logic; --!< Ativação Primeiro Registro de Peso ou Pre-Carregado.
            LOAD_WEIGHT           : in std_logic; --!< Ativação Segundo Registro de Peso ou do 'carregado'.
            -- Input
            INPUT_FIRST           : in EXTENDED_BYTE_TYPE; --!< Entrada para a operação de multiplicação-soma.
            INPUT_LAST            : in EXTENDED_BYTE_TYPE;
            LAST_SUM              : in std_logic_vector(LAST_SUM_WIDTH-1 downto 0); --!< Entrada para a acumulação dos valores.
            -- Output
            PARTIAL_SUM           : out std_logic_vector(PARTIAL_SUM_WIDTH-1 downto 0) --!< Saida do registro do valor parcial da soma.
        );
    end component MACC;
    for all : MACC use entity WORK.MACC(BEH);

    -- Sinal que armazena o resultado provisorio em uma matriz, que em cada SxY posição, possui um Word_type(vetor de std_logic), sao inicializados com "0"
    signal INTERIM_RESULT   : WORD_ARRAY_2D_TYPE(0 to MATRIX_HALF, 0 to MATRIX_WIDTH-1) := (others => (others => (others => '0')));
    signal WEIGHT_ADDRESS_cs : BYTE_TYPE := (others => '0');
    
    signal LOAD_WEIGHT_FLAG         : std_logic := '0';
    signal SIGN_EXTEND_WEIGHT_FLAG  : std_logic := '1';

    -- Sinais para conversão dos endereços
    signal LOAD_WEIGHT_MAP  : std_logic_vector(0 to MATRIX_HALF);
    signal LOAD_WEIGHT_cs   : std_logic := '0';

    signal ACTIVATE_CONTROL_cs  : std_logic_vector(0 to MATRIX_HALF-1) := (others => '0');
    signal ACTIVATE_CONTROL_ns  : std_logic_vector(0 to MATRIX_HALF-1);
    
    signal ACTIVATE_MAP         : std_logic_vector(0 to MATRIX_HALF);
    signal ACTIVATE_WEIGHT_cs   : std_logic := '0';

    -- Sinais para extensão dos sinais
    signal EXTENDED_WEIGHT_DATA0     : EXTENDED_BYTE_ARRAY(0 to MATRIX_WIDTH-1);
    signal EXTENDED_WEIGHT_DATA1      : EXTENDED_BYTE_ARRAY(0 to MATRIX_WIDTH-1);

    signal EXTENDED_SYSTOLIC_DATA   : EXTENDED_BYTE_ARRAY(0 to MATRIX_WIDTH-1) := (others => (others => '0'));
    
    -- Sinais para extensão dos sinais da resposta
    signal SIGN_CONTROL_cs  : std_logic_vector(0 to 2+MATRIX_HALF) := (others => '0'); -- Possui um delay de 2 registros causados pelo MACC
    signal SIGN_CONTROL_ns  : std_logic_vector(0 to 2+MATRIX_HALF);
begin
    
    -- Linear shift register: Controla a ativação com os pesos, é uma fila FIFO.
        -->> ie: 
        --> ACTIVATE_WEIGHT := 1 (Carrega bit Weight)
        --> ACTIVATE_CONTROL_cs (0 to 3) := "0000" (carrega bit Processo)
        --> ACTIVATE_CONTROL_ns(1 to 3)  <= "0" (Realiza a atribuição abaixo)
        --> ACTIVATE_CONTROL_ns(0)       <= ACTIVATE_WEIGHT
        -->> In Process:
        --> ACTIVATE_CONTROL_cs <= ACTIVATE_CONTROL_ns;(ACTIVATE_CONTROL_cs <= "1000")
        -->> Realizando o mesmo processo acima sem carregar bit Processo, porque ACTIVATE_CONTROL_cs ja possui  "1000":
        --> ACTIVATE_CONTROL_ns(1 to 3) <= "0"
        --> ACTIVATE_CONTROL_ns(0)       <= ACTIVATE_WEIGHT
        -->> In Process:
        --> ACTIVATE_CONTROL_cs <= ACTIVATE_CONTROL_ns;(ACTIVATE_CONTROL_cs <= "0100")
    ACTIVATE_CONTROL_ns(1 to MATRIX_HALF-1) <= ACTIVATE_CONTROL_cs(0 to MATRIX_HALF-1-1);
    ACTIVATE_CONTROL_ns(0) <= ACTIVATE_WEIGHT;

    -- Linear shift register: Controla a variação de sinal, mas mesmo que seja '1' pode ser que o dado relativo a posicao no SIGN_CONTROL nao seja negativo
    SIGN_CONTROL_ns(1 to 2+MATRIX_HALF) <= SIGN_CONTROL_cs(0 to 2+MATRIX_HALF-1);
    SIGN_CONTROL_ns(0) <= SYSTOLIC_SIGNED;
    
    -- Concatena o valor de ativacao novo do Weight com o Antigo, descartando o ultimo valor.
    ACTIVATE_MAP <= ACTIVATE_CONTROL_ns(0) & ACTIVATE_CONTROL_cs;
    
    LOAD:   -- Conversão de endereços
    process(LOAD_WEIGHT, WEIGHT_ADDRESS) is
    -- LOAD_WEIGHT <-> ACTIVATE_MAP(Position), WEIGHT_ADDRESS <-> INPUT 
        variable LOAD_WEIGHT_v       : std_logic;
        variable WEIGHT_ADDRESS_v    : BYTE_TYPE;
        
        variable LOAD_WEIGHT_MAP_v   : std_logic_vector(0 to MATRIX_HALF);
    begin
        LOAD_WEIGHT_MAP_v := (others => '0'); -- Inicializa a variavel com '0'
        LOAD_WEIGHT_v       := LOAD_WEIGHT; 
        WEIGHT_ADDRESS_v    := WEIGHT_ADDRESS;
            
        if LOAD_WEIGHT_v = '1' then -- Carrega para o sinal '1' para o Pre-Peso (permitindo, caso lido, carregar o proximo peso do endereço WEIGHT_ADDRESS)
            LOAD_WEIGHT_MAP_v(to_integer(unsigned(WEIGHT_ADDRESS_v))) := '1'; 
        end if;
        LOAD_WEIGHT_MAP <= LOAD_WEIGHT_MAP_v; -- Atualiza o Sinal
    end process LOAD;
    
    -- Função que realiza uma concatenação do Dado com o Sinal
    SIGN_EXTEND_WEIGHT:
    process(WEIGHT_DATA0, WEIGHT_DATA1, WEIGHT_SIGNED) is
    -- WEIGHT_DATA <-> INPUT, WEIGHT_SIGNED <-> INPUT
        begin
        for i in 0 to MATRIX_WIDTH-1 loop
                -- <WEIGHT_INPUT>
            if WEIGHT_SIGNED = '1' then
                EXTENDED_WEIGHT_DATA0(i) <= WEIGHT_DATA0(i)(BYTE_WIDTH-1) & WEIGHT_DATA0(i);
                EXTENDED_WEIGHT_DATA1(i) <= WEIGHT_DATA1(i)(BYTE_WIDTH-1) & WEIGHT_DATA1(i);
            else
                EXTENDED_WEIGHT_DATA0(i) <= '0' & WEIGHT_DATA0(i);
                EXTENDED_WEIGHT_DATA1(i) <= '0' & WEIGHT_DATA1(i);
            end if;
        end loop;
    end process SIGN_EXTEND_WEIGHT;

    SIGN_EXTEND_SYSTOLIC:
    process(SYSTOLIC_DATA, SIGN_CONTROL_ns) is
    --SYSTOLIC_DATA <-> INPUT, SIGN_CONTROL_ns(0) <-> SYSTOLIC_SIGNED, SIGN_CONTROL_ns(1 to n-1) <-> SIGN_CONTROL_cs(0 to n-2)
        begin
        for i in 0 to MATRIX_WIDTH-1 loop
            if SIGN_CONTROL_ns(i/NUMBER_OF_MULT) = '1' then 
                EXTENDED_SYSTOLIC_DATA(i) <= SYSTOLIC_DATA(i)(BYTE_WIDTH-1) & SYSTOLIC_DATA(i);
            else
                EXTENDED_SYSTOLIC_DATA(i) <= '0' & SYSTOLIC_DATA(i);
            end if;
        end loop;
    end process SIGN_EXTEND_SYSTOLIC;
   
    MACC_GEN:
    for i in 0 to MATRIX_HALF generate
        MACC_2D:
        for j in 0 to MATRIX_WIDTH-1 generate
            UPPER_LEFT_ELEMENT: -- Verifica o elemento na posicao 0x0, PRIMEIRO PROCESSO QUE OCORRE
            if i = 0 and j = 0 generate
                MACC_i0 : MACC
                generic map(
                    LAST_SUM_WIDTH      => 0,
                    PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) + 1
                )
                port map(
                    CLK                 => CLK,
                    RESET               => RESET,
                    ENABLE              => ENABLE,
                    WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                    WEIGHT_INPUT_LAST   => EXTENDED_WEIGHT_DATA1(j), -- ENTRADA DE UMA COLUNA DO PESO
                    PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                    LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                    INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                    INPUT_LAST          => EXTENDED_SYSTOLIC_DATA((NUMBER_OF_MULT * i)+1), -- ENTRADA DE DADOS
                    LAST_SUM            => (others => '0'), -- O ULTIMO VALOR DA SOMA ERA 0.
                    PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i)+1-1 downto 0) -- Guarda os novos valores, variando a posicao do i
                );
            end generate UPPER_LEFT_ELEMENT;

            FIRST_COLUMN: -- Verifica o elemento na posicao 0x0, PRIMEIRO PROCESSO QUE OCORRE
            if i = 0 and j > 0 generate
                MACC_i0 : MACC
                generic map(
                    LAST_SUM_WIDTH      => 0,
                    PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) + 1
                )
                port map(
                    CLK                 => CLK,
                    RESET               => RESET,
                    ENABLE              => ENABLE,
                    WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                    WEIGHT_INPUT_LAST   => EXTENDED_WEIGHT_DATA1(j), -- ENTRADA DE UMA COLUNA DO PESO
                    PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                    LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                    INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                    INPUT_LAST          => EXTENDED_SYSTOLIC_DATA((NUMBER_OF_MULT * i)+1), -- ENTRADA DE DADOS
                    LAST_SUM            => (others => '0'), -- O ULTIMO VALOR DA SOMA ERA 0.
                    PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i)+1-1 downto 0) -- Guarda os novos valores, variando a posicao do i
                );
            end generate FIRST_COLUMN;

            -- Completa o lado esquerdo do INTERIM_RESULT
            LEFT_FULL_ELEMENTS:
            if i > 0 and (NUMBER_OF_MULT * i)+1 <= 2*BYTE_WIDTH-1 and j = 0 and (NUMBER_OF_MULT * i)+1 <= (MATRIX_WIDTH-1) generate
                MACC_i2 : MACC
                generic map(                                                                        --  1,  2,  3,  4,  5
                    LAST_SUM_WIDTH      => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - i,        -- 19, 20, 21, 22, 23
                    PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)     -- 20, 21, 22, 23, 24...
                )
                port map(
                    CLK                 => CLK,
                    RESET               => RESET,
                    ENABLE              => ENABLE,
                    WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                    WEIGHT_INPUT_LAST   => EXTENDED_WEIGHT_DATA1(j), -- ENTRADA DE UMA COLUNA DO PESO
                    PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                    LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                    INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                    INPUT_LAST          => EXTENDED_SYSTOLIC_DATA((NUMBER_OF_MULT * i)+1), -- ENTRADA DE DADOS
                    LAST_SUM            => INTERIM_RESULT(i-1, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i+1) downto 0), -- É usado o valor anterior do atual
                    PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1) - 1 downto 0) -- Guarda os novos valores, variando a posicao do i
                );
            end generate LEFT_FULL_ELEMENTS;

             -- Preenche toda as colunas
            FULL_COLUMNS:
            if i > 0 and (NUMBER_OF_MULT * i)+1 <= 2*BYTE_WIDTH-1 and j > 0  and (NUMBER_OF_MULT * i)+1 <= (MATRIX_WIDTH-1) generate
                MACC_i3 : MACC
                generic map(
                    LAST_SUM_WIDTH      => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - i, 
                    PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1) 
                )
                port map(
                    CLK                 => CLK,
                    RESET               => RESET,
                    ENABLE              => ENABLE,
                    WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                    WEIGHT_INPUT_LAST   => EXTENDED_WEIGHT_DATA1(j), -- ENTRADA DE UMA COLUNA DO PESO
                    PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                    LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                    INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                    INPUT_LAST          => EXTENDED_SYSTOLIC_DATA((NUMBER_OF_MULT * i)+1), -- ENTRADA DE DADOS
                    LAST_SUM            => INTERIM_RESULT(i-1, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i+1) downto 0), -- É usado o valor anterior do atual
                    PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)-1 downto 0) -- Guarda os novos valores, variando a posicao do i e do j
                );
            end generate FULL_COLUMNS;

             -- Completa o lado esquerdo do INTERIM_RESULT
             LEFT_FULL_LAST_ELEMENTS_ODD:
             if i > 0 and (NUMBER_OF_MULT * i)+1 <= 2*BYTE_WIDTH-1 and j = 0 and (NUMBER_OF_MULT * i)+1 > (MATRIX_WIDTH-1) generate
                 MACC_i2 : MACC
                 generic map(                                           
                 LAST_SUM_WIDTH      => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - i, 
                 PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)
                 )
                 port map(
                     CLK                 => CLK,
                     RESET               => RESET,
                     ENABLE              => ENABLE,
                     WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                     WEIGHT_INPUT_LAST   => (others => '0'), -- ENTRADA DE UMA COLUNA DO PESO
                     PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                     LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                     INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                     INPUT_LAST          => (others => '0'), -- ENTRADA DE DADOS
                     LAST_SUM            => INTERIM_RESULT(i-1, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i+1) downto 0), -- É usado o valor anterior do atual
                     PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)-1 downto 0) -- Guarda os novos valores, variando a posicao do i
                 );
             end generate LEFT_FULL_LAST_ELEMENTS_ODD;
 
              -- Preenche toda as colunas
             FULL_COLUMNS_LAST_ELEMENT_ODD:
             if i > 0 and (NUMBER_OF_MULT * i)+1 <= 2*BYTE_WIDTH-1 and j > 0  and (NUMBER_OF_MULT * i)+1 > (MATRIX_WIDTH-1) generate
                 MACC_i3 : MACC
                 generic map(
                    LAST_SUM_WIDTH      => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - i, 
                    PARTIAL_SUM_WIDTH   => 2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)
                 )
                 port map(
                     CLK                 => CLK,
                     RESET               => RESET,
                     ENABLE              => ENABLE,
                     WEIGHT_INPUT_FIRST  => EXTENDED_WEIGHT_DATA0(j), -- ENTRADA DE UMA COLUNA DO PESO
                     WEIGHT_INPUT_LAST   => (others => '0'), -- ENTRADA DE UMA COLUNA DO PESO
                     PRELOAD_WEIGHT      => LOAD_WEIGHT_MAP(i), -- Carrega o sinal do pre-peso nesta posicao (ATIVO OU NAO)
                     LOAD_WEIGHT         => ACTIVATE_MAP(i), -- Carrega o sinal do peso nesta posicao (ATIVO OU NAO)
                     INPUT_FIRST         => EXTENDED_SYSTOLIC_DATA(NUMBER_OF_MULT * i), -- ENTRADA DE DADOS
                     INPUT_LAST          => (others => '0'), -- ENTRADA DE DADOS
                     LAST_SUM            => INTERIM_RESULT(i-1, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i+1) downto 0), -- É usado o valor anterior do atual
                     PARTIAL_SUM         => INTERIM_RESULT(i, j)(2*EXTENDED_BYTE_WIDTH + (NUMBER_OF_MULT * i) - (i-1)-1 downto 0) -- Guarda os novos valores, variando a posicao do i e do j
                 );
             end generate FULL_COLUMNS_LAST_ELEMENT_ODD;
        end generate MACC_2D;
    end generate MACC_GEN;
    
    RESULT_ASSIGNMENT:
    process(INTERIM_RESULT, SIGN_CONTROL_cs(2+MATRIX_HALF-1)) is
        -- INTERIM_RESULT <-> PARTIAL_SUM (FINAL), SIGN_CONTROL_cs(ULTIMA POSICAO) 
        variable RESULT_DATA_v  : std_logic_vector(2*EXTENDED_BYTE_WIDTH+(MATRIX_WIDTH-1)-(MATRIX_HALF-1)-1 downto 0);
        variable EXTEND_v       : std_logic_vector(4*BYTE_WIDTH-1 downto 2*EXTENDED_BYTE_WIDTH+(MATRIX_WIDTH-1)-(MATRIX_HALF-1)); -- 32bits Downto 32bits (tem 1 posicao)
    begin
        for i in MATRIX_WIDTH-1 downto 0 loop
            RESULT_DATA_v := INTERIM_RESULT(MATRIX_HALF, i)(2*EXTENDED_BYTE_WIDTH+(MATRIX_WIDTH-1)-(MATRIX_HALF-1)-1 downto 0); -- RESULT_DATA_v armazena todos os valores da ultima linha da coluna i, exceto o ultimo bit armazenado
            if SIGN_CONTROL_cs(2+MATRIX_HALF-1) = '1' then
                EXTEND_v := (others => INTERIM_RESULT(MATRIX_HALF, i)(2*EXTENDED_BYTE_WIDTH+(MATRIX_WIDTH-1)-(MATRIX_HALF-1)-1)); -- Guarda o valor do ultimo dado (SINAL)
            else
                EXTEND_v := (others => '0'); -- SINAL POSITIVO
            end if;
            
            RESULT_DATA(i) <= EXTEND_v & RESULT_DATA_v; -- Concatena o resultado com o sinal
        end loop;
    end process RESULT_ASSIGNMENT;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                ACTIVATE_CONTROL_cs     <= (others => '0');
                SIGN_CONTROL_cs         <= (others => '0');
                LOAD_WEIGHT_FLAG        <= '0';
                SIGN_EXTEND_WEIGHT_FLAG <= '1';
            else
                ACTIVATE_CONTROL_cs <= ACTIVATE_CONTROL_ns;
                SIGN_CONTROL_cs     <= SIGN_CONTROL_ns;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;