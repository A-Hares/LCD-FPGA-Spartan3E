library ieee;
use ieee.std_logic_1164.all;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity lcd is 
    generic (width : integer := 95);
    port (
        rst, clk : in std_logic;
        LCD_E : out std_logic;  -- Read/Write enable pulse 
        LCD_RS: out std_logic;  -- Register select 0 to select registers and 1 to select data
        LCD_RW : out std_logic; -- 0 Write LCD accepts data
        SF_CE0 : out std_logic; -- StrataFlash chip enable 1 to read from lcd
        DONE    : out std_logic;
        SF : out std_logic_vector(3 downto 0));
end lcd;

architecture behavioral of lcd is

    type PowerOn_state is (P0, P1, P2, P3, P4, P5, P6, P7, P8); 
    signal state_power, next_state_power : PowerOn_state;

    type Display_state is (D0, D1, D2, D3, D4,D5); 
    signal state_display, next_state_display : Display_state;

    type Byte_send_state is (B0, B1, B2, B3, B4, B5);       -- SF data & wait 40 ns -> enable high for 12 cycles 
                                                            -- -> enable low for 48 cycles -> SF data & wait 40 ns 
                                                            -- -> enable high for 12 cycles -> enable low for 40 us
    signal state_byte, next_state_byte : Byte_send_state;

    signal Display_enable, DN   : std_logic;
    signal Display_final,Display_final2    : std_logic;
    signal Byte_sent        : std_logic;
    signal Trigger          : std_logic;
    signal LCD_E_B, LCD_E_P : std_logic;
    signal LCD_RS_P, LCD_RS_D : std_logic;
    signal SF_lower, SF_P, SF_B     : std_logic_vector(3 downto 0);
    signal SF_upper,SF_upper_send,SF_lower_send,SF_lower_D,SF_upper_D                : std_logic_vector(3 downto 0);
    signal cnt_value, cnt_value_P, cnt_value_D, cnt_value_B  : std_logic_vector(19 downto 0);
    signal count            : std_logic_vector(19 downto 0);
    signal Data_to_send : std_logic_vector(width downto 0);
