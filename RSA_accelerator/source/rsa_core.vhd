--------------------------------------------------------------------------------
-- Author       : Oystein Gjermundnes
-- Organization : Norwegian University of Science and Technology (NTNU)
--                Department of Electronic Systems
--                https://www.ntnu.edu/ies
-- Course       : TFE4141 Design of digital systems 1 (DDS1)
-- Year         : 2018-2019
-- Project      : RSA accelerator
-- License      : This is free and unencumbered software released into the
--                public domain (UNLICENSE)
--------------------------------------------------------------------------------
-- Purpose:
--   Parallel RSA exponentiation cores with ordered input/output.
--   Computes C = M**key_e mod key_n, preserving packet boundaries.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity rsa_core is
	generic (
		-- Users to add parameters here
		C_BLOCK_SIZE          : integer := 256;
		C_CORE_COUNT          : positive := 8
	);
	port (
		-----------------------------------------------------------------------------
		-- Clocks and reset
		-----------------------------------------------------------------------------
		clk                    :  in std_logic;
		reset_n                :  in std_logic;

		-----------------------------------------------------------------------------
		-- Slave msgin interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgin_valid             : in std_logic;
		-- Slave ready to accept a new message
		msgin_ready             : out std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgin_data              :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgin_last              :  in std_logic;

		-----------------------------------------------------------------------------
		-- Master msgout interface
		-----------------------------------------------------------------------------
		-- Message that will be sent out is valid
		msgout_valid            : out std_logic;
		-- Slave ready to accept a new message
		msgout_ready            :  in std_logic;
		-- Message that will be sent out of the rsa_msgin module
		msgout_data             : out std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		-- Indicates boundary of last packet
		msgout_last             : out std_logic;

		-----------------------------------------------------------------------------
		-- Interface to the register block
		-----------------------------------------------------------------------------
		key_e_d                 :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		key_n                   :  in std_logic_vector(C_BLOCK_SIZE-1 downto 0);
		rsa_status              : out std_logic_vector(31 downto 0)

	);
end rsa_core;

architecture rtl of rsa_core is
    type block_array is array (natural range <>) of std_logic_vector(C_BLOCK_SIZE-1 downto 0);
    signal results : block_array(0 to C_CORE_COUNT-1);
    signal input_valid, input_ready, output_valid, output_ready : std_logic_vector(0 to C_CORE_COUNT-1);
    signal last_flags : std_logic_vector(0 to C_CORE_COUNT-1);
    signal dispatch_index, retire_index : natural range 0 to C_CORE_COUNT-1 := 0;

    function advance(index : natural) return natural is
    begin
        if index = C_CORE_COUNT-1 then return 0; end if;
        return index + 1;
    end function;
begin
    -- Strict round robin at BOTH ends preserves order even if a later core
    -- finishes first. Each exponentiation unit holds its result until accepted,
    -- so its DONE state also serves as a one-entry output buffer.
    msgin_ready <= input_ready(dispatch_index) when reset_n = '1' else '0';
    msgout_valid <= output_valid(retire_index) when reset_n = '1' else '0';
    msgout_data <= results(retire_index);
    msgout_last <= last_flags(retire_index);
    rsa_status <= (others => '0');

    cores : for i in 0 to C_CORE_COUNT-1 generate
        input_valid(i) <= msgin_valid when dispatch_index = i and reset_n = '1' else '0';
        output_ready(i) <= msgout_ready when retire_index = i and reset_n = '1' else '0';
        exponentiator : entity work.exponentiation
            generic map (C_block_size => C_BLOCK_SIZE)
            port map (
                clk => clk, reset_n => reset_n,
                message => msgin_data, key => key_e_d, modulus => key_n,
                valid_in => input_valid(i), ready_in => input_ready(i),
                valid_out => output_valid(i), ready_out => output_ready(i),
                result => results(i)
            );
    end generate;

    schedule : process(clk, reset_n)
    begin
        if reset_n = '0' then
            dispatch_index <= 0;
            retire_index <= 0;
            last_flags <= (others => '0');
        elsif rising_edge(clk) then
            if msgin_valid = '1' and input_ready(dispatch_index) = '1' then
                last_flags(dispatch_index) <= msgin_last;
                dispatch_index <= advance(dispatch_index);
            end if;
            if msgout_ready = '1' and output_valid(retire_index) = '1' then
                retire_index <= advance(retire_index);
            end if;
        end if;
    end process;
end rtl;
