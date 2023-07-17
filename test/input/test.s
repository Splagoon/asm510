    .set START, 0x0DC0
    .set LCD_RAM_START, 0x60
    .set RAM_PAGE_SIZE, 0x10
    .set SUBROUTINE_PAGE, 0x100

    # Subroutine: WAIT
    .set WAIT, 0x01
    .set WAIT_OFFSET, 0x80
    .org WAIT
    .word WAIT_OFFSET
    .set WAIT_PAGE_START, SUBROUTINE_PAGE + (WAIT_OFFSET * 0x10)
    .org WAIT_PAGE_START
    LAX 0
WAIT_LOOP:
    # Skip to near end of page
    .org WAIT_PAGE_START + 8
    ADX 1
    T WAIT_LOOP
    RTN0

    # Subroutine: LCDS_ON
    .set LCDS_ON, 0x00
    .set LCDS_ON_OFFSET, 0x00
    .org LCDS_ON
    .word LCDS_ON_OFFSET
    .org SUBROUTINE_PAGE + (LCDS_ON_OFFSET * 0x10)
LCDS_ON_LOOP:
    .irp bit, 0, 1, 2, 3
    SM \bit
    TM WAIT
    .endr
    INCB
    T LCDS_ON_LOOP
    RTN0

    # Subroutine: LCDS_OFF
    .set LCDS_OFF, 0x02
    .set LCDS_OFF_OFFSET, 0x40
    .org LCDS_OFF
    .word LCDS_OFF_OFFSET
    .org SUBROUTINE_PAGE + (LCDS_OFF_OFFSET * 0x10)
LCDS_OFF_LOOP:
    .irp bit, 0, 1, 2, 3
    RM \bit
    TM WAIT
    .endr
    INCB
    T LCDS_OFF_LOOP
    RTN0

    # Entrypoint
    .org START
MAIN_LOOP:
    .irp lcd_sub, LCDS_ON, LCDS_OFF
    .irp ram_offset, LCD_RAM_START, LCD_RAM_START + RAM_PAGE_SIZE
    LBL \ram_offset
    TM \lcd_sub
    .endr
    .endr
    T MAIN_LOOP
