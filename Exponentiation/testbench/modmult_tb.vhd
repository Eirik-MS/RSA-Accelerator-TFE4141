-- Testbench for modular_multiplication
-- Expected values generated with the group's Python model (modular_multiply)
-- Runs a few directed tests, prints PASS/FAIL per test and stops on its own.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity modular_multiplication_tb is
end modular_multiplication_tb;

architecture tb of modular_multiplication_tb is

	constant WIDTH      : positive := 256;
	constant CLK_PERIOD : time     := 10 ns;
	constant MAX_CYCLES : natural  := 2000;   -- timeout per multiplication

	signal clk      : std_logic := '0';
	signal reset_n  : std_logic := '0';
	signal start    : std_logic := '0';
	signal a, b, n  : std_logic_vector(WIDTH-1 downto 0) := (others => '0');
	signal result   : std_logic_vector(WIDTH-1 downto 0);
	signal done     : std_logic;
	signal sim_done : boolean := false;

begin

	-- clock stops when the test is finished, so "run all" ends by itself
	clk <= not clk after CLK_PERIOD/2 when not sim_done;

	dut : entity work.modular_multiplication
		generic map ( WIDTH => WIDTH )
		port map (
			clk     => clk,
			reset_n => reset_n,
			start   => start,
			a       => a,
			b       => b,
			n       => n,
			result  => result,
			done    => done
		);

	stimulus : process
		variable errors : natural := 0;

		procedure run_test(
			constant name     : in string;
			constant a_in     : in std_logic_vector(WIDTH-1 downto 0);
			constant b_in     : in std_logic_vector(WIDTH-1 downto 0);
			constant n_in     : in std_logic_vector(WIDTH-1 downto 0);
			constant expected : in std_logic_vector(WIDTH-1 downto 0)
		) is
			variable cycles : natural := 0;
		begin
			-- apply operands and pulse start for one cycle
			a     <= a_in;
			b     <= b_in;
			n     <= n_in;
			start <= '1';
			wait until rising_edge(clk);
			start <= '0';

			-- wait for done (works for both a pulse and a level)
			loop
				wait until rising_edge(clk);
				cycles := cycles + 1;
				exit when done = '1';
				if cycles >= MAX_CYCLES then
					report name & ": TIMEOUT, done never went high" severity error;
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

			wait until rising_edge(clk);
		end procedure;

		-- helper for small numbers
		function v(x : natural) return std_logic_vector is
		begin
			return std_logic_vector(to_unsigned(x, WIDTH));
		end function;

	begin
		-- reset
		reset_n <= '0';
		wait for 5 * CLK_PERIOD;
		wait until rising_edge(clk);
		reset_n <= '1';
		wait until rising_edge(clk);

		-- small sanity checks (easy to follow in the waveform)
		run_test("small 4*4 mod 33",   v(4),  v(4),  v(33), v(16));
		run_test("small 31*4 mod 33",  v(31), v(4),  v(33), v(25));
		run_test("zero operand",       v(0),  v(17), v(33), v(0));
		run_test("one operand",        v(1),  v(29), v(33), v(29));

		-- random 256-bit vectors from the Python model
		run_test("random 0",
			x"A80B6C1B4E1C53F539459321C892F8A13141C9760F2AA1C69429B4E9C01E9BA5",
			x"0D7523A9ACAB5593D8B6FDBE4152966EE5206AACE1B55AF05C57B5A386F0C68F",
			x"C6CF9EB85C229D2068C49F15B2B934475A8F83EED24BB25C22D08D5C2A2A806D",
			x"9136BFB546AC2055D2E3E565602B0CA569321D7969EB68A17A9F16EB5C6D2B38");

		run_test("random 1",
			x"B9156FBCFB80E449BE8369ADC049DEC1FD9CABCA41F422CD3D7DC862F53E0FF8",
			x"5F0B9D2F1F08E03B77AF3342AD14ACC9969C95C6B8C53ED6F63823F69C216F00",
			x"ED8ABDD0975BA475684276D007B4CAB9F1B166A7C1D756C0BDC79FA24D0F6D5B",
			x"08149E5DC3461D51D502899230ECA6D70C03CE050C4D42F1AFDE110E0DE12319");

		run_test("random 2",
			x"739A4704C209E62F871D60D3B0A7EF78E56CF1C8EE3A31291077512E4B85DD5F",
			x"F141DEAE80A5218C6A8B6D5BC9C1189EBCA7992897BA01F50B8EEF8314A1B7FA",
			x"FF0C271B5505DA59926E5AAC3471660182B1833DC557F5DF35F6045972EDA851",
			x"9888960343EFFA1E884553CBC8A88837242C99F5F19CB8A530F5156C10139B2D");

		-- worst case: (n-1)*(n-1) mod n = 1, intermediate values close to 3n
		run_test("edge (n-1)^2",
			x"CBFA1FF4FF063A013556679B85C9F49E6BA0CF995CD5602D17E889291CE94D56",
			x"CBFA1FF4FF063A013556679B85C9F49E6BA0CF995CD5602D17E889291CE94D56",
			x"CBFA1FF4FF063A013556679B85C9F49E6BA0CF995CD5602D17E889291CE94D57",
			x"0000000000000000000000000000000000000000000000000000000000000001");

		-- summary
		if errors = 0 then
			report "==== modular_multiplication_tb: ALL TESTS PASSED ====";
		else
			report "==== modular_multiplication_tb: " & integer'image(errors) &
			       " TEST(S) FAILED ====" severity error;
		end if;

		sim_done <= true;
		wait;
	end process;

end tb;