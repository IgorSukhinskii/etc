# Extract top-level column children from a horizontal container's inner string.
# Each child is: WxH,X,Y,PaneIndex  OR  WxH,X,Y[vertical-body]  OR  WxH,X,Y{horizontal-body}
# (depth-1 nesting only; sufficient for normal tmux split usage)
def split-top-level [s: string] {
  $s | parse --regex '(?P<col>\d+x\d+,\d+,\d+(?:,\d+|\[[^\]]*\]|\{[^}]*\}))' | get col
}

# Parse width from WxH at start of a layout child string
def parse-width [child: string] {
  $child | parse --regex '(?P<w>\d+)x\d+' | first | get w | into int
}

# Parse X coordinate from a layout child string
def parse-x [child: string] {
  $child | parse --regex '\d+x\d+,(?P<x>\d+),' | first | get x | into int
}

# Replace every WxH,OLD_X,Y occurrence in a child subtree string with WxH,NEW_X,Y
def update-x [child: string, old_x: int, new_x: int] {
  let pat = '(\d+x\d+,)' + ($old_x | into string) + '(,\d+)'
  let rep = "${1}" + ($new_x | into string) + "${2}"
  $child | str replace --regex --all $pat $rep
}

# Compute tmux's CRC16 checksum over the layout body (everything after "CKSUM,")
# Pure arithmetic — avoids bits commands (limited to 8-bit in Nushell 0.108)
def layout-checksum [body: string] {
  # Printable ASCII chars starting at code 32; str index-of gives offset, +32 = byte value
  let ascii = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
  let csum = ($body | split chars | reduce --fold 0 { |c, acc|
    let b = ($ascii | str index-of $c) + 32
    # (acc >> 1) | ((acc & 1) << 15)  via arithmetic, keep 16-bit
    let rotated = ($acc / 2 | into int) + (($acc mod 2) * 32768)
    ($rotated + $b) mod 65536
  })
  let hex_chars = ("0123456789abcdef" | split chars)
  [4096, 256, 16, 1] | each { |div| $hex_chars | get (($csum / $div | into int) mod 16) } | str join
}

def main [] {
  let pane_id = (^tmux display -p '#{pane_id}' | str trim)
  let pane_num = ($pane_id | str replace "%" "")
  let layout = (^tmux display-message -p '#{window_layout}' | str trim)

  # Strip checksum prefix (everything up to and including first comma)
  let sep = ($layout | str index-of ',')
  let body = ($layout | str substring ($sep + 1)..)

  # Root must be a horizontal container {…} for column rotation to apply
  let brace_pos = ($body | str index-of '{')
  if $brace_pos == -1 { return }  # single pane or vertical-only, nothing to do

  # Extract root header (WxH,X,Y) and children string
  let root_header = ($body | str substring 0..($brace_pos - 1))
  let body_len = ($body | str length)
  let inner = ($body | str substring ($brace_pos + 1)..($body_len - 2))  # strip { and }

  # Split children into columns (depth-aware: leaf or [...] or {...} per child)
  let columns = (split-top-level $inner)
  let n = ($columns | length)
  if $n <= 1 { return }

  # Find which column the current pane belongs to
  # Leaf nodes have format WxH,X,Y,PaneIndex — extract pane indices
  let pane_ids_per_col = ($columns | each { |col| $col | parse --regex '\d+x\d+,\d+,\d+,(?P<id>\d+)' | get id })
  let col_pos = ($pane_ids_per_col | enumerate | where { |e| $pane_num in $e.item } | first | get index)

  let center = $n // 2
  let delta = $col_pos - $center
  if $delta == 0 { return }

  # Count panes in each column (for rotate-window alignment)
  let pane_counts = ($pane_ids_per_col | each { |ids| $ids | length })

  # select-layout assigns panes to slots by pane_index order (ignores IDs in the string).
  # rotate-window -U shifts all pane indices so slot K+1 gets the pane that was at slot K.
  # We pre-rotate pane indices so that after select-layout the correct panes land in each slot.
  #
  # delta > 0 (current col is right of center): rotate columns left, first |delta| cols go to back
  #   → rotate-window -U by count of panes in those first columns
  # delta < 0 (current col is left of center): rotate columns right, last |delta| cols go to front
  #   → rotate-window -D by count of panes in those last columns
  let d = ($delta | math abs)
  let n_rotate = if $delta > 0 {
    $pane_counts | first $d | math sum
  } else {
    $pane_counts | last $d | math sum
  }

  if $delta > 0 {
    for _i in 0..($n_rotate - 1) { ^tmux rotate-window -U }
  } else {
    for _i in 0..($n_rotate - 1) { ^tmux rotate-window -D }
  }

  # Rotate columns so current pane's column is at center
  let rotated = if $delta > 0 {
    ($columns | last ($n - $d)) ++ ($columns | first $d)
  } else {
    ($columns | last $d) ++ ($columns | first ($n - $d))
  }

  # Recalculate X positions for rotated columns (widths preserved, just reordered)
  let widths = ($rotated | each { |col| parse-width $col })
  let new_xs = ($widths | reduce --fold {x: 0, xs: []} { |w, acc|
    {x: ($acc.x + $w + 1), xs: ($acc.xs | append $acc.x)}
  } | get xs)

  # Update x coordinates in each column subtree
  let updated_cols = ($rotated | enumerate | each { |e|
    let old_x = (parse-x $e.item)
    let new_x = ($new_xs | get $e.index)
    update-x $e.item $old_x $new_x
  })

  # Reconstruct layout body and apply via select-layout
  let new_inner = ($updated_cols | str join ",")
  let new_body = $root_header + "{" + $new_inner + "}"
  let cksum = (layout-checksum $new_body)
  ^tmux select-layout $"($cksum),($new_body)"
  ^tmux select-pane -t $pane_id
}
