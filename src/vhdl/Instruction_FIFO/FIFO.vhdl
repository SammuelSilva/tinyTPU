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

--! @file FIFO.vhdl
--! @author Jonas Fuhrmann
--! Este componente inclui umas FIFO simples
--! Esta FIFO usa LUTRAM - Ram Distribuida

use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;

entity FIFO is
    generic(
        FIFO_WIDTH  : natural := 8;
        FIFO_DEPTH  : natural := 32
    );
    port(
        CLK, RESET  : in  std_logic;
        INPUT       : in  std_logic_vector(FIFO_WIDTH-1 downto 0); --!< Porta de Escrita da FIFO, insere um valor novo na FIFO.
        WRITE_EN    : in  std_logic; --!< Ativador de escrita para a FIFO.
        
        OUTPUT      : out std_logic_vector(FIFO_WIDTH-1 downto 0); --!< Porta de Leitura da FIFO, que recebe o valor que sai da FIFO.
        NEXT_EN     : in  std_logic; --!< Ativador de Leitura ou "Proximo" da FIFO (Apaga os valores atuais).
        
        EMPTY       : out std_logic; --!< Determina se a FIFO esta vazia.
        FULL        : out std_logic --!< Determina se a FIFO esta cheia.
    );
end entity FIFO;

architecture FF_FIFO of FIFO is
    -- Conjunto de 32 bytes
    type FIFO_TYPE is array(0 to FIFO_DEPTH-1) of std_logic_vector(FIFO_WIDTH-1 downto 0);

    signal FIFO_DATA    : FIFO_TYPE := (others => (others => '0'));
    signal SIZE         : natural range 0 to FIFO_DEPTH := 0;
begin

    -- A Saida recebe o dado da primeira posição
    OUTPUT <= FIFO_DATA(0);
    
    -- Processo de uma FIFO, os dados entram na ultima posição e caminham ate a primeira onde são alimentados ao sistema.
    -- Size fica variando de acordo com a quantidade de dados na FIFO
    FIFO_PROC:
    process(CLK, INPUT, WRITE_EN, NEXT_EN, FIFO_DATA, SIZE) is
        variable INPUT_v        : std_logic_vector(FIFO_WIDTH-1 downto 0);
        variable WRITE_EN_v     : std_logic;
        variable NEXT_EN_v      : std_logic;
    
        variable FIFO_DATA_v    : FIFO_TYPE;
        variable SIZE_v         : natural range 0 to FIFO_DEPTH;
        
        -- output
        variable EMPTY_v        : std_logic := '1';
        variable FULL_v         : std_logic := '0';
    begin
        -- Atribuição das variaveis
        INPUT_v     := INPUT;
        WRITE_EN_v  := WRITE_EN;
        NEXT_EN_v   := NEXT_EN;
        
        FIFO_DATA_v := FIFO_DATA;
        SIZE_v      := SIZE;
        
        if CLK'event and CLK = '1' then
            if RESET = '1' then -- Reset ativado zera todas as informações e esvazia a FIFO
                SIZE_v      := 0;
                FIFO_DATA_v := (others => (others => '0')); -- É Realmente nescessario zerar a FIFO? 
                EMPTY_v     := '1';
                FULL_v      := '0';
            else
                if NEXT_EN_v = '1' then -- Caso o ativador de leitura esteja ativado
                    for i in 1 to FIFO_DEPTH-1 loop -- Os dados caminham pela FIFO
                        FIFO_DATA_v(i-1) := FIFO_DATA_v(i);
                    end loop;
                    
                    SIZE_v := SIZE_v - 1; -- E o tamanho dela diminui
                    FULL_v := '0'; -- Nao esta cheia
                end if;
                
                if WRITE_EN_v = '1' then -- Caso o ativador de escrita esteja ativado
                    FIFO_DATA_v(SIZE_v) := INPUT_v; -- Um novo dado é inserido na ultima posição vaga
                    SIZE_v := SIZE_v + 1; -- O Tamanho é incrementado
                    EMPTY_v := '0'; -- A fifo nao esta vazia
                end if;
                
                -- Caso o SIZE_v seja do do tamanho da "profundadidade" da FIFO, entao ela esta cheia
                -- Caso o SIZE_v seja 0 então a FIFO se encontra vazia
                -- Default: cada sinal é atribuido de acordo com a propria variavel
                case SIZE_v is
                    when FIFO_DEPTH =>
                        EMPTY_v := '0';
                        FULL_v  := '1';
                    when 0 =>
                        EMPTY_v := '1';
                        FULL_v  := '0';
                    when others =>
                        EMPTY_v := EMPTY_v;
                        FULL_v  := FULL_v;
                end case;
                       
            end if;
        end if;
        
        FIFO_DATA   <= FIFO_DATA_v;
        SIZE        <= SIZE_v;
        EMPTY       <= EMPTY_v;
        FULL        <= FULL_v;
    end process FIFO_PROC;
