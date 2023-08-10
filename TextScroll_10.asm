* Scroll function for BASIC programs
* V 1.00 by Glen Hewlett

* Sample BASIC program:
*
* 10 '4K COCO USE L=&HC96
* 20 '16K COCO USE L=&H3C96
* 30 '32K COCO USE L=&H7C96
* 40 L=&H7C96
* 50 POKE &H1DA,L/256:POKE&H1DB,L AND 255
* 60 CLEAR 255,L
* 70 L=PEEK(&H1DA)*256+PEEK(&H1DB)
* 80 LOADM"TXTSCRLL",L
* 90 DEFUSR0=L+&H10
* 100 '0 = DOWN, 1 = RIGHT, 2 = LEFT, 3 = UP
* 110 POKE&H1DA,0' DIRECTION
* 120 POKE&H1DB,0' X POSITION
* 130 POKE&H1DC,0' Y POSITION
* 140 POKE&H1DD,32' WIDTH
* 150 POKE&H1DE,16' HEIGHT
* 160 E=USR0(L)'SETUP SCROLL
* 170 IF E=0 THEN GOTO 250
* 180 CLS
* 190 PRINT"ERROR SETTING UP SCROLL WINDOW"
* 200 IF E AND 1 THEN PRINT"USED NEGATIVE NUMBERS"
* 210 IF E AND 2 THEN PRINT"WIDTH + STARTING X IS TOO WIDE"
* 220 IF E AND 4 THEN PRINT"HEIGHT + STARTING Y IS TOO HIGH"
* 230 IF E AND 8 THEN PRINT"DIRECTION MUST BE 0 TO 3 MAX"
* 240 END
* 245 'KIND OF LIKE THE MATRIX :)
* 250 R=RND(32):POKE&H3FF+R,RND(64)-1
* 260 EXEC L 'DO THE SCROLL
* 270 GOTO 250
* 
* ROM Calls for BASIC ROM version 1.2 & CoCo 3
INTCNV          EQU     $B3ED           * Convert FPA0 to a signed 2-byte integer; return the value in ACCD.
GIVABF          EQU     $B4F4           * Convert the value in ACCD into a floating point number in FPA0.
UnPackXToFPA0   EQU     $BC14           * COPY A PACKED FP NUMBER FROM (X) TO FPA0
PackFPA0AtX     EQU     $BC35           * PACK FPA0 AND SAVE IT IN ADDRESS POINTED TO BY X

* User variables
Direction       EQU     $01DA           * 0 = Down, 1 = Right, 2 = Left, 3 = Up Same as Print@ (range of 0 to 511)
StartX          EQU     Direction+1     * X starting location
StartY          EQU     StartX+1        * Y starting location
Width           EQU     StartY+1        * Width of scroll window (Max 32)
Height          EQU     Width+1         * Height of scroll window (Max 16)

* Program variable space
StackPointer    EQU     Height+1        * Backup S stack before stack blasting

        ORG     $0000           * Start of program (let the user decide where to load it with LOADM"TXTSCRLL",&H7000)
CoCo_START:
***********************************************************
* BASIC's scroll command CPU cycles: 3 + (21 * 240) + 21 + (6 + (13 * 32) + 5) = 5,491 total cycles 

DoScroll:
        PSHS    CC,D,DP,X,Y,U   * Save the registers
        ORCC    #$50            * Disable interrupts
PrepB:
        LDB     #$FF            * Self Mod value for B (Height)
PrepX:
        LDX     #$FFFF          * Self mod value for X (starting location)
PrepY:
        LDY     #$FFFF          * Self mod value for Y (2nd Jmp location)
PrepScrollJump:
        JMP     $FFFF           * Self mod to jump to the preset scroll code
SetupScroll:
        PSHS    CC,D,DP,X,Y,U   * Save the registers
        ORCC    #$50            * Disable interrupts
