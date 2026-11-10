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
    -- Precompute -N when accepting operands, off the per-bit feedback path.
    signal negative_n_reg : unsigned(C_block_size+1 downto 0) := (others => '0');
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

    signal negative_2n : unsigned(C_block_size+1 downto 0);
    signal sum_n, carry_n, sum_2n, carry_2n : unsigned(C_block_size+1 downto 0);

    signal sub_n  : unsigned(C_block_size+1 downto 0);
    signal sub_2n : unsigned(C_block_size+1 downto 0);


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
    -- 7. CARRY-SAVE REDUCTION CANDIDATES
    -- ============================================================

    -- Addition modulo 2^(k+2) gives T-N and T-2N. Compress the three
    -- operands with local XOR/majority logic, then propagate carry ONCE.
    -- This avoids cascading the T adder into a full-width subtractor.
    -- negative_2n is just wiring; -N was registered at operand acceptance.
    negative_2n <= shift_left(negative_n_reg, 1);
    sum_n <= shifted_s xor selected_a xor negative_n_reg;
    carry_n <= shift_left((shifted_s and selected_a) or
                         (shifted_s and negative_n_reg) or
                         (selected_a and negative_n_reg), 1);
    sum_2n <= shifted_s xor selected_a xor negative_2n;
    carry_2n <= shift_left((shifted_s and selected_a) or
                          (shifted_s and negative_2n) or
                          (selected_a and negative_2n), 1);
    sub_n <= sum_n + carry_n;
    sub_2n <= sum_2n + carry_2n;

    -- For 0 <= A,S < N, T=2*S+b_i*A < 3*N. Both T-N and T-2N
    -- fit signed (k+2) bits, so the top bit still indicates negativity.

    -- ============================================================
    -- 9. MULTIPLEXER: SELECT REDUCED RESULT
    -- ============================================================

    s_next <= sub_2n(C_block_size-1 downto 0)
                  when sub_2n(C_block_size+1) = '0'
              else sub_n(C_block_size-1 downto 0)
                  when sub_n(C_block_size+1) = '0'
              else addition_result(C_block_size-1 downto 0);


    -- ============================================================
    -- 10. SEQUENTIAL PROCESS: REGISTERS AND FSM
    -- ============================================================

    process(clk, reset_n)
    begin

        -- Asynchronous active-low reset
        if reset_n = '0' then
            state <= IDLE;
            
            a_reg <= (others => '0');
            b_reg <= (others => '0');
            negative_n_reg <= (others => '0');
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
                        negative_n_reg <= to_unsigned(0, C_block_size+2) -
                                          resize(unsigned(n), C_block_size+2);

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