end architecture FF_FIFO;

-- Arquitetura do Bloco de LUTRAM para a FIFO
architecture DIST_RAM_FIFO of FIFO is
    component DIST_RAM is
        generic(
            DATA_WIDTH      : natural := 8; --!< A Largura de uma palavra de dados.
            DATA_DEPTH      : natural := 32; --!< A "altura" da memoria.
            ADDRESS_WIDTH   : natural := 5 --!< A Largura dos endereços.
        );
        port(
            CLK     : in  std_logic;
            IN_ADDR : in  std_logic_vector(ADDRESS_WIDTH-1 downto 0); --!< Input do endereço para a memoria.
            INPUT   : in  std_logic_vector(DATA_WIDTH-1 downto 0); --!< Porta de escrita da memoria.
            WRITE_EN: in  std_logic; --!< Ativador de escrita da memoria.
            OUT_ADDR: in  std_logic_vector(ADDRESS_WIDTH-1 downto 0); --!< Output do endereço da memoria.
            OUTPUT  : out std_logic_vector(DATA_WIDTH-1 downto 0) --!< Porta de leitura da memória.
        );
    end component DIST_RAM;
    for all : DIST_RAM use entity WORK.DIST_RAM(BEH);
    
    -- Calcula a largura mínima do endereço
    constant ADDRESS_WIDTH  : natural := natural(ceil(log2(real(FIFO_DEPTH)))); -- Neste caso o valor é 5

    constant ADD_ONE         : unsigned(1 downto 0) := (1 downto 1 => '0')&'1';
    -- Ponteiros de escrita
    signal WRITE_PTR_cs     : std_logic_vector(ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal WRITE_PTR_ns     : std_logic_vector(ADDRESS_WIDTH-1 downto 0);
    -- Ponteiros de Leitura
    signal READ_PTR_cs      : std_logic_vector(ADDRESS_WIDTH-1 downto 0) := (others => '0');
    signal READ_PTR_ns      : std_logic_vector(ADDRESS_WIDTH-1 downto 0);

    signal LOOPED_cs        : std_logic := '0';
    signal LOOPED_ns        : std_logic;

    -- Flags de verificação do status FIFO
    signal EMPTY_cs         : std_logic := '1';
    signal EMPTY_ns         : std_logic;
    signal FULL_cs          : std_logic := '0';
    signal FULL_ns          : std_logic;
begin
    RAM_i : DIST_RAM
    generic map(
        DATA_WIDTH      => FIFO_WIDTH,
        DATA_DEPTH      => FIFO_DEPTH,
        ADDRESS_WIDTH   => ADDRESS_WIDTH
    )
    port map(
        CLK         => CLK,
        IN_ADDR     => WRITE_PTR_cs,
        INPUT       => INPUT,
        WRITE_EN    => WRITE_EN,
        OUT_ADDR    => READ_PTR_cs,
        OUTPUT      => OUTPUT
    );
    
    -- Atualização do Status da FIFO
    EMPTY <= EMPTY_cs;
    FULL  <= FULL_cs;

    --> Durante o preenchimento da memoria o ponteiro de escrita estará sempre a frente do de leitura. Após a memoria ter sido preenchida "Tanto faz"
    --> A variavel NEXT_EN define se há uma leitura a ser realizada, o que pode ocorrer se houver um loop ativo ou os ponteiros estiverem em posições diferentes.
    --> A variavel WRITE_EN define se há um dado a ser escrito na memoria, o que pode ocorrer se o loop estiver desativado ou os ponteiros estiverem em posições diferente
    --> Caso os ponteiros estejam em posições iguais ou a memoria esta cheia (Ou seja, chegou na ultima posição da memoria) ou estão na posição inicial
        --> Se estiverem na posição inicial: o Loop estará zerado, permitindo a escrita de dados.
        --> Se estiverem na posição final: O Loop será ativado, permitindo que o ponteiro de leitura vá para a primeira posição e o loop é zerado de novo
    FIFO_PROC:
    process(WRITE_PTR_cs, READ_PTR_cs, LOOPED_cs, EMPTY_cs, FULL_cs, WRITE_EN, NEXT_EN) is
        variable WRITE_PTR_v    : std_logic_vector(ADDRESS_WIDTH-1 downto 0);
        variable READ_PTR_v     : std_logic_vector(ADDRESS_WIDTH-1 downto 0);
        variable LOOPED_v       : std_logic;
        variable EMPTY_v        : std_logic;
        variable FULL_v         : std_logic;
        variable WRITE_EN_v     : std_logic;
        variable NEXT_EN_v      : std_logic;
    begin
        WRITE_PTR_v := WRITE_PTR_cs;
        READ_PTR_v  := READ_PTR_cs;
        LOOPED_v    := LOOPED_cs;
        EMPTY_v     := EMPTY_cs;
        FULL_v      := FULL_cs;
        WRITE_EN_v  := WRITE_EN;
        NEXT_EN_v   := NEXT_EN;
        
        -- Se a Leitura ou "proximo" esta ativado e o ponteiro de escrita é diferente do ponteiro de leitura ou o LOOP esta ativo
        if NEXT_EN_v = '1' and (WRITE_PTR_v /= READ_PTR_v or LOOPED_v = '1') then
            if READ_PTR_v = std_logic_vector(to_unsigned(FIFO_DEPTH-1, ADDRESS_WIDTH)) then -- Se o ponteiro de leitura for igual a ultima posição da FIFO
                READ_PTR_v := (others => '0'); -- O endereço de leitura é apontado para o inicio da memoria
                LOOPED_v := '0'; -- e o loop finalizado
            else -- Senão o ponteiro de leitura recebe o endereço atual + 1
                READ_PTR_v := std_logic_vector(unsigned(READ_PTR_v) + ADD_ONE);
            end if;
        end if;
        
        -- Se a Ativação de escrita é 1 e o ponteiro de escrita é difente do de leitura ou o LOOP esta desativado
        if WRITE_EN_v = '1' and (WRITE_PTR_v /= READ_PTR_v or LOOPED_v = '0') then
            if WRITE_PTR_v = std_logic_vector(to_unsigned(FIFO_DEPTH-1, ADDRESS_WIDTH)) then -- Se o ponteiro de escrita for igual a ultima posição da FIFO
                WRITE_PTR_v := (others => '0'); -- O Endereço de escrita é apontado para o inicio da memoria
                LOOPED_v := '1'; -- E o LOOP é ativado
            else -- Senão o ponteiro de escrita recebe o endereço atual + 1
                WRITE_PTR_v := std_logic_vector(unsigned(WRITE_PTR_v) + 1);
            end if;
        end if;
        
        if WRITE_PTR_v = READ_PTR_v then -- Caso o ponteiro de escrita e leitura se encontrem ou a memoria estara cheia ou vazia
            if LOOPED_v = '1' then
                EMPTY_v := EMPTY_v;
                FULL_v  := '1';
            else
                EMPTY_v := '1';
                FULL_v  := FULL_v;
            end if;
        else -- Caso contrario ambas as flags serão desativadas
            EMPTY_v := '0';
            FULL_v  := '0';
        end if;
        
        WRITE_PTR_ns    <= WRITE_PTR_v;
        READ_PTR_ns     <= READ_PTR_v;
        LOOPED_ns       <= LOOPED_v;
        EMPTY_ns        <= EMPTY_v;
        FULL_ns         <= FULL_v;
    end process FIFO_PROC;
    
    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                WRITE_PTR_cs <= (others => '0');
                READ_PTR_cs  <= (others => '0');
                LOOPED_cs    <= '0';
                EMPTY_cs     <= '1';
                FULL_cs      <= '0';
            else
                WRITE_PTR_cs <= WRITE_PTR_ns;
                READ_PTR_cs  <= READ_PTR_ns;
                LOOPED_cs    <= LOOPED_ns;
                EMPTY_cs     <= EMPTY_ns;
                FULL_cs      <= FULL_ns;
            end if;
        end if;
    end process SEQ_LOG;
end architecture DIST_RAM_FIFO;