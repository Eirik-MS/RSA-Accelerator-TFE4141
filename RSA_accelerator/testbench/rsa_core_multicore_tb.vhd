-- Ordered 256-bit message interface integration test (not an AXI/DMA model).
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;
use std.env.all;

entity rsa_core_multicore_tb is
    generic (
        CORE_COUNT : positive := 2;
        COURSE_BLOCKS : natural := 0; -- 0 = quick functional tests only
        INPUT_FILE : string := "ct4_in.hex";
        EXPECTED_FILE : string := "pt4_expected.hex"
    );
end entity;

architecture sim of rsa_core_multicore_tb is
    constant PERIOD : time := 10 ns;
    constant COURSE_N : std_logic_vector(255 downto 0) :=
        x"99925173ad65686715385ea800cd28120288fc70a9bc98dd4c90d676f8ff768d";
    constant COURSE_D : std_logic_vector(255 downto 0) :=
        x"0cea1651ef44be1f1f1476b7539bed10d73e3aac782bd9999a1e5a790932bfe9";
    signal clk : std_logic := '0';
    signal reset_n, input_valid, input_ready, input_last : std_logic := '0';
    signal output_valid, output_ready, output_last : std_logic := '0';
    signal input_data, key, modulus : std_logic_vector(255 downto 0) := (others => '0');
    signal output_data : std_logic_vector(255 downto 0);
    signal status : std_logic_vector(31 downto 0);

    function v(value : natural) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(value, 256));
    end function;

    function exponent_for(index : natural) return natural is
    begin
        case index mod 6 is
            when 0 => return 31; -- Slow head followed by an almost immediate result
            when 1 => return 0;
            when 2 => return 3;
            when 3 => return 7;
            when 4 => return 1;
            when others => return 5;
        end case;
    end function;

    function modulus_for(index : natural) return positive is
    begin
        case index mod 3 is
            when 0 => return 33;
            when 1 => return 97;
            when others => return 257;
        end case;
    end function;

    function expected_for(index : natural) return std_logic_vector is
        variable value : natural := 1;
        constant n : positive := modulus_for(index);
        constant message : natural := (index*7 mod 29) + 2;
    begin
        for i in 1 to exponent_for(index) loop
            value := (value * message) mod n;
        end loop;
        return v(value);
    end function;

    function last_for(index, count : natural) return std_logic is
    begin
        -- Adjacent packets, single-block packets, odd packet sizes, final block.
        if index mod 5 = 0 or index mod 5 = 3 or index = count-1 then return '1'; end if;
        return '0';
    end function;
