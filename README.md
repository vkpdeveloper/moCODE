# mecode

meCode is a Flutter client for a local/remote AI coding server. It lets you
pick a project directory, create chat sessions, and work with models through
a focused, developer-first UI.

## Features

- Project picker with VCS and health status indicators
- Session list with create, delete, fork, archive, and share controls
- Chat UI with plan/build mode toggle and model selection
- File attachment and command palettes inside the chat input (@ files, / commands)
- Live session status updates and streaming event handling
- Per-session model persistence plus user default model selection
- Server configuration (host/port) and connectivity status

## Tech Stack

- Flutter + Riverpod
- GoRouter navigation
- REST + event stream integration with the backend server
