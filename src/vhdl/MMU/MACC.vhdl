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

--! @file MACC.vhdl
--! @author Jonas Fuhrmann
--! @brief Component which does a multiply-add operation with double buffered weights.
--! @details This component has two weight registers, which are configured as gated clock registers with seperate enable flags.
--! The second register is used for multiplication with the input register. The product is added to the LAST_SUM input, which defines the PARTIAL_SUM output register.
--!
--! Componente responsavel pelas operações de Multiplicação e Soma com o Pesos duplicados.
--! Este componente possui dois registradores de pesos, que sao configurados como "Gated clock Registers" com Flags de ativação separadas.
--! O segundo registrador é usado na multiplicação com o Registrador de Entrada. O produto é somado com a entrada LAST_SUM, que define a saida do registrador PARTIAL_SUM.


use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity MACC is
    generic(
        -- O tamanho da ultima entrada de soma
        LAST_SUM_WIDTH      : natural   := 0;
        -- O Tamanho do registrador de saida
        PARTIAL_SUM_WIDTH   : natural   := 2*EXTENDED_BYTE_WIDTH -- Valor inicial = 18
    );
    port(
        CLK, RESET            : in std_logic;
        ENABLE                : in std_logic;
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
end entity MACC;

--! @brief Architecture of the MACC component.
architecture BEH of MACC is

    -- Alternating weight registers
        -- Registros (Vetores) que contem o PreWeight e o Weight atual (cs) e o proximo (ns).
    signal PREWEIGHT_cs     : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1) := (others => (others => '0')); 
    signal PREWEIGHT_ns     : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1);
    
    signal WEIGHT_cs        : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1) := (others => (others => '0'));
    signal WEIGHT_ns        : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1);
    
    -- Input register
    signal INPUT_cs         : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1) := (others => (others => '0'));
    signal INPUT_ns         : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1);
    
    -- Pipeline register
        -- Sua entrada recebe os resultados da multiplicação
    signal PIPELINE_cs      : MUL_HALFWORD_ARRAY_TYPE(0 to NUMBER_OF_MULT-1) := (others=> (others => '0'));
    signal PIPELINE_ns      : MUL_HALFWORD_ARRAY_TYPE(0 to NUMBER_OF_MULT-1);
    
    -- Result register
        -- Registros (Vetores) que contem os valores da soma atual (cs) e proximo(ns)
    signal PARTIAL_SUM_cs       : std_logic_vector(PARTIAL_SUM_WIDTH-1 downto 0) := (others => '0');
    signal PARTIAL_SUM_ns       : std_logic_vector(PARTIAL_SUM_WIDTH-1 downto 0);

    attribute use_dsp : string;
    attribute use_dsp of PARTIAL_SUM_ns : signal is "yes";