begin
    clk <= not clk after PERIOD/2;
    dut : entity work.rsa_core
        generic map (C_BLOCK_SIZE => 256, C_CORE_COUNT => CORE_COUNT)
        port map (
            clk => clk, reset_n => reset_n,
            msgin_valid => input_valid, msgin_ready => input_ready,
            msgin_data => input_data, msgin_last => input_last,
            msgout_valid => output_valid, msgout_ready => output_ready,
            msgout_data => output_data, msgout_last => output_last,
            key_e_d => key, key_n => modulus, rsa_status => status
        );

    stimulus : process
        type blocks_t is array (0 to 881) of std_logic_vector(255 downto 0);
        variable course_inputs, course_expected : blocks_t;
        file inputs, expected_values : text;
        variable row : line;
        variable good : boolean;

        procedure reset_core is
        begin
            wait until falling_edge(clk);
            reset_n <= '0';
            input_valid <= '0';
            output_ready <= '0';
            for i in 1 to 4 loop
                wait until rising_edge(clk);
                assert input_ready = '0' and output_valid = '0'
                    report "Interface active during reset" severity failure;
            end loop;
            wait until falling_edge(clk);
            reset_n <= '1';
        end procedure;

        procedure run_batch(count : positive; stalled, course : boolean; uniform : boolean := false) is
            variable sent, received, ticks, last_progress, max_inflight : natural := 0;
            variable held : boolean := false;
            variable held_data : std_logic_vector(255 downto 0);
            variable held_last : std_logic;
            variable expected_data : std_logic_vector(255 downto 0);
        begin
            while received < count loop
                wait until falling_edge(clk);
                -- sent changes only on acceptance, so input data stays stable
                -- until its handshake, even during gaps in ready.
                if sent < count then
                    input_valid <= '1';
                    if course then
                        if sent = count-1 then input_last <= '1'; else input_last <= '0'; end if;
                    else
                        input_last <= last_for(sent, count);
                    end if;
                    if course then
                        input_data <= course_inputs(sent);
                        key <= COURSE_D;
                        modulus <= COURSE_N;
                    elsif uniform then
                        input_data <= v((sent*7 mod 29)+2);
                        key <= v(3);
                        modulus <= v(33);
                    else
                        input_data <= v((sent*7 mod 29)+2);
                        key <= v(exponent_for(sent));
                        modulus <= v(modulus_for(sent));
                    end if;
                else
                    input_valid <= '0';
                    input_data <= (others => 'X');
                    key <= (others => 'X');
                    modulus <= (others => 'X');
                end if;
                -- Initially fill the cores and block retirement, then alternate
                -- long stalls and short stalls to exercise held output packets.
                if stalled and (ticks < 3000 or ticks mod 47 < 13) then
                    output_ready <= '0';
                else
                    output_ready <= '1';
                end if;
                wait until rising_edge(clk);
                ticks := ticks + 1;
                if held then
                    assert output_valid = '1' and output_data = held_data and output_last = held_last
                        report "Output changed while stalled" severity failure;
                end if;
                held := output_valid = '1' and output_ready = '0';
                held_data := output_data;
                held_last := output_last;
                if input_valid = '1' and input_ready = '1' then
                    sent := sent + 1;
                    last_progress := ticks;
                end if;
                if output_valid = '1' and output_ready = '1' then
                    assert received < sent report "Unexpected or duplicate result" severity failure;
                    if course then expected_data := course_expected(received);
                    elsif uniform then expected_data := v((((received*7 mod 29)+2)**3) mod 33);
                    else expected_data := expected_for(received); end if;
                    assert output_data = expected_data
                        report "Wrong/out-of-order result at block " & integer'image(received) &
                            ": expected " & to_hstring(expected_data) & ", got " & to_hstring(output_data)
                        severity failure;
                    if course then
                        if received = count-1 then
                            assert output_last = '1' report "Missing final course packet flag" severity failure;
                        else
                            assert output_last = '0' report "Early course packet flag" severity failure;
                        end if;
                    else
                        assert output_last = last_for(received, count)
                            report "Wrong packet-end flag at block " & integer'image(received) severity failure;
                    end if;
                    received := received + 1;
                    last_progress := ticks;
                    if course and received mod 100 = 0 then
                        report "Course blocks checked: " & integer'image(received);
                    end if;
                end if;
                if sent-received > max_inflight then max_inflight := sent-received; end if;
                assert sent-received <= CORE_COUNT report "Too many outstanding inputs" severity failure;
                assert ticks-last_progress < 300000 report "Batch handshake timeout" severity failure;
            end loop;
            if count >= CORE_COUNT then
                assert max_inflight = CORE_COUNT report "Failed to fill all cores" severity failure;
            end if;
            report "PASS cores=" & integer'image(CORE_COUNT) & " blocks=" & integer'image(count) &
                " cycles=" & integer'image(ticks) & " time=" & time'image(ticks*PERIOD);
            wait until falling_edge(clk);
            input_valid <= '0';
            output_ready <= '1';
            for i in 1 to 10 loop
                wait until rising_edge(clk);
                assert output_valid = '0' report "Duplicate result after batch" severity failure;
            end loop;
        end procedure;

        variable wait_cycles : natural;
    begin
        assert COURSE_BLOCKS <= 882 report "COURSE_BLOCKS must be 0..882" severity failure;
        if COURSE_BLOCKS > 0 then
            file_open(inputs, INPUT_FILE, read_mode);
            file_open(expected_values, EXPECTED_FILE, read_mode);
            for i in 0 to COURSE_BLOCKS-1 loop
                assert not endfile(inputs) and not endfile(expected_values)
                    report "Missing course vector" severity failure;
                readline(inputs, row); hread(row, course_inputs(i), good);
                assert good report "Invalid input hex" severity failure;
                readline(expected_values, row); hread(row, course_expected(i), good);
                assert good report "Invalid expected hex" severity failure;
            end loop;
            if COURSE_BLOCKS = 882 then
                assert endfile(inputs) and endfile(expected_values)
                    report "Unexpected extra course vectors" severity failure;
            end if;
            file_close(inputs); file_close(expected_values);
        end if;

        reset_core;
        -- Start work on every core, then reset before completion. The next
        -- batches must not receive any result or packet flag from this work.
        for i in 0 to CORE_COUNT-1 loop
            wait until falling_edge(clk);
            input_valid <= '1'; input_data <= v(4); input_last <= '1';
            key <= v(31); modulus <= v(33);
            wait_cycles := 0;
            loop
                wait until rising_edge(clk);
                exit when input_ready = '1';
                wait_cycles := wait_cycles + 1;
                assert wait_cycles < 300000 report "Reset test input timeout" severity failure;
            end loop;
        end loop;
        reset_core;
        run_batch(32, true, false);
        run_batch(17, false, false); -- Non-multiple of the core count; no reset between batches
        report "Fixed-key throughput batch (short exponent, not the course private key)";
        run_batch(32, false, false, true);
        if COURSE_BLOCKS > 0 then
            report "Course private-key batch";
            run_batch(COURSE_BLOCKS, false, true);
            if COURSE_BLOCKS = 882 then report "FULL COURSE CASE 4 PASSED";
            else report "COURSE SUBSET ONLY PASSED"; end if;
        end if;
        report "MULTICORE INTEGRATION TESTS PASSED";
        finish;
        wait;
    end process;
end architecture;
