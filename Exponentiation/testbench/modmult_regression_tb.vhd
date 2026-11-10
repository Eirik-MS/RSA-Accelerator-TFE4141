library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity modmult_regression_tb is
    generic (VECTOR_FILE : string := "modmult_vectors.txt");
end entity;

architecture sim of modmult_regression_tb is
    signal clk : std_logic := '0';
    signal reset_n, start, done : std_logic := '0';
    signal a, b, n : std_logic_vector(255 downto 0) := (others => '0');
    signal result : std_logic_vector(255 downto 0);
begin
    clk <= not clk after 5 ns;
    dut : entity work.modular_multiplication
        port map (clk => clk, reset_n => reset_n, start => start,
                  a => a, b => b, n => n, result => result, done => done);
    stimulus : process
        file vectors : text open read_mode is VECTOR_FILE;
        variable row : line;
        variable av, bv, nv, expected : std_logic_vector(255 downto 0);
        variable good : boolean;
        variable count, cycles : natural := 0;
    begin
        wait for 25 ns;
        wait until falling_edge(clk);
        reset_n <= '1';
        while not endfile(vectors) loop
            readline(vectors, row);
            hread(row, av, good); assert good severity failure;
            hread(row, bv, good); assert good severity failure;
            hread(row, nv, good); assert good severity failure;
            hread(row, expected, good); assert good severity failure;
            wait until falling_edge(clk);
            a <= av; b <= bv; n <= nv; start <= '1';
            wait until rising_edge(clk);
            start <= '0';
            a <= (others => 'X'); b <= (others => 'X'); n <= (others => 'X');
            cycles := 0;
            loop
                wait until rising_edge(clk);
                cycles := cycles + 1;
                exit when done = '1';
                assert cycles < 300 report "Multiplier timeout" severity failure;
            end loop;
            assert cycles = 257 report "Multiplier latency changed" severity failure;
            assert result = expected
                report "Mismatch at vector " & integer'image(count) & ": got " & to_hstring(result) &
                    ", expected " & to_hstring(expected) severity failure;
            count := count + 1;
            wait until rising_edge(clk);
        end loop;
        assert count > 0 report "Empty multiplier regression" severity failure;
        report "MULTIPLIER REGRESSION PASSED: " & integer'image(count) & " vectors, 257 cycles each";
        finish;
        wait;
    end process;
end architecture;
