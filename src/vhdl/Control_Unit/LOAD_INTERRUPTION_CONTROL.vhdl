use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    use IEEE.math_real.log2;
    use IEEE.math_real.ceil;

entity LOAD_INTERRUPTION_CONTROL is
    generic(
        MATRIX_WIDTH            :  natural := 8;
        WEIGHT_BUFFER_DEPTH     :  natural := 32768
    );
    port(
        CLK, RESET              :  in std_logic;
        ENABLE                  :  in std_logic;

        INSTRUCTION_EN          :  in std_logic;

        BUSY                    :  out std_logic;
        RESOURCE_BUSY           :  out std_logic
    );
end entity LOAD_INTERRUPTION_CONTROL;

architecture BEH of LOAD_INTERRUPTION_CONTROL is
    constant DELAY_CLK          : natural   := 9;

    signal RUNNING_cs           : std_logic := '0';
    signal RUNNING_ns           : std_logic;

    signal RUNNING_PIPE_cs      : std_logic_vector(0 to DELAY_CLK-1) := (others => '0');
    signal RUNNING_PIPE_ns      : std_logic_vector(0 to DELAY_CLK-1);

    signal ACTIVE_COUNTER_cs    : std_logic := '0';
    signal ACTIVE_COUNTER_ns    : std_logic;

    signal DEPTH_REACHED        : std_logic := '0';

    signal COUNTER              : natural := 0;
begin

    BUSY <= RUNNING_cs;
    RUNNING_PIPE_ns(0) <= RUNNING_cs;
    RUNNING_PIPE_ns(1 to 2) <= RUNNING_PIPE_cs(0 to 1);
    RUNNING_PIPE_ns(2 to 3) <= RUNNING_PIPE_cs(1 to 2);
    RUNNING_PIPE_ns(3 to 4) <= RUNNING_PIPE_cs(2 to 3);
    RUNNING_PIPE_ns(4 to 5) <= RUNNING_PIPE_cs(3 to 4);
    RUNNING_PIPE_ns(5 to 6) <= RUNNING_PIPE_cs(4 to 5);
    RUNNING_PIPE_ns(6 to 7) <= RUNNING_PIPE_cs(5 to 6);
    RUNNING_PIPE_ns(7 to 8) <= RUNNING_PIPE_cs(6 to 7);

    CONTROL:
    process(INSTRUCTION_EN, DEPTH_REACHED, RUNNING_cs) is
        variable INSTRUCTION_EN_v  : std_logic;
        variable RUNNING_v         : std_logic;
        variable DEPTH_REACHED_v   : std_logic;
        variable ACTIVE_COUNTER_v  : std_logic;
    begin
        INSTRUCTION_EN_v := INSTRUCTION_EN;
        RUNNING_v        := RUNNING_cs;
        DEPTH_REACHED_v  := DEPTH_REACHED;

        --synthesis translate_off
        if INSTRUCTION_EN_v = '1' and RUNNING_v = '1' then
            report "New Instruction shouldn't be feeded while processing! LOAD_INTERRUPTION_CONTROL.vhdl" severity warning;
        end if;
        --synthesis translate_on 
        
        if RUNNING_v = '0' then
            if INSTRUCTION_EN_v = '1' then
                RUNNING_v        := '1';
                ACTIVE_COUNTER_v := '1';
            else
                RUNNING_v        := '0';
                ACTIVE_COUNTER_v := '0';
            end if;
        else
            if DEPTH_REACHED_v = '1' then
                RUNNING_v        := '0';
                ACTIVE_COUNTER_v := '0';
            else
                RUNNING_v        := '1';
                ACTIVE_COUNTER_v := '1';
            end if;
        end if;

        RUNNING_ns        <= RUNNING_v;
        ACTIVE_COUNTER_ns <= ACTIVE_COUNTER_v;
    end process CONTROL;

    RESOURCE:
    process(RUNNING_cs, RUNNING_PIPE_cs) is
        variable RESOURCE_BUSY_v : std_logic;
    begin
        RESOURCE_BUSY_v := RUNNING_cs;
        for i in 0 to (DELAY_CLK-1) loop
            RESOURCE_BUSY_v := RESOURCE_BUSY_v or RUNNING_PIPE_cs(i);
        end loop;
        RESOURCE_BUSY <= RESOURCE_BUSY_v;
    end process RESOURCE;


    CHECK_DEPTH:
    process(ACTIVE_COUNTER_cs, COUNTER) is
        variable DEPTH_REACHED_v  : std_logic;
        variable ACTIVE_COUNTER_v : std_logic;
        variable COUNTER_v        : natural;
    begin

        ACTIVE_COUNTER_v := ACTIVE_COUNTER_cs;
        COUNTER_v        := COUNTER;

        if ACTIVE_COUNTER_v = '1' then
            if COUNTER_v = WEIGHT_BUFFER_DEPTH then
                DEPTH_REACHED_v := '1';
            end if;
        else
            DEPTH_REACHED_v := '0';
        end if;
            
        DEPTH_REACHED <= DEPTH_REACHED_v;
    end process CHECK_DEPTH;

    SEQ_LOG:
    process(CLK) is
    begin
        if CLK'event and CLK = '1' then
            if RESET = '1' then
                COUNTER           <=  0;
                ACTIVE_COUNTER_cs <= '0';
                RUNNING_PIPE_cs   <= (others => '0');
            else
                if ENABLE = '1' then
                    ACTIVE_COUNTER_cs <= ACTIVE_COUNTER_ns;
                    RUNNING_PIPE_cs   <= RUNNING_PIPE_ns;
                    RUNNING_cs        <= RUNNING_ns;

                    if ACTIVE_COUNTER_cs = '1' then
                        if DEPTH_REACHED = '0' then
                            COUNTER <= COUNTER + 1;
                        end if;
                    else
                        COUNTER <= 0;
                    end if;
                end if;
            end if;
        end if;
    end process SEQ_LOG;

end architecture BEH;