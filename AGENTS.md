# Project Overview

This project is a neovim plugin designed to enable Neovim and Tmux users to effectively prompt AI CLI agents in their workflow

It does this allowing the user to reference context in their neovim context and sending that information, via tmux, to an instance of an AI agent, such as Claude Code or Pi.

It's inspired by https://github.com/samir-roy/code-bridge.nvim, and shares it's license.

## How it works

When the user runs a command, the plugin discovers tmux panes running an agent (Claude Code, opencode, pi, or whatever is configured), formats the current file path (and optional visual range) as `@path/to/file` or `@path/to/file#L10-25`, and sends it to the agent's pane via `tmux send-keys`. If more than one agent is running, the user gets a picker. By default it then focuses the target pane.
