def main [dir: string] {
  let panes = (
    ^tmux list-panes -F '#{pane_left} #{pane_id}'
    | lines
    | parse "{left} {id}"
    | update left { into int }
  )
  let columns = (
    $panes
    | group-by left
    | transpose key value
    | sort-by { |r| $r.key | into int }
    | get value
  )
  let n = ($columns | length)
  if $n <= 1 { return }
  let current = (^tmux display -p '#{pane_id}' | str trim)
  let col_pos = (
    $columns
    | enumerate
    | where { |e| $e.item | any { |p| $p.id == $current } }
    | first
    | get index
  )
  let cur_left = ($columns | get $col_pos | first | get left)
  ^tmux set-option -w $"@last_pane_col_($cur_left)" $current
  let new_col_pos = if $dir == "D" { ($col_pos + 1) mod $n } else { ($col_pos - 1 + $n) mod $n }
  let new_col = ($columns | get $new_col_pos)
  let new_left = ($new_col | first | get left)
  let stored = (try { ^tmux show-options -wv $"@last_pane_col_($new_left)" } catch { "" } | str trim)
  let target = if ($stored | is-not-empty) and ($new_col | any { |p| $p.id == $stored }) {
    $stored
  } else {
    $new_col | first | get id
  }
  ^tmux select-pane -t $target
  tmux-pane-center
}
