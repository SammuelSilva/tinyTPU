use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;
    
entity TB_TPU_MINE is
end entity TB_TPU_MINE;

architecture BEH of TB_TPU_MINE is
    component DUT is
        generic(
            MATRIX_WIDTH            : natural := 14
        );  
        port(   
            CLK, RESET              : in  std_logic;
            ENABLE                  : in  std_logic;

            -- entradas das instruções divididas (16b, 32b, 32b)
            LOWER_INSTRUCTION_WORD  : in  WORD_TYPE;
            MIDDLE_INSTRUCTION_WORD : in  WORD_TYPE;
            UPPER_INSTRUCTION_WORD  : in  HALFWORD_TYPE;
            INSTRUCTION_WRITE_EN    : in  std_logic_vector(0 to 2);
            -- Flags para interrupções do buffer
            INSTRUCTION_EMPTY       : out std_logic;
            INSTRUCTION_FULL        : out std_logic;

            -- Dados do Weight Buffer
            WEIGHT_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            WEIGHT_ADDRESS          : in  WEIGHT_ADDRESS_TYPE;
            WEIGHT_ENABLE           : in  std_logic;
            WEIGHT_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1);
                
            -- Dados do Unified Buffer
            BUFFER_WRITE_PORT       : in  BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_READ_PORT        : out BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
            BUFFER_ADDRESS          : in  BUFFER_ADDRESS_TYPE;
            BUFFER_ENABLE           : in  std_logic;
            BUFFER_WRITE_ENABLE     : in  std_logic_vector(0 to MATRIX_WIDTH-1);
            -- Memory synchronization flag for interrupt 
            SYNCHRONIZE             : out std_logic
        );
    end component DUT;
    for all : DUT use entity WORK.TPU(BEH);

    constant MATRIX_WIDTH           : natural := 14;
    constant LOAD_WEIGHT            : std_logic_vector (BYTE_WIDTH-1 downto 0) := "00001000";
    constant MATRIX_MUTIPLY         : std_logic_vector (BYTE_WIDTH-1 downto 0) := "00100000";
    constant SIGMOID_ACT            : std_logic_vector (BYTE_WIDTH-1 downto 0) := "10001001";
    constant SYNCHRONIZE_CONST      : std_logic_vector (BYTE_WIDTH-1 downto 0) := "11111111";

    signal CLK                      : std_logic;
    signal RESET                    : std_logic;
    signal ENABLE                   : std_logic;
        
    -- Sinal para a instrução a ser inserida na TPU
    signal INSTRUCTION : INSTRUCTION_TYPE;

    -- Sinais para as entradas das instruções divididas (16b, 32b, 32b)
    signal LOWER_INSTRUCTION_WORD   : WORD_TYPE;
    signal MIDDLE_INSTRUCTION_WORD  : WORD_TYPE;
    signal UPPER_INSTRUCTION_WORD   : HALFWORD_TYPE;
    signal INSTRUCTION_WRITE_EN     : std_logic_vector(0 to 2);
    
    -- Sinais para as flags para interrupções do buffer
    signal INSTRUCTION_EMPTY        : std_logic;
    signal INSTRUCTION_FULL         : std_logic;

    -- Sinais para o Weight e Unified Buffer
    signal WEIGHT_WRITE_PORT        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal WEIGHT_ADDRESS           : WEIGHT_ADDRESS_TYPE;
    signal WEIGHT_ENABLE            : std_logic;
    signal WEIGHT_WRITE_ENABLE      : std_logic_vector(0 to MATRIX_WIDTH-1);
            
    signal BUFFER_WRITE_PORT        : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_READ_PORT         : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal BUFFER_ADDRESS           : BUFFER_ADDRESS_TYPE;
    signal BUFFER_ENABLE            : std_logic;
    signal BUFFER_WRITE_ENABLE      : std_logic_vector(0 to MATRIX_WIDTH-1);
        
    signal SYNCHRONIZE              : std_logic;

    -- Para geração do sinal de clock
    constant clock_period   : time := 10 ns;
    signal stop_the_clock   : boolean;

