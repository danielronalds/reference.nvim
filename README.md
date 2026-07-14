# reference.nvim

A small Neovim plugin for sending file references from your editor to an
AI CLI agent running in another tmux pane or the current WADE session.

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

Send a reference to the current file to an agent running in the configured
reference driver.

- In normal mode, sends `@path/to/file`.
- With a visual selection, sends `@path/to/file#L<line1>-<line2>`.
- With the default tmux driver, if exactly one agent is found, sends to it directly.
- With the default tmux driver, if more than one agent is found, opens a `vim.ui.select` picker
  showing each agent's process, session, window, and pane.
- With the WADE driver, sends to the active agent terminal for the current `WADE_SESSION`.

### `:ReferenceSendFirst`

Same as `:ReferenceSend`, but skips the tmux picker when multiple agents are
found and sends to the first one discovered. With the WADE driver, this behaves
the same as `:ReferenceSend`. Useful when bound to a keymap and you do not want
a prompt in the middle of your flow.

## Configuration

The plugin works without any configuration. Pass a table to `setup` to
override defaults.

### Options

| Option                  | Type       | Default                          |
| ----------------------- | ---------- | -------------------------------- |
| `driver`                | `string`   | `'tmux'`                         |
| `wade.timeout_seconds`  | `number`   | `5`                              |
| `tmux.process_names`    | `string[]` | `{ 'claude', 'opencode', 'pi' }` |
| `tmux.switch_to_target` | `boolean`  | `true`                           |

`driver` can be `'tmux'` or `'wade'`. The tmux driver preserves the original
behaviour. The WADE driver sends to WADE's local HTTP API using the current
`WADE_SESSION` environment variable as the project name.

`wade.timeout_seconds` controls the curl timeout for WADE API requests.

`tmux.process_names` is the list of process names to look for when
discovering agents in tmux panes. Names are also matched against the
arguments of any `node` child processes, so Claude Code is found
through its node wrapper.

`tmux.switch_to_target` controls whether the active tmux window and
pane are switched to the target agent after sending.

### Defaults

```lua
require('reference').setup({
  driver = 'tmux',
  wade = {
    timeout_seconds = 5,
  },
  tmux = {
    process_names = { 'claude', 'opencode', 'pi' },
    switch_to_target = true,
  },
})
```

### WADE driver

When running Neovim inside a WADE-launched terminal, use:

```lua
require('reference').setup({
  driver = 'wade',
})
```

The WADE driver reads the project name from `WADE_SESSION`. It resolves the
server address from `WADE_ADDR`, or falls back to WADE's default local hosts:
`editor-dev.localhost:8765` when `WADE_DEV` is enabled, otherwise
`editor.localhost:8765`.