begin
    -- Na entrada o dado, o Peso e o Atual valor do Pre-Weight é atribuido ao pipeline do Input (INPUT_ns), do PreWeight_ns e do Weight_ns
    -- Apenas uma linha da matriz do peso é carregada por vez
    -- O PreWeight recebe a proxima linha a ser usada na multiplicação
    INPUT_ns(0)        <= INPUT_FIRST;
    INPUT_ns(1)        <= INPUT_LAST;

    PREWEIGHT_ns(0)    <= WEIGHT_INPUT_FIRST;
    PREWEIGHT_ns(1)    <= WEIGHT_INPUT_LAST;

    WEIGHT_ns(0 to NUMBER_OF_MULT-1)       <= PREWEIGHT_cs(0 to NUMBER_OF_MULT-1);

    MUL:
    process(INPUT_cs, WEIGHT_cs) is
        variable INPUT_v            : EXTENDED_BYTE_TYPE;
        variable WEIGHT_v           : EXTENDED_BYTE_TYPE;
        variable PIPELINE_ns_v      : MUL_HALFWORD_ARRAY_TYPE(0 to NUMBER_OF_MULT-1);
        variable FLAG_v             : std_logic;
    begin
        PIPELINE_ns_v := (others => (others => '0'));
        FLAG_v := '0';

        for i in 0 to NUMBER_OF_MULT-1 loop
                -- (INPUT > INPUT_ns > INPUT_cs > INPUT_v)
            INPUT_v         := INPUT_cs(i); -- Recebe o valor carregado do input 
                -- (WEIGHT_INPUT > PREWEIGHT_ns [IF PRELOAD_WEIGHT = 1] > PREWEIGHT_cs > WEIGHT_ns [IF LOAD_WEIGHT = 1] > WEIGHT_cs > WEIGHT_v) - Permite a realizaÃ§Ã£o de calculos com o mesmo peso varias vezes.
            WEIGHT_v        := WEIGHT_cs(i); -- Recebe o valor carregado do peso
                -- Converte para signed para realizar as operaÃ§Ãµes, depois converte novamente para vector logic.
            PIPELINE_ns_v(i) := std_logic_vector(signed(INPUT_v) * signed(WEIGHT_v));
        end loop;

        PIPELINE_ns(0 to NUMBER_OF_MULT-1)     <= PIPELINE_ns_v(0 to NUMBER_OF_MULT-1); -- Recebe o valor da multiplicaÃ§ao
    end process MUL;
    
        -- O Processo de multiplicaÃ§Ã£o e soma
    ADD:
    process(PIPELINE_cs, LAST_SUM) is
        variable PIPELINE_cs_v      : MUL_HALFWORD_ARRAY_TYPE(0 to NUMBER_OF_MULT-1);
        variable LAST_SUM_v         : std_logic_vector(LAST_SUM_WIDTH-1 downto 0);
        variable PARTIAL_SUM_v      : std_logic_vector(PARTIAL_SUM_WIDTH-1 downto 0);
    begin

        -- (NO INPUT > PIPELINE_ns_v > PIPELINE_ns > PIPELINE_cs > PIPELINE_cs_v)
        PIPELINE_cs_v(0 to NUMBER_OF_MULT-1)   := PIPELINE_cs(0 to NUMBER_OF_MULT-1);
        LAST_SUM_v      := LAST_SUM;

        -- Somente um caso irÃ¡ acontecer, e a soma que ocorre Ã© a da multiplicaÃ§Ã£o anterior a que ocorreu nesse processo atual
            -- (1) Caso LAST_SUM_WIDTH > 0, houve uma entrada anterior e  seu tamanho Ã© menor do que o tamanho da soma parcial, tendo que fazer uma concatenaÃ§Ã£o
            -- (2) Caso LAST_SUM_WIDTH > 0, houve uma entrada anterior e o seu tamanho Ã© igual ao tamanho da soma parcial, entÃ£o nÃ£o Ã© necessario a concatenaÃ§Ã£o
            -- (3) Caso o LAST_SUM_WIDTH = 0, nÃ£o houve nenhuma entrada, entÃ£o a soma parcial recebe somente os valores da multiplicaÃ§Ã£o
        if LAST_SUM_WIDTH > 0 and LAST_SUM_WIDTH < PARTIAL_SUM_WIDTH then -- (1)
            PARTIAL_SUM_v := std_logic_vector(signed(PIPELINE_cs_v(0)(PIPELINE_cs_v(0)'HIGH) & PIPELINE_cs_v(0)) + signed(PIPELINE_cs_v(1)(PIPELINE_cs_v(1)'HIGH) & PIPELINE_cs_v(1)) + signed(LAST_SUM_v(LAST_SUM_v'HIGH) & LAST_SUM_v));
        elsif LAST_SUM_WIDTH > 0 and LAST_SUM_WIDTH = PARTIAL_SUM_WIDTH then --(2)
            PARTIAL_SUM_v := std_logic_vector(signed(PIPELINE_cs_v(0)) + signed(PIPELINE_cs_v(1)) + signed(LAST_SUM_v));
        else -- (3)
            PARTIAL_SUM_v := std_logic_vector(signed(PIPELINE_cs_v(0)(PIPELINE_cs_v(0)'HIGH) & PIPELINE_cs_v(0)) + signed(PIPELINE_cs_v(1)(PIPELINE_cs_v(1)'HIGH) & PIPELINE_cs_v(1))); -- PRIMEIRA OPERACAO QUE ACONTECE
        end if;

        PARTIAL_SUM_ns  <= PARTIAL_SUM_v; -- Recebe o valor atual da soma
    end process ADD;
    
    PARTIAL_SUM <= PARTIAL_SUM_cs; -- Carrega o valor da soma na saida

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                PREWEIGHT_cs    <= (others => (others => '0'));
                WEIGHT_cs       <= (others => (others => '0'));
                INPUT_cs        <= (others => (others => '0'));
                PIPELINE_cs     <= (others => (others => '0'));
                PARTIAL_SUM_cs  <= (others => '0');
            else
                if PRELOAD_WEIGHT = '1' then
                    PREWEIGHT_cs(0 to NUMBER_OF_MULT-1)    <= PREWEIGHT_ns(0 to NUMBER_OF_MULT-1); -- Pre carregamento de um novo peso (P_new)
                end if;
                
                if LOAD_WEIGHT = '1' then
                    WEIGHT_cs(0 to NUMBER_OF_MULT-1)       <= WEIGHT_ns(0 to NUMBER_OF_MULT-1); -- Carregamento do novo peso (P_new)
                end if;
                
                if ENABLE = '1' then
                    INPUT_cs(0 to NUMBER_OF_MULT-1)     <= INPUT_ns(0 to NUMBER_OF_MULT-1); -- Responsavel por armazenar o input
                    PIPELINE_cs(0 to NUMBER_OF_MULT-1)  <= PIPELINE_ns(0 to NUMBER_OF_MULT-1); -- Responsavel por armazenar o valor intacto da multiplicação
                    PARTIAL_SUM_cs                      <= PARTIAL_SUM_ns; --Responsavel por armazenar o valor da soma
                end if;
            end if;
        end if;
    end process SEQ_LOG;
end architecture BEH;