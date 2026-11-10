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
--   RSA encryption core template. This core currently computes
--   C = M xor key_n
--
--   Replace/change this module so that it implements the function
--   C = M**key_e mod key_n.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
entity rsa_core is
	generic (
		-- Users to add parameters here
		C_BLOCK_SIZE          : integer := 256;
		-- Number of parallel exponentiation cores
		C_NUM_CORES           : integer := 14
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
	type data_array_t is array (0 to C_NUM_CORES-1) of std_logic_vector(C_BLOCK_SIZE-1 downto 0);

	-- Round-robin pointers: next core to receive a message / deliver a result
	signal in_idx  : integer range 0 to C_NUM_CORES-1;
	signal out_idx : integer range 0 to C_NUM_CORES-1;

	signal core_valid_in  : std_logic_vector(C_NUM_CORES-1 downto 0);
	signal core_ready_in  : std_logic_vector(C_NUM_CORES-1 downto 0);
	signal core_valid_out : std_logic_vector(C_NUM_CORES-1 downto 0);
	signal core_ready_out : std_logic_vector(C_NUM_CORES-1 downto 0);
	signal core_result    : data_array_t;

	-- msgin_last flag belonging to the message each core is working on
	signal last_r         : std_logic_vector(C_NUM_CORES-1 downto 0);

begin
	-- All cores use the same key, so they all take the same number of cycles.
	-- Dispatching and collecting in the same round-robin order therefore keeps
	-- the messages in order without costing throughput.
	gen_cores : for i in 0 to C_NUM_CORES-1 generate
		-- Only the selected core may see valid/ready, otherwise every idle core
		-- would start on the same message.
		core_valid_in(i)  <= msgin_valid  when in_idx  = i else '0';
		core_ready_out(i) <= msgout_ready when out_idx = i else '0';

		i_exponentiation : entity work.exponentiation
			generic map (
				C_block_size => C_BLOCK_SIZE
			)
			port map (
				message   => msgin_data       ,
				key       => key_e_d          ,
				valid_in  => core_valid_in(i) ,
				ready_in  => core_ready_in(i) ,
				ready_out => core_ready_out(i),
				valid_out => core_valid_out(i),
				result    => core_result(i)   ,
				modulus   => key_n            ,
				clk       => clk              ,
				reset_n   => reset_n
			);
	end generate;

	msgin_ready  <= core_ready_in(in_idx);
	msgout_valid <= core_valid_out(out_idx);
	msgout_data  <= core_result(out_idx);
	msgout_last  <= last_r(out_idx);

	rr_proc : process(clk, reset_n)
	begin
		if reset_n = '0' then
			in_idx  <= 0;
			out_idx <= 0;
			last_r  <= (others => '0');
		elsif rising_edge(clk) then
			-- Message accepted by core in_idx
			if msgin_valid = '1' and core_ready_in(in_idx) = '1' then
				last_r(in_idx) <= msgin_last;
				if in_idx = C_NUM_CORES-1 then
					in_idx <= 0;
				else
					in_idx <= in_idx + 1;
				end if;
			end if;

			-- Result delivered by core out_idx
			if core_valid_out(out_idx) = '1' and msgout_ready = '1' then
				if out_idx = C_NUM_CORES-1 then
					out_idx <= 0;
				else
					out_idx <= out_idx + 1;
				end if;
			end if;
		end if;
	end process;

	-- Low bits: which cores are idle (debug aid)
	rsa_status <= std_logic_vector(resize(unsigned(core_ready_in), 32));
end rtl;
