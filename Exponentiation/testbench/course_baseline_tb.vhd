-- Course notebook case 4: decrypt ct4_in.txt using its exact RSA key.
-- This tests exponentiation only, not AXI, DMA, or packet boundaries.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity course_baseline_tb is
  generic (
    INPUT_FILE : string := "course_vectors/ct4_in.hex";
    EXPECTED_FILE : string := "course_vectors/pt4_expected.hex";
    MAX_BLOCKS : natural := 0; -- 0 = all 882 blocks; 1 = quick smoke test
    CLOCK_PERIOD : time := 10 ns
  );
end entity;

architecture sim of course_baseline_tb is
  constant KEY_N : std_logic_vector(255 downto 0) :=
    x"99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d";
  constant KEY_D : std_logic_vector(255 downto 0) :=
    x"0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9";
  constant EXPECTED_BLOCKS : positive := 882;
  constant TIMEOUT_CYCLES : positive := 300000;
  signal clk : std_logic := '0';
  signal reset_n : std_logic := '0';
  signal message, key, modulus : std_logic_vector(255 downto 0) := (others => '0');
  signal result : std_logic_vector(255 downto 0);
  signal valid_in : std_logic := '0';
  signal ready_in, valid_out : std_logic;
begin
  clk <= not clk after CLOCK_PERIOD / 2;
  dut : entity work.exponentiation
    generic map (C_block_size => 256)
    port map (
      clk => clk, reset_n => reset_n,
      message => message, key => key, modulus => modulus,
      valid_in => valid_in, ready_in => ready_in,
      valid_out => valid_out, ready_out => '1', result => result
    );

  stimulus : process
    file inputs : text open read_mode is INPUT_FILE;
    file expected_values : text open read_mode is EXPECTED_FILE;
    variable input_line, expected_line : line;
    variable input_block, expected_block : std_logic_vector(255 downto 0);
    variable good : boolean;
    variable blocks, cycles, wait_cycles, total_cycles : natural := 0;
    variable min_cycles : natural := natural'high;
    variable max_cycles : natural := 0;
    variable batch_start : time;
  begin
    assert MAX_BLOCKS <= EXPECTED_BLOCKS report "MAX_BLOCKS must be 0..882" severity failure;
    wait for 5 * CLOCK_PERIOD;
    wait until rising_edge(clk);
    reset_n <= '1';
    wait until rising_edge(clk);
    batch_start := now;

    while not endfile(inputs) loop
      exit when MAX_BLOCKS /= 0 and blocks = MAX_BLOCKS;
      assert not endfile(expected_values) report "Missing expected block" severity failure;
      readline(inputs, input_line);
      readline(expected_values, expected_line);
      hread(input_line, input_block, good);
      assert good report "Invalid input hex" severity failure;
      hread(expected_line, expected_block, good);
      assert good report "Invalid expected hex" severity failure;

      message <= input_block;
      key <= KEY_D;
      modulus <= KEY_N;
      valid_in <= '1';
      wait_cycles := 0;
      loop
        wait until rising_edge(clk);
        wait_cycles := wait_cycles + 1;
        exit when ready_in = '1';
        assert wait_cycles < TIMEOUT_CYCLES report "Input handshake timeout" severity failure;
      end loop;
      valid_in <= '0';
      -- Verify the DUT captured its operands at the input handshake.
      message <= (others => 'X');
      key <= (others => 'X');
      modulus <= (others => 'X');

      cycles := 0;
      loop
        wait until rising_edge(clk);
        cycles := cycles + 1;
        exit when valid_out = '1';
        assert cycles < TIMEOUT_CYCLES report "Output timeout" severity failure;
      end loop;
      assert result = expected_block
        report "Block " & integer'image(blocks) & " FAIL: expected " &
          to_hstring(expected_block) & ", got " & to_hstring(result)
        severity failure;
      total_cycles := total_cycles + cycles;
      if cycles < min_cycles then min_cycles := cycles; end if;
      if cycles > max_cycles then max_cycles := cycles; end if;
      blocks := blocks + 1;
      if blocks mod 100 = 0 then
        report "Checked " & integer'image(blocks) & " blocks";
      end if;
    end loop;

    if MAX_BLOCKS = 0 then
      assert blocks = EXPECTED_BLOCKS report "Expected exactly 882 input blocks" severity failure;
      assert endfile(expected_values) report "Extra expected blocks" severity failure;
      report "FULL COURSE CASE 4: ALL 882 BLOCKS PASSED";
    else
      assert blocks = MAX_BLOCKS report "Too few input blocks" severity failure;
      report "SMOKE TEST ONLY: " & integer'image(blocks) & " blocks passed";
    end if;
    report "Cycles per block, min/max: " & integer'image(min_cycles) & "/" & integer'image(max_cycles);
    report "Total input-to-output latency cycles (sum): " & integer'image(total_cycles);
    report "Batch cycles including input handshakes: " & integer'image((now - batch_start) / CLOCK_PERIOD);
    report "Batch simulated time: " & time'image(now - batch_start);
    finish;
    wait;
  end process;
end architecture;
