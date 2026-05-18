# reference.nvim

A small Neovim plugin for sending file references from your editor to an
AI CLI agent running in another tmux pane.

It is heavily inspired by
[code-bridge.nvim](https://github.com/samir-roy/code-bridge.nvim) and
shares its GPL v2 licence. Where code-bridge.nvim aims to be a full
bridge between Neovim and an agent, reference.nvim sticks to one job:
hand the agent a file reference and get out of the way.

## Vibe code disclosure

Most of this plugin was written collaboratively with a clanker. The code has
been reviewed and shaped by me, but if you are reading the source expecting
hand-crafted artisanal Lua, this is your warning.

## Installation

### lazy.nvim

```lua
return {
  'danielronalds/reference.nvim',
  opts = {},
  keys = {
    { '<leader>rs', '<cmd>ReferenceSend<CR>', mode = 'n', desc = 'Send reference to agent' },
    { '<leader>rs', ":'<,'>ReferenceSend<CR>", mode = 'v', desc = 'Send reference (range) to agent' },
    { '<leader>rf', '<cmd>ReferenceSendFirst<CR>', mode = 'n', desc = 'Send reference to first agent' },
    { '<leader>rf', ":'<,'>ReferenceSendFirst<CR>", mode = 'v', desc = 'Send reference (range) to first agent' },
  },
}
```

## Usage

The plugin exposes two user commands. Both accept a visual range.

### `:ReferenceSend`

Send a reference to the current file to an agent running in tmux.

- In normal mode, sends `@path/to/file`.
- With a visual selection, sends `@path/to/file#L<line1>-<line2>`.
- If exactly one agent is found, sends to it directly.
- If more than one agent is found, opens a `vim.ui.select` picker
  showing each agent's process, session, window, and pane.

### `:ReferenceSendFirst`

Same as `:ReferenceSend`, but skips the picker when multiple agents are
found and sends to the first one discovered. Useful when bound to a
keymap and you do not want a prompt in the middle of your flow.

## Configuration

The plugin works without any configuration. Pass a table to `setup` to
override defaults.

### Options

| Option                  | Type       | Default                          |
| ----------------------- | ---------- | -------------------------------- |
| `tmux.process_names`    | `string[]` | `{ 'claude', 'opencode', 'pi' }` |
| `tmux.switch_to_target` | `boolean`  | `true`                           |

`tmux.process_names` is the list of process names to look for when
discovering agents in tmux panes. Names are also matched against the
arguments of any `node` child processes, so Claude Code is found
through its node wrapper.

`tmux.switch_to_target` controls whether the active tmux window and
pane are switched to the target agent after sending.

### Defaults

```lua
require('reference').setup({
  tmux = {
    process_names = { 'claude', 'opencode', 'pi' },
    switch_to_target = true,
  },
})
```