begin

    SF_CE0 <= '1';
    LCD_RW <= '0';
    LCD_E   <=      LCD_E_P when Display_enable = '0' else
                    --'0'     when Display_final = '1' else
                    LCD_E_B;
    LCD_RS  <=      LCD_RS_P when Display_enable = '0' else
                    '1' when Display_final2 = '1' else
                    LCD_RS_D;
    SF      <=      SF_P when Display_enable = '0' else
                    SF_B; 
    cnt_value   <=  cnt_value_P when Display_enable = '0' else
                    cnt_value_D when Display_final = '1' else
                    cnt_value_B; 
    
    SF_lower    <= SF_lower_send when Display_final2 = '1' else
                    SF_lower_D;

    SF_upper    <= SF_upper_send when Display_final2 = '1' else
                    SF_upper_D;
                    
    DONE <= DN;
    SYNC_PROC: process (Trigger,rst,next_state_power,next_state_display)
    begin
        if rst = '1' then
            state_power <= P0;
            state_display <= D0;
            state_byte <= B0;
        elsif rising_edge(Trigger) then
            if (Display_enable = '0') then
                state_power <= next_state_power;
            else
                if (Display_final2 = '1') then 
                    state_byte <= next_state_byte;
                elsif (Byte_sent = '1')  then
                    state_display <= next_state_display;
                    state_byte <= next_state_byte;
                else
                    state_byte <= next_state_byte;
                end if;
            end if;
        end if;        
    end process;

    Send_char: process (rst,Display_final2,Data_to_send,Byte_sent)
        variable cnt : integer range 0 to width;
    begin
        if rst = '1' then
            Data_to_send <= X"41484D454420484152455300";        -- insert data you want to send here in hex and add 00 to the LSB
            cnt := width;
            DN <= '0';
        elsif Display_final2 = '1' then
            if rising_edge(Byte_sent) then
                SF_upper_send <= Data_to_send(cnt downto (cnt-3));
                SF_lower_send <= Data_to_send((cnt-4) downto (cnt-7));
                if cnt = 7 then
                    DN <= '1';
                else
                    cnt := cnt - 8;
                end if;
            end if;
        else
            SF_upper_send <= "0000";
            SF_lower_send <= "0000"; 
        end if;        
    end process Send_char;

    PowerOn_next_state: process (state_power)
    begin
        next_state_power <= state_power;
        LCD_RS_P <= '0';      -- register write
        LCD_E_P <= '0';       -- RW not enabled
        SF_P <= "0000";
        cnt_value_P <= X"10000";
        Display_enable <= '0';
        case (state_power) is
            when P0 =>
                    next_state_power <= P1;
                    cnt_value_P <= X"5B8D8";
            when P1 =>
                    next_state_power <= P2;
                    cnt_value_P <= X"00006";
                    LCD_E_P <= '1';       -- RW enabled
                    SF_P <= "0011";
            when P2 =>
                    next_state_power <= P3;
                    cnt_value_P <= X"19064";
            when P3 =>
                    next_state_power <= P4;
                    cnt_value_P <= X"00006";
                    LCD_E_P <= '1';       -- RW enabled
                    SF_P <= "0011";
            when P4 =>
                    next_state_power <= P5;
                    cnt_value_P <= X"009C4";
            when P5 =>
                    next_state_power <= P6;
                    cnt_value_P <= X"00006";
                    LCD_E_P <= '1';       -- RW enabled
                    SF_P <= "0011";
            when P6 =>
                    next_state_power <= P7;
                    cnt_value_P <= X"003E8";
            when P7 =>
                    next_state_power <= P8;
                    cnt_value_P <= X"00006";
                    LCD_E_P <= '1';       -- RW enabled
                    SF_P <= "0010";
            when P8 =>
                    cnt_value_P <= X"003E8";
                    Display_enable <= '1';
            when others =>
                next_state_power <= P0;
       end case;      
    end process PowerOn_next_state;

    Display_next_state: process (state_display)
    begin
        next_state_display <= state_display;
        LCD_RS_D <= '0';
        Display_final <= '0';
        Display_final2 <= '0';
        SF_upper_D <= "0000";
        SF_lower_D <= "0000";
        cnt_value_D <= X"10000";
        case (state_display) is
            when D0 =>
                    next_state_display <= D1;
                    SF_upper_D <= "0010";
                    SF_lower_D <= "1000";
            when D1 =>
                    next_state_display <= D2;
                    SF_upper_D <= "0000";
                    SF_lower_D <= "0110";
            when D2 =>
                    next_state_display <= D3;
                    SF_upper_D <= "0000";
                    SF_lower_D <= "1111";
            when D3 =>
                    next_state_display <= D4;
                    SF_upper_D <= "0000";
                    SF_lower_D <= "0001";
            when D4 =>
                    Display_final <= '1';
                    cnt_value_D <= X"0A028";
                    next_state_display <= D5;
            when D5 =>
                    Display_final2 <= '1';
                    Display_final <= '0';
            when others =>
                next_state_display <= D0;
       end case;      
    end process Display_next_state;

    Byte_next_state: process (state_byte,SF_upper,SF_lower,DN)
    begin
        next_state_byte <= state_byte;
        LCD_E_B <= '0';
        cnt_value_B <= X"10000";
        Byte_sent <= '0';
        SF_B <= "0000";
        case (state_byte) is
            when B0 =>
                if (DN = '0') then
                    next_state_byte <= B1;
                end if;
                cnt_value_B <= X"00001";
                SF_B <= SF_upper;
            when B1 =>
                next_state_byte <= B2;
                cnt_value_B <= X"00006";
                LCD_E_B <= '1';
                SF_B <= SF_upper;
            when B2 =>
                next_state_byte <= B3;
                cnt_value_B <= X"00018";
                SF_B <= SF_upper;
            when B3 =>
                next_state_byte <= B4;
                cnt_value_B <= X"00001";
                SF_B <= SF_lower;
            when B4 =>
                next_state_byte <= B5;
                cnt_value_B <= X"00006";
                LCD_E_B <= '1';
                SF_B <= SF_lower;
            when B5 =>
                next_state_byte <= B0;
                Byte_sent <= '1';
                cnt_value_B <= X"003E8";
                SF_B <= SF_lower;
            when others =>
                next_state_byte <= B0;
       end case;      
    end process Byte_next_state;

    TriggerGeneration: process(clk,rst)
    begin
        if rst = '1' then
            Trigger <= '0';
            count <= X"00000";
        elsif rising_edge(clk) then
            count <= count + 1;
            if (count=cnt_value) then
                Trigger <= not Trigger;
                count <= X"00000";
            end if;
        end if;
    end process TriggerGeneration;

end behavioral;
