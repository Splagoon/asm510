    .set START, 0x0DC0
    .set LCD_RAM_START, 0x60
    .set RAM_PAGE_SIZE, 0x10
    .set SUBROUTINE_PAGE, 0x100
    .set NEXT_SUBROUTINE, 0
    .set MAX_SUBROUTINES, 3
    .set ON, 1
    .set OFF, 0

    .macro def_subroutine subroutine
    .if NEXT_SUBROUTINE > MAX_SUBROUTINES
    .err
    .endif

    .set 'subroutine, NEXT_SUBROUTINE
    .set NEXT_SUBROUTINE, NEXT_SUBROUTINE + 1

    .org \subroutine
    .word \subroutine * 0x40

    .org SUBROUTINE_PAGE + (\subroutine * 0x400)
    .endm

    .macro toggle_lcd toggle
LCDS_'toggle _LOOP:
    .irp bit, 0, 1, 2, 3
    .if \toggle
    SM \bit
    .else
    RM \bit
    .endif
    TM WAIT
    .endr
    INCB
    T LCDS_'toggle _LOOP
    .endm

    # Subroutine: WAIT
    def_subroutine WAIT
    LAX 0
WAIT_LOOP:
    # Skip to near end of page
    .skip 47
    ADX 1
    T WAIT_LOOP
    RTN0

    # Subroutine: LCDS_ON
    def_subroutine LCDS_ON
    toggle_lcd ON
    RTN0

    # Subroutine: LCDS_OFF
    def_subroutine LCDS_OFF
    toggle_lcd OFF
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
