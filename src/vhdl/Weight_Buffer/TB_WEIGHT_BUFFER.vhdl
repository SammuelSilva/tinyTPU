use WORK.TPU_pack.all;
library IEEE;
    use IEEE.std_logic_1164.all;
    use IEEE.numeric_std.all;

entity TB_WEIGHT_BUFFER is
end entity TB_WEIGHT_BUFFER;

architecture BEH of TB_WEIGHT_BUFFER is
    component DUT is
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
    end component DUT;
    for all : DUT use entity WORK.WEIGHT_BUFFER(BEH);

    constant MATRIX_WIDTH   : natural := 14;
    constant TILE_WIDTH     : natural := 32768;  --!< The depth of the buffer.
    constant SIZE_AUX       : natural := 3;

    signal CLK, RESET       : std_logic;
    signal ENABLE           : std_logic;

    type DATA_RAM_IN is array (0 to SIZE_AUX) of BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    type DATA_RAM_OUT is array (0 to SIZE_AUX) of BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1);
    signal DATA_IN_P0         : DATA_RAM_IN;
    signal DATA_IN_P1         : DATA_RAM_IN;
    signal DATA_OUT_P0        : DATA_RAM_OUT;
    signal DATA_OUT_P1        : DATA_RAM_OUT;

    signal   EVALUATE       : boolean := false;
    signal END_EVALUATION   : boolean := false;
    constant INITIAL_POS    : natural := 150;
    constant FINAL_POS      : natural := INITIAL_POS + SIZE_AUX;

-- Port0    
    signal ADDRESS0         : WEIGHT_ADDRESS_TYPE; -- Endereço da porta 0, vetor logico de tamanho 40
    signal EN0              : std_logic; -- ativação da porta 0.
    signal WRITE_EN0        : std_logic; -- ativação de escrita da porta 0.
    signal WRITE_PORT0      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Escrita de dados da porta 0.
    signal READ_PORT0       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Leitura de dados da porta 0.
-- Port1
    signal ADDRESS1         : WEIGHT_ADDRESS_TYPE; -- Endereço da porta 1, vetor logico de tamanho 40
    signal EN1              : std_logic; -- Enable of porta 1.
    signal WRITE_EN1        : std_logic_vector(0 to MATRIX_WIDTH-1); -- ativação de escrita da porta 1.
    signal WRITE_PORT1      : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Escrita de dados da porta 1.
    signal READ_PORT1       : BYTE_ARRAY_TYPE(0 to MATRIX_WIDTH-1); -- Leitura de dados da porta 1.

-- For clock gen
    constant clock_period   : time    := 10 ns;
    signal   stop_the_clock : boolean := false;