* Error codes:
NegValue        EQU     1       * (set bit 0) one of the setup values is a negative
TooWide         EQU     2       * (set bit 1) Settings are too wide goes past 0 to 31 columns
TooTall         EQU     4       * (set bit 2) Settings are too high, goes past 0 to 15 rows
DirectError     EQU     8       * (set bit 3) Direction value is not between 0 and 3
* Test values are safe
        CLRB
        LDA     StartX          * Get the x start location
        ORA     Width           * OR with Width
        ORA     StartY          * OR the y start location
        ORA     Height          * OR the height
        BPL     >               * If all are positive then good so far
        ORB     #NegValue       * ERROR: at least one setting is a negative value
!       LDA     StartX          * Get the x start location
        ADDA    Width           * Add the width
        BCC     >
        ORB     #TooWide        * ERROR: If we've gone over 255 then too big, return with ERROR
!       CMPA    #32             * 1 to 32 is the text screen width
        BLS     >               * if lower or the same as 31 then good
        ORB     #TooWide        * ERROR: too wide
!       LDA     StartY          * Get the y start location
        ADDA    Height          * Add the height
        BCC     >
        ORB     #TooTall        * ERROR: If we've gone over 255 then too big, return with ERROR
!       CMPA    #16             * 1 to 16 is the text screen height
        BLS     >               * If less or the same then good skip ahead
        ORB     #TooTall        * ERROR: If we've gone over 255 then too big, return with ERROR
!       LDA     Direction       * Get the direction the user wants to scroll, 0 = Down, 1 = Right, 2 = Left, 3 = Up
        CMPA    #4              * Is it lower then 4?
        BLO     >               * Skip ahead if so, good direction #
        ORB     #DirectError    * Value of the direction is not between 0 and 3
!       TSTB                    * Did we find any errors?
        BEQ     >               * If no erros skip ahead
SendErrorOut:        
        CLRA                    * D now has the Error code
        JSR     GIVABF          * Convert the value in ACCD into a floating point number in FPA0.
        PULS    CC,D,DP,X,Y,U,PC  * Restore & Return to BASIC
!       LDA     #32
        LDB     StartY
        MUL
        TFR     D,X
        LDB     StartX
        ABX                     * X = The users starting location
        LDA     Direction       * Get the direction the user wants to scroll, 0 = Down, 1 = Right, 2 = Left, 3 = Up
        BEQ     ScrollDown 
        DECA
        LBEQ    ScrollRight
        DECA
        LBEQ    ScrollLeft
* If we get here then we Scroll Up
* Enter with X = users screen starting location
SetupUp:
        LEAX    $400+32,X       * Now points to the top left corner of the users requested window
        LDB     Width           * B is the width
        LBSR    SetJumps        * Setup the jumps to blast a row on screen
        LDB     Height          * B = Height
        DECB                    * Decrement the number of rows to copy
        LEAU    DoUp,PCR        * Get address for doing the Scrolling Up routine
SavePresets:
        STB     PrepB+1,PCR     * Self mod B's value for doing the actual Scroll
        STX     PrepX+1,PCR     * Self mod B's value for doing the actual Scroll
        STY     PrepY+2,PCR     * Self mod B's value for doing the actual Scroll
        STU     PrepScrollJump+1,PCR     * Self mod B's value for doing the actual Scroll
        LDD     #$0000          * Return with a value of zero to signify no errors occurred setting up the scroll area
        JSR     GIVABF          * Convert the value in ACCD into a floating point number in FPA0.
        PULS    CC,D,DP,X,Y,U,PC  * All Preset - Restore & Return to BASIC
 
DoUp:
!       LEAU    -32,X           * U is now the row below X on screen
        BSR     Blast           * Blast (copy) a row of RAM from X to U
        LEAX    32,X            * Move X down a row
        DECB                    * Decrement our counter
        BNE     <               * If not done, go do another row
        PULS    CC,D,DP,X,Y,U,PC  * Restore & Return to BASIC

* Scroll Down
* Enter with X = users screen starting location
ScrollDown:
        LDB     Width           * B is the width
        BSR     SetJumps        * Setup the jumps to blast a row on screen
        LDA     #32
        LDB     Height          * B = Height
        MUL
        ADDD    #$400-32*2      * Offset it to the start of the Text Screen in RAM
        LEAX    D,X
        LDB     Height          * B = Height
        DECB                    * Decrement the number of rows to copy
        LEAU    DoDown,PCR      * Get address for doing the Scrolling Down routine
        BRA     SavePresets     * Save values for doing the sctual scrolling and return
