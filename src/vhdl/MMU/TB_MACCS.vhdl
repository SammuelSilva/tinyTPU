use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity TB_MACCS is
end entity TB_MACCS;

architecture BEH of TB_MACCS is
    component DUT is
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
        ZERO_FIRST            : in std_logic;
        ZERO_LAST             : in std_logic;
        -- Output
        PARTIAL_SUM     : out std_logic_vector(PARTIAL_SUM_WIDTH-1 downto 0) --!< Saida do registro do valor parcial da soma.
    );
    end component DUT;
    for all : DUT use entity WORK.MACC(BEH);

    constant SUM_WIDTH             : natural := 2*EXTENDED_BYTE_WIDTH;
    constant LAST_SUM_WIDTH_DUT1   : natural := 2*EXTENDED_BYTE_WIDTH;

    -- Device Under Test 1
    signal CLK, RESET            : std_logic;
    signal ENABLE_DUT1           : std_logic;
    signal PRELOAD_WEIGHT_DUT1   : std_logic;
    signal LOAD_WEIGHT_DUT1      : std_logic;
    signal WEIGHT_INPUT_DUT1     : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1);
    signal INPUT_DUT1            : EXTENDED_BYTE_ARRAY(0 to NUMBER_OF_MULT-1);
    signal ZERO_DUT1             : std_logic_vector(0 to NUMBER_OF_MULT-1);
    signal LAST_SUM_DUT1         : std_logic_vector(LAST_SUM_WIDTH_DUT1-1 downto 0);
    signal PARTIAL_SUM_DUT1      : std_logic_vector(SUM_WIDTH-1 downto 0);    
    
    signal RESULT_NOW       : std_logic;

    -- for clock gen
    constant clock_period   : time := 10 ns;
    signal stop_the_clock   : boolean;
    signal QUIT_CLOCK0      : boolean := false;
    signal QUIT_CLOCK1      : boolean := false;
    signal flag             : boolean := false;
    
    signal RESULT_FINAL     : std_logic_vector(SUM_WIDTH-1 downto 0) := (others => '0');
begin

    DUT_i1 : DUT
    generic map(
        LAST_SUM_WIDTH_DUT1,
        SUM_WIDTH
    )
    port map(
        CLK => CLK,
        RESET => RESET,
        ENABLE => ENABLE_DUT1,
        WEIGHT_INPUT_FIRST => WEIGHT_INPUT_DUT1(0),
        WEIGHT_INPUT_LAST => WEIGHT_INPUT_DUT1(1),
        PRELOAD_WEIGHT => PRELOAD_WEIGHT_DUT1,
        LOAD_WEIGHT => LOAD_WEIGHT_DUT1,
        INPUT_FIRST => INPUT_DUT1(0),
        INPUT_LAST => INPUT_DUT1(1),
        ZERO_FIRST => ZERO_DUT1(0),
        ZERO_LAST => ZERO_DUT1(1),
        LAST_SUM => LAST_SUM_DUT1,
        PARTIAL_SUM => PARTIAL_SUM_DUT1
    );
                
    STIMULUS_DUT_i1:
    process is
    begin
        ENABLE_DUT1 <= '0';
        PRELOAD_WEIGHT_DUT1 <= '0';
        LOAD_WEIGHT_DUT1 <= '0';
        RESET <= '0';
        LAST_SUM_DUT1 <= (others => '0');

        wait until CLK = '1' and CLK'event;
        RESET <= '1';
        wait until CLK = '1' and CLK'event;
        RESET <= '0';

        for INPUT_VAL in 1 to 4 loop

            for i in 0 to NUMBER_OF_MULT-1 loop

                if (INPUT_VAL + i) = 0 then
                    ZERO_DUT1(i) <= '1';
                else
                    ZERO_DUT1(i) <= '0';
                end if;

                INPUT_DUT1(i) <= std_logic_vector(to_unsigned(INPUT_VAL + i, EXTENDED_BYTE_WIDTH));
            end loop;

            for WEIGHT_VAL in 0 to 3 loop

                for i in 0 to NUMBER_OF_MULT-1 loop
                    WEIGHT_INPUT_DUT1(i) <= std_logic_vector(to_unsigned(WEIGHT_VAL + i, EXTENDED_BYTE_WIDTH));
                end loop;

                PRELOAD_WEIGHT_DUT1 <= '1';
                wait until '1'=CLK and CLK'event;
                LOAD_WEIGHT_DUT1 <= '1';
                PRELOAD_WEIGHT_DUT1 <= '0';
                wait until '1'=CLK and CLK'event;
                ENABLE_DUT1 <= '1';     
                LOAD_WEIGHT_DUT1 <= '0';
                wait until '1'=CLK and CLK'event;
                wait until '1'=CLK and CLK'event;
                wait until '1'=CLK and CLK'event;

                wait for 1 ns;
                if PARTIAL_SUM_DUT1 /=  std_logic_vector(signed(WEIGHT_INPUT_DUT1(0)) * signed(INPUT_DUT1(0)) + signed(WEIGHT_INPUT_DUT1(1)) * signed(INPUT_DUT1(1)) + signed(LAST_SUM_DUT1)) then
                    report "Result is not correct! DUT1" severity ERROR;
                    QUIT_CLOCK1 <= true;
                wait;
                end if;

                wait until '1'=CLK and CLK'event;
                LAST_SUM_DUT1 <= std_logic_vector(signed(WEIGHT_INPUT_DUT1(0)) * signed(INPUT_DUT1(0)) + signed(WEIGHT_INPUT_DUT1(1)) * signed(INPUT_DUT1(1)) + signed(LAST_SUM_DUT1));
            end loop;
        end loop;
        QUIT_CLOCK1 <= true;
        wait;
    end process;

    stop_the_clock <= QUIT_CLOCK1;

    CLOCK_GEN: 
    process
    begin
        while not stop_the_clock loop
          CLK <= '0', '1' after clock_period / 2;
          wait for clock_period;
        end loop;
        wait;
    end process CLOCK_GEN;
end architecture BEH;