begin

    DUT_i0 : DUT
    generic map(
        MATRIX_WIDTH => MATRIX_WIDTH,
        TILE_WIDTH   => TILE_WIDTH
    )
    port map(
        CLK          => CLK, 
        RESET        => RESET,      
        ENABLE       => ENABLE, -- PERMITE QUE O DADO LIDO SEJA LEVADO PARA A SAIDA         
        ADDRESS0     => ADDRESS0,   
        EN0          => EN0, -- PERMITEM A LEITURA DE UM DADO  
        WRITE_EN0    => WRITE_EN0,  -- PERMITEM A ESCRITA DE UM DADO  
        WRITE_PORT0  => WRITE_PORT0,    
        READ_PORT0   => READ_PORT0,   
        ADDRESS1     => ADDRESS1,   
        EN1          => EN1,   -- PERMITEM A LEITURA DE UM DADO  
        WRITE_EN1    => WRITE_EN1,  -- PERMITEM A ESCRITA DE UM DADO  
        WRITE_PORT1  => WRITE_PORT1,   
        READ_PORT1   => READ_PORT1   
    );

    STIMULUS:
    process is
    begin

        for position in INITIAL_POS to FINAL_POS-1 loop
            DATA_IN_P0(position-INITIAL_POS) <= BITS_TO_BYTE_ARRAY(std_logic_vector(to_unsigned(position, BYTE_WIDTH*MATRIX_WIDTH)));
        end loop;
        
        for position in INITIAL_POS to FINAL_POS-1 loop
            DATA_IN_P1(position-INITIAL_POS) <= BITS_TO_BYTE_ARRAY(std_logic_vector(to_unsigned(position-INITIAL_POS+1, BYTE_WIDTH*MATRIX_WIDTH)));
        end loop;

        ENABLE <= '0';
        RESET <= '0';
        EN0 <= '0';
        EN1 <= '0';
        READ_PORT0 <= (others =>(others => '0'));
        READ_PORT1 <= (others =>(others => '0'));

        -- Teste do Reset
        wait until '1'= CLK and CLK'event;
        RESET <= '1';
        wait until '1'= CLK and CLK'event;
        RESET <= '0';
        WRITE_EN1 <= ('1', others => '0');
        WRITE_EN0 <= '1';

        for position in INITIAL_POS to FINAL_POS-1 loop
            -- Inserção dos endereços: PORT0 150 <-> 154, PORT1 0 <-> 4
            --ADDRESS0 <= std_logic_vector(to_unsigned(position, WEIGHT_ADDRESS_WIDTH));
            ADDRESS1 <= std_logic_vector(to_unsigned(position-INITIAL_POS, WEIGHT_ADDRESS_WIDTH));
            -- Inserção dos dados: PORT0 150 <-> 154 Em BYTES, PORT1 0 <-> 4 Em BYTES

            --WRITE_PORT0 <= DATA_IN_P0(position-INITIAL_POS);
            WRITE_PORT1 <= DATA_IN_P1(position-INITIAL_POS);
            --wait until '1'= CLK and CLK'event;
            wait until '1'= CLK and CLK'event;

            EN1 <= '1';
            EN0 <= '1';
            wait until '1'= CLK and CLK'event;
            EN1 <= '0';
            EN0 <= '0';
        end loop;

        WRITE_EN1 <= (others => '0');
        WRITE_EN0 <= '0';

        ENABLE <= '1';
        EN1 <= '0';
        EN0 <= '1';
        for position in INITIAL_POS to FINAL_POS+1-(SIZE_AUX/2) loop
            if position > INITIAL_POS then
                ADDRESS0 <= std_logic_vector(to_unsigned(2*(position-INITIAL_POS-1), WEIGHT_ADDRESS_WIDTH));
                --ADDRESS1 <= std_logic_vector(to_unsigned(position-INITIAL_POS-1, WEIGHT_ADDRESS_WIDTH));
                wait until '1' = CLK and CLK'event;
                wait until '1'= CLK and CLK'event;
                wait until '1'= CLK and CLK'event;
                
                DATA_OUT_P0(position - INITIAL_POS - 1) <= READ_PORT0;
                DATA_OUT_P1(position - INITIAL_POS - 1) <= READ_PORT1;
                wait until '1'= CLK and CLK'event;
                wait until '1'= CLK and CLK'event;

            end if;
        end loop;
        ENABLE <= '0';
        EN1 <= '0';
        EN0 <= '0';
        EVALUATE <= true;
    end process;
    
    EVALUATE_RESULT:
    process is
    begin
        wait until EVALUATE = true;
        wait until '1'= CLK and CLK'event;
        wait until '1'= CLK and CLK'event;        
        for position in INITIAL_POS+1 to FINAL_POS loop
            if DATA_OUT_P0(position-INITIAL_POS)(0)(7 downto 0) /= DATA_IN_P1(position-INITIAL_POS-1)(0)(7 downto 0) then
                report "Test Failed!" severity ERROR;
            end if;
        end loop;
        END_EVALUATION <= true;
    end process;

    stop_the_clock <= END_EVALUATION;

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