begin
    DUT_i : DUT
    generic map(
        MATRIX_WIDTH => MATRIX_WIDTH
    )
    port map(
        CLK => CLK,
        RESET => RESET,
        ENABLE => ENABLE,

        LOWER_INSTRUCTION_WORD => LOWER_INSTRUCTION_WORD,
        MIDDLE_INSTRUCTION_WORD => MIDDLE_INSTRUCTION_WORD,
        UPPER_INSTRUCTION_WORD => UPPER_INSTRUCTION_WORD,
        
        INSTRUCTION_WRITE_EN => INSTRUCTION_WRITE_EN,
        INSTRUCTION_EMPTY => INSTRUCTION_EMPTY,
        INSTRUCTION_FULL => INSTRUCTION_FULL,
        
        WEIGHT_WRITE_PORT => WEIGHT_WRITE_PORT,
        WEIGHT_ADDRESS => WEIGHT_ADDRESS,
        WEIGHT_ENABLE => WEIGHT_ENABLE,
        WEIGHT_WRITE_ENABLE => WEIGHT_WRITE_ENABLE,
        
        BUFFER_WRITE_PORT => BUFFER_WRITE_PORT,
        BUFFER_READ_PORT => BUFFER_READ_PORT,
        BUFFER_ADDRESS => BUFFER_ADDRESS,
        BUFFER_ENABLE => BUFFER_ENABLE,
        BUFFER_WRITE_ENABLE => BUFFER_WRITE_ENABLE,
        
        SYNCHRONIZE => SYNCHRONIZE
    );

    LOWER_INSTRUCTION_WORD <= INSTRUCTION_TO_BITS(INSTRUCTION)(4*BYTE_WIDTH-1 downto 0); -- 32 Bits
    MIDDLE_INSTRUCTION_WORD <= INSTRUCTION_TO_BITS(INSTRUCTION)(2*4*BYTE_WIDTH-1 downto 4*BYTE_WIDTH); -- 32 bits
    UPPER_INSTRUCTION_WORD <= INSTRUCTION_TO_BITS(INSTRUCTION)(2*4*BYTE_WIDTH+2*BYTE_WIDTH-1 downto 2*4*BYTE_WIDTH); -- 16 bits
    
    STIMULUS:
    process is
    begin
        report "INITIALIZATION: BEGIN" severity NOTE ;

            ENABLE <= '0';
            RESET <= '0';
            INSTRUCTION <= INIT_INSTRUCTION;
            INSTRUCTION_WRITE_EN <= (others => '0');
            WEIGHT_ADDRESS <= (others => '0');
            WEIGHT_WRITE_PORT <= (others => (others => '0'));
            WEIGHT_ENABLE <= '0';
            WEIGHT_WRITE_ENABLE <= (others => '0');
            BUFFER_ADDRESS <= (others => '0');
            BUFFER_WRITE_PORT <= (others => (others => '0'));
            BUFFER_ENABLE <= '0';
            BUFFER_WRITE_ENABLE <= (others => '0');
        
        report "INITIALIZATION: ENDS" severity NOTE ;
        wait until '1' = CLK and CLK'event;

        report "lOAD WEIGHT: BEGIN" severity NOTE ;
            ENABLE <= '1';

            INSTRUCTION.OP_CODE <= LOAD_WEIGHT;
            INSTRUCTION.CALC_LENGTH <= std_logic_vector(to_unsigned(14, LENGTH_WIDTH));
            INSTRUCTION.BUFFER_ADDRESS <= x"000000";
            INSTRUCTION.ACC_ADDRESS <= x"0000";

            INSTRUCTION_WRITE_EN <= (others => '1');

        report "lOAD WEIGHT: END" severity NOTE ;
        wait until '1' = CLK and CLK'event;

        report "MATRIX MULTIPLY: BEGIN" severity NOTE;
            INSTRUCTION.OP_CODE <= MATRIX_MUTIPLY;
            INSTRUCTION.CALC_LENGTH <= std_logic_vector(to_unsigned(14, LENGTH_WIDTH));
            INSTRUCTION.BUFFER_ADDRESS <= x"000000"; 
            INSTRUCTION.ACC_ADDRESS <= x"0000";

        report "MATRIX MULTIPLY: END" severity NOTE ;
        wait until '1' = CLK and CLK'event;

        report "SIGMOID ACTIVATION: BEGIN" severity NOTE;
            INSTRUCTION.OP_CODE <= SIGMOID_ACT;
            INSTRUCTION.CALC_LENGTH <= std_logic_vector(to_unsigned(14, LENGTH_WIDTH));
            INSTRUCTION.BUFFER_ADDRESS <= x"000000"; 
            INSTRUCTION.ACC_ADDRESS <= x"0000";

        report "SIGMOID ACTIVATION: END" severity NOTE ;
        wait until '1' = CLK and CLK'event;
        
        report "lOAD WEIGHT: BEGIN" severity NOTE ;
            ENABLE <= '1';

            INSTRUCTION.OP_CODE <= LOAD_WEIGHT;
            INSTRUCTION.CALC_LENGTH <= std_logic_vector(to_unsigned(14, LENGTH_WIDTH));
            INSTRUCTION.BUFFER_ADDRESS <= x"00000E"; -- Endereço 14 pra cima
            INSTRUCTION.ACC_ADDRESS <= x"0001";

            INSTRUCTION_WRITE_EN <= (others => '1');

        report "lOAD WEIGHT: END" severity NOTE ;
        wait until '1' = CLK and CLK'event;

        report "SYNCHRONIZE: BEGIN" severity NOTE ;
            INSTRUCTION.OP_CODE <= SYNCHRONIZE_CONST;
            INSTRUCTION.CALC_LENGTH <= x"00000000";
            INSTRUCTION.BUFFER_ADDRESS <= x"000000";
            INSTRUCTION.ACC_ADDRESS <= x"0000";
        report "SYNCHRONIZE: END" severity NOTE ;
        wait until SYNCHRONIZE = '1';

        INSTRUCTION_WRITE_EN <= (others => '0');
        wait;
    end process STIMULUS;

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