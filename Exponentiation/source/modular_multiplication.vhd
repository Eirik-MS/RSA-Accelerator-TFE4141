library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity modular_multiplication is
    generic (
        C_block_size : positive := 256
    );
    port (
        clk     : in  std_logic;
        reset_n : in  std_logic;

        start   : in  std_logic;

        a       : in  std_logic_vector(C_block_size-1 downto 0);
        b       : in  std_logic_vector(C_block_size-1 downto 0);
        n       : in  std_logic_vector(C_block_size-1 downto 0);

        result  : out std_logic_vector(C_block_size-1 downto 0);
        done    : out std_logic
    );
end modular_multiplication;


architecture mod_mul_behave of modular_multiplication is 
  
    -- ============================================================
    -- 1. CONTROLLER (FSM)
    -- ============================================================

    type state_t is (IDLE , CALCULATE, DONE_STATE);
    signal state : state_t := IDLE;

    -- ============================================================
    -- 2. REGISTERS
    -- ============================================================

    signal a_reg : unsigned(C_block_size-1 downto 0) := (others => '0');
    signal b_reg : unsigned(C_block_size-1 downto 0) := (others => '0');
    signal n_reg : unsigned(C_block_size-1 downto 0) := (others => '0');
    signal s_reg : unsigned(C_block_size-1 downto 0) := (others => '0');

    -- Number of multiplier bits remaining
    signal bits_left : natural range 0 to C_block_size := 0;

    -- ============================================================
    -- 3. COMBINATIONAL DATAPATH SIGNALS
    -- ============================================================

    -- Intermediate calculations need two extra bits.
    -- 2*S + A can be almost 3*N

    signal shifted_s : unsigned(C_block_size+1 downto 0);
    signal selected_a : unsigned(C_block_size+1 downto 0);
    signal addition_result : unsigned(C_block_size+1 downto 0);

    signal extended_n : unsigned(C_block_size+1 downto 0);
    signal doubled_n : unsigned(C_block_size+1 downto 0);

    signal greater_n : std_logic;
    signal greater_2n : std_logic;

    signal subtraction_operand : unsigned(C_block_size+1 downto 0);
    signal reduced_result : unsigned(C_block_size+1 downto 0);

    signal s_next : unsigned(C_block_size-1 downto 0);

begin
    -- ============================================================
    -- 4. LEFT SHIFT: 2*S
    -- ============================================================
    
    shifted_s <= shift_left(resize(s_reg, C_block_size+2), 1);

    -- ============================================================
    -- 5. MULTIPLEXER: SELECT A OR ZERO
    -- ============================================================

    selected_a <= resize(a_reg, C_block_size+2)
                  when b_reg(C_block_size-1) = '1'
                  else (others => '0');

    -- ============================================================
    -- 6. ADDER: T = 2*S + b_i*A
    -- ============================================================

    addition_result <= shifted_s + selected_a;

    -- ============================================================
    -- 7. MODULUS VALUES: N AND 2*N
    -- ============================================================

    extended_n <= resize(n_reg, C_block_size+2);

    doubled_n <= shift_left(extended_n, 1);

    -- ============================================================
    -- 8. COMPARATORS
    -- ============================================================

    greater_n <= '1' when addition_result >= extended_n
                 else '0';

    greater_2n <= '1' when addition_result >= doubled_n
                  else '0';

    -- ============================================================
    -- 9. MULTIPLEXER: SELECT WHAT TO SUBTRACT
    -- ============================================================

    subtraction_operand <= doubled_n when greater_2n = '1'
                           else extended_n when greater_n = '1'
                           else (others => '0');

    -- ============================================================
    -- 10. SUBTRACTOR: MODULAR REDUCTION
    -- ============================================================

    reduced_result <= addition_result - subtraction_operand;

    -- ============================================================
    -- 11. FEEDBACK TO S REGISTER
    -- ============================================================

    s_next <= reduced_result(C_block_size-1 downto 0);

    -- ============================================================
    -- 12. SEQUENTIAL PROCESS: REGISTERS AND FSM
    -- ============================================================

    process(clk, reset_n)
    begin

        -- Asynchronous active-low reset
        if reset_n = '0' then
            state <= IDLE;
            
            a_reg <= (others => '0');
            b_reg <= (others => '0');
            n_reg <= (others => '0');
            s_reg <= (others => '0');

            bits_left <= 0;

        elsif rising_edge(clk) then

            case state is

                -- ------------------------------------------------
                -- IDLE: Wait for a new multiplication
                -- ------------------------------------------------

                when IDLE =>

                    if start = '1' then

                        -- Load operands into registers
                        a_reg <= unsigned(a);
                        b_reg <= unsigned(b);
                        n_reg <= unsigned(n);

                        -- Iniitialize partial result
                        s_reg <= (others => '0');

                        -- Process exactly C_block_size bits
                        bits_left <= C_block_size;

                        -- Start calculation
                        state <= CALCULATE;
                    end if;

                -- ------------------------------------------------
                -- CALCULATE: Process one multiplier bit per cycle
                -- ------------------------------------------------

                when CALCULATE =>

                    -- Store the new recuced partial result
                    s_reg <= s_next;
                    
                    -- Shift multiplier to expose its next bit
                    b_reg <= shift_left(b_reg, 1);

                    -- Update bit counter
                    if bits_left = 1 then

                        bits_left <= 0;
                        state <= DONE_STATE;

                    else

                        bits_left <= bits_left - 1;

                    end if;

                -- ------------------------------------------------
                -- DONE_STATE: Signal completion
                -- ------------------------------------------------

                when DONE_STATE =>

                    state <= IDLE;

            end case;

        end if;

    end process;

    -- ============================================================
    -- 13. OUTPUT SIGNALS
    -- ============================================================

    result <= std_logic_vector(s_reg);

    done <= '1' when state = DONE_STATE else '0';

    
end mod_mul_behave;