DoDown:
!       LEAU    32,X            * U is the row below X on screen
        BSR     Blast           * Blast (copy) a row of RAM from X to U
        LEAX    -32,X           * Move X up a row
        DECB                    * Decrement our counter
        BNE     <               * If not done, go do another row
        PULS    CC,D,DP,X,Y,U,PC  * Restore & Return to BASIC

* X = Source address
* U = Destination address
Blast:
        PSHS    B,X,Y,U         * Save Row counter B & starting points of X & U
        STS     StackPointer    * Save S
FirstJump:
        JMP     $FFFF           * Go do First routine then 2nd routine (This address get's self modded)

* Enter with X = users screen starting location
ScrollRight:
        LEAX    $400-2,X        * Offset it to the start of the Text Screen in RAM
        LDB     Width           * B is the width
        DECB
        ABX                     * Move X starting position to the right (we work right to left)
        BSR     SetJumpsR       * Setup the jumps to blast a row on screen to the right
        LDB     Height          * B = Height
        LEAU    DoRight,PCR     * Get address for doing the Scrolling Right routine
        BRA     SavePresets     * Save values for doing the sctual scrolling and return
DoRight:
!       LEAU    1,X             * U is the byte to the right
        BSR     Blast           * Blast (copy) a row of RAM from X to U
        LEAX    32,X            * Move X down a row
        DECB                    * Decrement our counter
        BNE     <               * If not done, go do another row
        PULS    CC,D,DP,X,Y,U,PC  * Restore & Return to BASIC

* Enter with X = users screen starting location
ScrollLeft:
        LEAX    $401,X          * Offset it to the start of the Text Screen in RAM
        LDB     Width           * B is the width
        DECB
        BSR     SetJumps        * Setup the jumps to blast a row on screen
        LDB     Height          * B = Height
        LEAU    DoLeft,PCR      * Get address for doing the Scrolling Left routine
        LBRA    SavePresets     * Save values for doing the sctual scrolling and return
DoLeft:
!       LEAU    -1,X            * U is the byte to the left
        BSR     Blast           * Blast (copy) a row of RAM from X to U
        LEAX    32,X            * Move X down a row
        DECB                    * Decrement our counter
        BNE     <               * If not done, go do another row
        PULS    CC,D,DP,X,Y,U,PC  * Restore & Return to BASIC

* Set two required jumps to do a row
* Enter with B = the width of window
SetJumps:
        PSHS    D,X,U           * Save registers
        LSLB                    * B = B * 2 New range is 0 to 62
        LSLB                    * B = B * 2 New range is 0 to 124
        LEAX    BlastTable,PCR  * X = the current BlastTable entry lcoation
        ABX                     * Move X to the correct entry in the table
        LDD     ,X              * D = the correct jump address for the routine
        LEAU    D,X             * Add the offset to the jump location
        STU     FirstJump+1,PCR * Save the First Jump value to be used later (Self Mod)
        LDD     2,X             * D = the correct jump address for the routine
        LEAY    D,X             * Make Y the 2nd jump location
        PULS    D,X,U,PC

SetJumpsR:
        PSHS    D,X,U           * Save registers
        LSLB                    * B = B * 2 New range is 0 to 62
        LSLB                    * B = B * 2 New range is 0 to 124
        LEAX    BlastTableR,PCR  * X = the current BlastTable entry lcoation
        ABX                     * Move X to the correct entry in the table
        LDD     ,X              * D = the correct jump address for the routine
        LEAU    D,X             * Add the offset to the jump location
        STU     FirstJump+1,PCR * Save the First Jump value to be used later (Self Mod)
        LDD     2,X             * D = the correct jump address for the routine
        LEAY    D,X             * Make Y the 2nd jump location
        PULS    D,X,U,PC

* Jump Table for entries 1 to 32
BlastTable:
        FDB     DoNothing-*,Return-*     * Do width of zero
        FDB     Do1-*,Return-*    * Do width of 1
        FDB     Do2-*,Return-*    * Do width of 2
        FDB     Do3-*,Return-*    * Do width of 3
        FDB     Do4-*,Return-*    * Do width of 4
        FDB     Do5-*,Return-*    * Do width of 5
        FDB     Do6-*,Return-*    * Do width of 6
        FDB     Do0-*,Do7B-*    * Do width of 7
        FDB     Do1-*,Do7B-*    * Do width of 8
        FDB     Do2-*,Do7B-*    * Do width of 9
        FDB     Do3-*,Do7B-*    * Do width of 10
        FDB     Do4-*,Do7B-*    * Do width of 11
        FDB     Do5-*,Do7B-*    * Do width of 12
        FDB     Do6-*,Do7B-*    * Do width of 13
        FDB     Do0-*,Do14-*    * Do width of 14
        FDB     Do1-*,Do14-*    * Do width of 15
        FDB     Do2-*,Do14-*    * Do width of 16
        FDB     Do3-*,Do14-*    * Do width of 17
        FDB     Do4-*,Do14-*    * Do width of 18
        FDB     Do5-*,Do14-*    * Do width of 19
        FDB     Do6-*,Do14-*    * Do width of 20
        FDB     Do0-*,Do21-*    * Do width of 21
        FDB     Do1-*,Do21-*    * Do width of 22
        FDB     Do2-*,Do21-*    * Do width of 23
        FDB     Do3-*,Do21-*    * Do width of 24
        FDB     Do4-*,Do21-*    * Do width of 25
        FDB     Do5-*,Do21-*    * Do width of 26
        FDB     Do6-*,Do21-*    * Do width of 27
        FDB     Do0-*,Do28-*    * Do width of 28
        FDB     Do1-*,Do28-*    * Do width of 29
        FDB     Do2-*,Do28-*    * Do width of 30
        FDB     Do3-*,Do28-*    * Do width of 31
        FDB     Do4-*,Do28-*    * Do width of 32

Do7:    LDD     ,X
        STD     ,U
        LDD     2,X
        STD     2,U
        LDD     4,X
        STD     4,U
        LDA     6,X
        STA     6,U
        LEAS    7,X             * S = Source address
        LEAU    7+7,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do6:    LDD     ,X
        STD     ,U
        LDD     2,X
        STD     2,U
        LDD     4,X
        STD     4,U
        LEAS    6,X              * S = Source address
        LEAU    7+6,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do5:    LDD     ,X
        STD     ,U
        LDD     2,X
        STD     2,U
        LDA     4,X
        STA     4,U
        LEAS    5,X              * S = Source address
        LEAU    7+5,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do4:    LDD     ,X
        STD     ,U
        LDD     2,X
        STD     2,U
        LEAS    4,X              * S = Source address
        LEAU    7+4,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do3:    LDD     ,X
        STD     ,U
        LDA     2,X
        STA     2,U
        LEAS    3,X              * S = Source address
        LEAU    7+3,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do2:    LDD     ,X
        STD     ,U
        LEAS    2,X              * S = Source address
        LEAU    7+2,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do1:    LDA     ,X
        STA     ,U
        LEAS    1,X              * S = Source address
        LEAU    7+1,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return
Do0:    LEAS    ,X              * S = Source address
        LEAU    7,U             * Prepare U for a stack blast
        JMP     ,Y              * Do second jump, restore registers and Return

Do28:   PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 28 Total
        LEAU    14,U            * Position U for the next 7 Bytes
Do21:   PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 21 Total
        LEAU    14,U            * Position U for the next 7 Bytes
Do14:   PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 14 Total
        LEAU    14,U            * Position U for the next 7 Bytes
Do7B:   PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 7 Total
        LDS     StackPointer    * Restore S
        PULS    B,X,Y,U,PC      * Done Return


* Jump Table for entries 1 to 32 scroll right
BlastTableR:
        FDB     DoNothing-*,Return-*    * Do width of zero
        FDB     Do1R-*,Return-* * Do width of 1
        FDB     Do2R-*,Return-* * Do width of 2
        FDB     Do3R-*,Return-* * Do width of 3
        FDB     Do4R-*,Return-* * Do width of 4
        FDB     Do5R-*,Return-* * Do width of 5
        FDB     Do6R-*,Return-* * Do width of 6
        FDB     Do0R-*,Do7BR-*  * Do width of 7
        FDB     Do1R-*,Do7BR-*  * Do width of 8
        FDB     Do2R-*,Do7BR-*  * Do width of 9
        FDB     Do3R-*,Do7BR-*  * Do width of 10
        FDB     Do4R-*,Do7BR-*  * Do width of 11
        FDB     Do5R-*,Do7BR-*  * Do width of 12
        FDB     Do6R-*,Do7BR-*  * Do width of 13
        FDB     Do0R-*,Do14R-*  * Do width of 14
        FDB     Do1R-*,Do14R-*  * Do width of 15
        FDB     Do2R-*,Do14R-*  * Do width of 16
        FDB     Do3R-*,Do14R-*  * Do width of 17
        FDB     Do4R-*,Do14R-*  * Do width of 18
        FDB     Do5R-*,Do14R-*  * Do width of 19
        FDB     Do6R-*,Do14R-*  * Do width of 20
        FDB     Do0R-*,Do21R-*  * Do width of 21
        FDB     Do1R-*,Do21R-*  * Do width of 22
        FDB     Do2R-*,Do21R-*  * Do width of 23
        FDB     Do3R-*,Do21R-*  * Do width of 24
        FDB     Do4R-*,Do21R-*  * Do width of 25
        FDB     Do5R-*,Do21R-*  * Do width of 26
        FDB     Do6R-*,Do21R-*  * Do width of 27
        FDB     Do0R-*,Do28R-*  * Do width of 28
        FDB     Do1R-*,Do28R-*  * Do width of 29
        FDB     Do2R-*,Do28R-*  * Do width of 30
        FDB     Do3R-*,Do28R-*  * Do width of 31
        FDB     Do4R-*,Do28R-*  * Do width of 32

Do7R:   LDD     ,X
        STD     ,U
        LDD     -2,X
        STD     -2,U
        LDD     -4,X
        STD     -4,U
        LDA     -5,X
        STA     -5,U
        LEAS    -7-5,X           * S = Source address
        LEAU    -5,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do6R:   LDD     ,X
        STD     ,U
        LDD     -2,X
        STD     -2,U
        LDD     -4,X
        STD     -4,U
        LEAS    -7-4,X            * S = Source address
        LEAU    -4,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do5R:   LDD     ,X
        STD     ,U
        LDD     -2,X
        STD     -2,U
        LDA     -3,X
        STA     -3,U
        LEAS    -7-3,X            * S = Source address
        LEAU    -3,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do4R:   LDD     ,X
        STD     ,U
        LDD     -2,X
        STD     -2,U
        LEAS    -7-2,X            * S = Source address
        LEAU    -2,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do3R:   LDD     ,X
        STD     ,U
        LDA     -1,X
        STA     -1,U
        LEAS    -7-1,X            * S = Source address
        LEAU    -1,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do2R:   LDD     ,X
        STD     ,U
        LEAS    -7,X            * S = Source address
        JMP     ,Y              * Do second jump, restore registers and Return
Do1R:   LDA     1,X
        STA     1,U
        LEAS    -7+1,X            * S = Source address
        LEAU    1,U
        JMP     ,Y              * Do second jump, restore registers and Return
Do0R:   LEAS    -7+2,X            * S = Source address
        LEAU    2,U
        JMP     ,Y              * Do second jump, restore registers and Return
DoNothing:
Return:
        LDS     StackPointer    * Restore S
        PULS    B,X,Y,U,PC      * Done Return

* U is the byte to the right
Do28R:  PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 28 Total
        LEAS    -14,S           * Position S for the next 7 Bytes
Do21R:  PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 21 Total
        LEAS    -14,S           * Position S for the next 7 Bytes
Do14R:  PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 14 Total
        LEAS    -14,S           * Position S for the next 7 Bytes
Do7BR:  PULS    D,DP,X,Y        * Read 7 Bytes
        PSHU    D,DP,X,Y        * Write 7 Bytes - 7 Total
        LDS     StackPointer    * Restore S
        PULS    B,X,Y,U,PC      * Done Return

LAST:
_4kCLEAR        EQU     $1000-LAST
_16kCLEAR       EQU     $4000-LAST
_32kCLEAR       EQU     $8000-LAST
        END     CoCo_START
