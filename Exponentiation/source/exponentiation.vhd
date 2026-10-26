library ieee;
use ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;



entity exponentiation is
	generic (
		C_block_size : integer := 256
	);
	port (
		--input controll
		valid_in	: in STD_LOGIC;
		ready_in	: out STD_LOGIC;

		--input data
		message 	: in STD_LOGIC_VECTOR ( C_block_size-1 downto 0 );
		key 		: in STD_LOGIC_VECTOR ( C_block_size-1 downto 0 );

		--ouput controll
		ready_out	: in STD_LOGIC;
		valid_out	: out STD_LOGIC;

		--output data
		result 		: out STD_LOGIC_VECTOR(C_block_size-1 downto 0);

		--modulus
		modulus 	: in STD_LOGIC_VECTOR(C_block_size-1 downto 0);

		--utility
		clk 		: in STD_LOGIC;
		reset_n 	: in STD_LOGIC		
	);
end exponentiation;


architecture expBehave of exponentiation is
	type exp_state_t is (IDLE, CHECK, MULT_START, MULT_WAIT, SQUARE_START, SQUARE_WAIT, SHIFT, DONE);
	signal state, next_state : exp_state_t;  

	-- input registers
	signal R_reg, P_reg, N_reg, E_reg : STD_LOGIC_VECTOR(C_block_size-1 downto 0);
	signal mm_a, mm_result : STD_LOGIC_VECTOR(C_block_size-1 downto 0);

	-- controller inputs 
    signal start     : std_logic;
    signal mm_done   : std_logic;
    signal e_bit     : std_logic;
    signal e_zero    : std_logic;

    -- controller outputs
    signal result_we : std_logic;
    signal power_we  : std_logic;
    signal done_sig  : std_logic;
    signal mm_start  : std_logic;
    signal mux_a_sel : std_logic;   -- '0' = R_reg, '1' = P_reg
    signal e_shift   : std_logic;
    signal init      : std_logic;

begin
	-- direct mapping
	start     <= valid_in when state = IDLE else '0';
    ready_in  <= '1' when state = IDLE else '0';
    valid_out <= done_sig;
    result    <= R_reg;

    e_bit  <= E_reg(0);
    e_zero <= '1' when Unsigned(E_reg) = 0 else '0';

    mm_a <= R_reg when mux_a_sel = '0' else P_reg;

	exponentiation_state_machine_proc : process(all)
	begin
		--default values
		next_state <= state;
		result_we  <= '0';
        power_we   <= '0';
        done_sig   <= '0';
        mm_start   <= '0';
        mux_a_sel  <= '0';
		e_shift    <= '0';
		init       <= '0';

		case state is
			when IDLE =>
				if start = '1' then 
					init <= '1';
					next_state <= CHECK;
				end if;

			when CHECK =>
            	if e_zero = '1' then
            	    next_state <= DONE;
            	elsif e_bit = '1' then
            	    next_state <= MULT_START;
            	else
            	    next_state <= SQUARE_START;
            	end if;

        	when MULT_START =>
        		mm_start   <= '1';
        	    mux_a_sel  <= '0';          -- R_reg * P_reg
        	    next_state <= MULT_WAIT;

        	when MULT_WAIT =>
        	    if mm_done = '1' then
        	        result_we  <= '1';
        	        next_state <= SQUARE_START;
        	    end if;

        	when SQUARE_START =>
        	    mm_start   <= '1';
        	    mux_a_sel  <= '1';          -- P_reg * P_reg
        	    next_state <= SQUARE_WAIT;

        	when SQUARE_WAIT =>
        	    if mm_done = '1' then
        	        power_we   <= '1';
        	        next_state <= SHIFT;
        	    end if;

        	when SHIFT =>
        	    e_shift    <= '1';
        	    next_state <= CHECK;

        	when DONE =>
        	    done_sig <= '1';
        	    if ready_out = '1' then
        	        next_state <= IDLE;
        	    end if;
		end case;
	end process;

	exponentiation_state_machine_update : process(clk, reset_n)
	begin
		if reset_n = '0' then
			state <= IDLE;
		elsif rising_edge(clk) then
			state <= next_state;
		end if;
	end process;

	datapath_proc : process(clk)
	begin
	    if rising_edge(clk) then
	        if init = '1' then
	            R_reg <= (0 => '1', others => '0');    -- R = 1
	            P_reg <= message;
	            E_reg <= key;
	            N_reg <= modulus;
	        else
	            if result_we = '1' then R_reg <= mm_result; end if;
	            if power_we  = '1' then P_reg <= mm_result; end if;
	            if e_shift   = '1' then E_reg <= '0' & E_reg(C_block_size-1 downto 1); end if;
	        end if;
	    end if;
	end process;
	
	u_modmult : entity work.modular_multiplication
    port map (
        -- modmult port  =>  exponentiation signal
        clk     => clk,         -- same clock
        reset_n => reset_n,     -- same reset
        start   => mm_start,    -- FSM output    -> modmult input
        a       => mm_a,        -- mux output    -> modmult input
        b       => P_reg,       -- register      -> modmult input
        n       => N_reg,       -- register      -> modmult input
        result  => mm_result,   -- modmult output -> datapath process
        done    => mm_done      -- modmult output -> FSM input
    );

	
end expBehave;
