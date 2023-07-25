defmodule ASM510.Opcodes do
  import Bitwise

  # Comments adapted from: https://github.com/mamedev/mame/blob/2d0088772029a2b788b1eeac64984fb375662410/src/devices/cpu/sm510/sm510op.cpp

  defguard is_opcode(string)
           when string in [
                  "ADD",
                  "ADD11",
                  "ADX",
                  "ATBP",
                  "ATFC",
                  "ATL",
                  "ATPL",
                  "ATR",
                  "BDC",
                  "CEND",
                  "COMA",
                  "DC",
                  "DECB",
                  "EXBLA",
                  "EXC",
                  "EXCD",
                  "EXCI",
                  "IDIV",
                  "INCB",
                  "KTA",
                  "LAX",
                  "LB",
                  "LBL",
                  "LDA",
                  "RC",
                  "RM",
                  "ROT",
                  "RTN0",
                  "RTN1",
                  "SBM",
                  "SC",
                  "SKIP",
                  "SM",
                  "T",
                  "TA0",
                  "TABL",
                  "TAL",
                  "TAM",
                  "TB",
                  "TC",
                  "TF1",
                  "TF4",
                  "TIS",
                  "TL",
                  "TM",
                  "TMI",
                  "TML",
                  "WR",
                  "WS"
                ]

  # ADD: add RAM to ACC
  def get_opcode("ADD", [], _), do: {:ok, [0x08]}

  # ADD11: add RAM and carry to ACC and carry, skip next on carry
  def get_opcode("ADD11", [], _), do: {:ok, [0x09]}

  # ADX: add immediate value to ACC, skip next on carry except if x = 10
  def get_opcode("ADX", [x], _), do: {:ok, [0x30 + x]}

  # ATBP: output ACC to BP LCD flag(s)
  def get_opcode("ATBP", [], _), do: {:ok, [0x01]}

  # ATFC: output ACC to Y
  def get_opcode("ATFC", [], _), do: {:ok, [0x60]}

  # ATL: output ACC to L
  def get_opcode("ATL", [], _), do: {:ok, [0x59]}

  # ATPL: load PL (PC low bits) with ACC
  def get_opcode("ATPL", [], _), do: {:ok, [0x03]}

  # ATR: output ACC to R
  def get_opcode("ATR", [], _), do: {:ok, [0x61]}

  # BDC: enable LCD bleeder current with C
  def get_opcode("BDC", [], _), do: {:ok, [0x6D]}

  # CEND: stop clock (halt the CPU and go into low-power mode)
  def get_opcode("CEND", [], _), do: {:ok, [0x5D]}

  # COMA: complement ACC
  def get_opcode("COMA", [], _), do: {:ok, [0x0A]}

  # DC: same as ADX 10
  def get_opcode("DC", [], _), do: {:ok, [0x3A]}

  # DECB: decrement BL, skip next on overflow
  def get_opcode("DECB", [], _), do: {:ok, [0x6C]}

  # EXBLA: exchange BL with ACC
  def get_opcode("EXBLA", [], _), do: {:ok, [0x0B]}

  # EXC x: exchange ACC with RAM, xor BM with x
  def get_opcode("EXC", [x], _), do: {:ok, [0x10 + (x &&& 3)]}

  # EXCD x: EXC x, DECB
  def get_opcode("EXCD", [x], _), do: {:ok, [0x1C + x]}

  # EXCI x: EXC x, INCB
  def get_opcode("EXCI", [x], _), do: {:ok, [0x14 + x]}

  # IDIV: reset divider
  def get_opcode("IDIV", [], _), do: {:ok, [0x65]}

  # INCB: increment BL, skip next on overflow
  def get_opcode("INCB", [], _), do: {:ok, [0x64]}

  # KTA: input K to ACC
  def get_opcode("KTA", [], _), do: {:ok, [0x6A]}

  # LAX x: load ACC with immediate value, skip any next LAX
  def get_opcode("LAX", [x], _), do: {:ok, [0x20 + x]}

  # LB x: load BM/BL with 4-bit immediate value (partial)
  def get_opcode("LB", [x], _), do: {:ok, [0x40 + (x &&& 0x0F)]}

  # LBL xy: load BM/BL with 8-bit immediate value
  def get_opcode("LBL", [xy], _), do: {:ok, [0x5F, xy]}

  # LDA x: load ACC with RAM, xor BM with x
  def get_opcode("LDA", [x], _), do: {:ok, [0x18 + x]}

  # RC: reset carry
  def get_opcode("RC", [], _), do: {:ok, [0x66]}

  # RM x: reset RAM bit
  def get_opcode("RM", [x], _), do: {:ok, [0x04 + x]}

  # ROT: rotate ACC right through carry
  def get_opcode("ROT", [], _), do: {:ok, [0x6B]}

  # RTN0: return from subroutine
  def get_opcode("RTN0", [], _), do: {:ok, [0x6E]}

  # RTN1: return from subroutine, skip next
  def get_opcode("RTN1", [], _), do: {:ok, [0x6F]}

  # SBM: set BM high bit for next opcode
  def get_opcode("SBM", [], _), do: {:ok, [0x02]}

  # SC: set carry
  def get_opcode("SC", [], _), do: {:ok, [0x67]}

  # SKIP: no operation
  def get_opcode("SKIP", [], _), do: {:ok, [0x00]}

  # SM x: set RAM bit
  def get_opcode("SM", [x], _), do: {:ok, [0x0C + x]}

  # T xy: jump (transfer) within current page
  def get_opcode("T", [x], _), do: {:ok, [0x80 + (x &&& 0x3F)]}

  # TA0: skip next if ACC is clear
  def get_opcode("TA0", [], _), do: {:ok, [0x5A]}

  # TAL: skip next if BA pin is set
  def get_opcode("TAL", [], _), do: {:ok, [0x5E]}

  # TABL: skip next if ACC equals BL
  def get_opcode("TABL", [], _), do: {:ok, [0x5B]}

  # TAM: skip next if ACC equals RAM
  def get_opcode("TAM", [], _), do: {:ok, [0x53]}

  # TB: skip next if B (beta) pin is set
  def get_opcode("TB", [], _), do: {:ok, [0x51]}

  # TC: skip next if no carry
  def get_opcode("TC", [], _), do: {:ok, [0x52]}

  # TF1: skip next if divider F1 (d14) is set
  def get_opcode("TF1", [], _), do: {:ok, [0x68]}

  # TF4: skip next if divider F4 (d11) is set
  def get_opcode("TF4", [], _), do: {:ok, [0x69]}

  # TIS: skip next if 1S (gamma flag) is clear, reset it after
  def get_opcode("TIS", [], _), do: {:ok, [0x58]}

  # TL xyz: long jump
  def get_opcode("TL", [xyz], _), do: {:ok, [0x70 + (xyz >>> 8), xyz &&& 0xFF]}

  # TM x: indirect subroutine call, pointers (IDX) are on page 0
  def get_opcode("TM", [x], _), do: {:ok, [0xC0 + x]}

  # TMI x: skip next if RAM bit is set
  def get_opcode("TMI", [x], _), do: {:ok, [0x54 + x]}

  # TML xyz: long call
  def get_opcode("TML", [xyz], _), do: {:ok, [0x7C + (xyz >>> 8), xyz &&& 0xFF]}

  # WR: shift 0 into W
  def get_opcode("WR", [], _), do: {:ok, [0x62]}

  # WS: shift 1 into W
  def get_opcode("WS", [], _), do: {:ok, [0x63]}

  # Unknown opcode or wrong arity
  def get_opcode(opcode, args, line_number),
    do: {:error, line_number, {:bad_opcode, opcode, length(args)}}
end
