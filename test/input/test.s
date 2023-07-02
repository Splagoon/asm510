    .set START, 0x0DC0

    # Subroutine: WAIT
    .set WAIT, 0x01
    .org WAIT
    .word 0x80
    .org 0x900
    LAX 0
WAIT_LOOP:
    # Skip to near end of page
    .org 0x908
    ADX 1
    T WAIT_LOOP
    RTN0

    # Subroutine: LCDS_ON
    .set LCDS_ON, 0x00
    .org LCDS_ON
    .word 0x00
    .org 0x100
LCDS_ON_LOOP:
    SM 0
    TM WAIT
    SM 1
    TM WAIT
    SM 2
    TM WAIT
    SM 3
    TM WAIT
    INCB
    T LCDS_ON_LOOP
    RTN0

    # Subroutine: LCDS_OFF
    .set LCDS_OFF, 0x02
    .org LCDS_OFF
    .word 0x40
    .org 0x500
LCDS_OFF_LOOP:
    RM 0
    TM WAIT
    RM 1
    TM WAIT
    RM 2
    TM WAIT
    RM 3
    TM WAIT
    INCB
    T LCDS_OFF_LOOP
    RTN0

    # Entrypoint
    .org START
MAIN_LOOP:
    # Go to first LCD
    LBL 0x60
    TM LCDS_ON
    LBL 0x70
    TM LCDS_ON
    LBL 0x60
    TM LCDS_OFF
    LBL 0x70
    TM LCDS_OFF
    T MAIN_LOOP
