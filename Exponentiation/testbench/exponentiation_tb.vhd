-- Testbench for exponentiation
-- Expected values generated with the group's Python model (modular_exponentiation)
-- Drives the valid/ready handshake like rsa_core does, checks each result,
-- prints the cycle count per message and stops on its own.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity exponentiation_tb is
	generic (
		C_block_size : integer := 256
	);
end exponentiation_tb;

architecture expBehave of exponentiation_tb is

	constant CLK_PERIOD : time    := 10 ns;
	constant MAX_CYCLES : natural := 300000;   -- timeout per message (worst case ~133k)

	signal message   : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
	signal key       : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
	signal valid_in  : std_logic := '0';
	signal ready_in  : std_logic;
	signal ready_out : std_logic := '1';
	signal valid_out : std_logic;
	signal result    : std_logic_vector(C_block_size-1 downto 0);
	signal modulus   : std_logic_vector(C_block_size-1 downto 0) := (others => '0');
	signal clk       : std_logic := '0';
	signal reset_n   : std_logic := '0';
	signal sim_done  : boolean := false;

begin

	-- clock stops when the test is finished, so "run all" ends by itself
	clk <= not clk after CLK_PERIOD/2 when not sim_done;

	i_exponentiation : entity work.exponentiation
		port map (
			message   => message,
			key       => key,
			valid_in  => valid_in,
			ready_in  => ready_in,
			ready_out => ready_out,
			valid_out => valid_out,
			result    => result,
			modulus   => modulus,
			clk       => clk,
			reset_n   => reset_n
		);

	stimulus : process
		variable errors : natural := 0;

		procedure run_test(
			constant name     : in string;
			constant m_in     : in std_logic_vector(C_block_size-1 downto 0);
			constant e_in     : in std_logic_vector(C_block_size-1 downto 0);
			constant n_in     : in std_logic_vector(C_block_size-1 downto 0);
			constant expected : in std_logic_vector(C_block_size-1 downto 0)
		) is
			variable cycles : natural := 0;
		begin
			-- input handshake: hold valid_in until the DUT shows ready_in
			message  <= m_in;
			key      <= e_in;
			modulus  <= n_in;
			valid_in <= '1';
			loop
				wait until rising_edge(clk);
				exit when ready_in = '1';      -- transfer happened on this edge
			end loop;
			valid_in <= '0';
			-- scramble inputs: the DUT must have latched them already
			message  <= (others => 'X');
			key      <= (others => 'X');
			modulus  <= (others => 'X');

			-- output handshake: ready_out is '1', so transfer on first valid_out edge
			loop
				wait until rising_edge(clk);
				cycles := cycles + 1;
				exit when valid_out = '1';
				if cycles >= MAX_CYCLES then
					report name & ": TIMEOUT, valid_out never went high" severity error;
					errors := errors + 1;
					return;
				end if;
			end loop;

			if result = expected then
				report name & ": PASS (" & integer'image(cycles) & " cycles)";
			else
				report name & ": FAIL" & LF &
				       "  expected " & to_hstring(expected) & LF &
				       "  got      " & to_hstring(result) severity error;
				errors := errors + 1;
			end if;
		end procedure;

		function v(x : natural) return std_logic_vector is
		begin
			return std_logic_vector(to_unsigned(x, C_block_size));
		end function;

	begin
		-- reset
		reset_n <= '0';
		wait for 5 * CLK_PERIOD;
		wait until rising_edge(clk);
		reset_n <= '1';
		wait until rising_edge(clk);

		-- small example from the Python model (n = 33, e = 3, d = 7)
		run_test("encrypt 4^3 mod 33",  v(4),  v(3), v(33), v(31));
		run_test("decrypt 31^7 mod 33", v(31), v(7), v(33), v(4));
		run_test("encrypt 6^3 mod 33",  v(6),  v(3), v(33), v(18));
		run_test("exponent 0",          v(5),  v(0), v(33), v(1));

		-- 256-bit, typical public exponent e = 65537
		run_test("256-bit, e = 65537",
			x"3C6C1DF5213ABC8CC00B7B58C0A6175623E94D13954728DF057512335B382A98",
			x"0000000000000000000000000000000000000000000000000000000000010001",
			x"B3E69B6F813D3739BD4A4AED9739B9D970AF50D349BEC67402EED8A58D8D97F5",
			x"8E8308012AF95D78D921A5C913D153FF370B08C4C95A1F758F5EEDCBE76BF388");

		-- 256-bit, full-length exponent (like a private key d)
		run_test("256-bit, full exponent",
			x"95340609EE4782D65A191B845BE72FE6F97B77A442816F3FB953B234AD21E0F0",
			x"A716A83349C758A9F2D93E4DF95D813DE97A2A23FF148D3D05B7F8A101675EA3",
			x"A802D1DD78C26638EC229E63550FB207998151FED775939C410AAE0D5766ADBB",
			x"8EEFDC064D3FFCC96C5FA5EB2EAA49A6FCC176C7E55B8DCD08CD783E606EF73E");

		-- summary
		if errors = 0 then
			report "==== exponentiation_tb: ALL TESTS PASSED ====";
		else
			report "==== exponentiation_tb: " & integer'image(errors) &
			       " TEST(S) FAILED ====" severity error;
		end if;

		sim_done <= true;
		wait;
	end process;

end expBehave;