use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity TB_LOAD_INTERRUPTION_CONTROL is
end entity TB_LOAD_INTERRUPTION_CONTROL;

architecture BEH of TB_LOAD_INTERRUPTION_CONTROL is
    component DUT is
        generic(
        MATRIX_WIDTH            :  natural := 8;
        WEIGHT_BUFFER_DEPTH     :  natural := 65536
        );
        port(
            CLK, RESET              :  in std_logic;
            ENABLE                  :  in std_logic;

            INSTRUCTION_EN          :  in std_logic;

            BUSY                    :  out std_logic;
            RESOURCE_BUSY           :  out std_logic
        );
    end component DUT;
    for all : DUT use entity WORK.LOAD_INTERRUPTION_CONTROL(BEH);
    
    constant MATRIX_WIDTH        : natural := 8;
    constant WEIGHT_BUFFER_DEPTH : natural := 25;

    signal CLK, RESET            : std_logic;
    signal ENABLE                : std_logic;

    signal INSTRUCTION_EN        : std_logic;
    signal BUSY                  : std_logic;
    signal RESOURCE_BUSY         : std_logic;

    -- For clock gen
    constant clock_period   : time    := 10 ns;
    signal   stop_the_clock : boolean := false;
begin

    DUT_i0 : DUT
    generic map(
        MATRIX_WIDTH          => MATRIX_WIDTH,
        WEIGHT_BUFFER_DEPTH   => WEIGHT_BUFFER_DEPTH
    )
    port map(
        CLK             => CLK, 
        RESET           => RESET,      
        ENABLE          => ENABLE, -- PERMITE QUE O DADO LIDO SEJA LEVADO PARA A SAIDA         
        INSTRUCTION_EN  => INSTRUCTION_EN,
        BUSY            => BUSY,
        RESOURCE_BUSY   => RESOURCE_BUSY
    );

    STIMULUS:
    process is
    begin
        stop_the_clock <= false;
        
        ENABLE          <= '0';
        RESET           <= '0';
        INSTRUCTION_EN  <= '0';

        -- Teste do Reset
        wait until '1'= CLK and CLK'event;
        RESET <= '1';
        wait until '1'= CLK and CLK'event;
        RESET <= '0';

        INSTRUCTION_EN <= '1';
        ENABLE <= '1';

        wait until '1'= CLK and CLK'event;
        INSTRUCTION_EN <= '0';

        wait until BUSY = '0' and RESOURCE_BUSY = '0';
        stop_the_clock <= true;
    end process;
    
    CLOCK_GEN: 
    process
    begin
        while not stop_the_clock loop
          CLK <= '0', '1' after clock_period / 2;
          wait for clock_period;
        end loop;
        wait;
    end process;
end architecture BEH;
