# I Built a Mobile IDE So I Could Ship Code from My Bed

**And fix production bugs while walking my dog.**

---

It was 11 PM. I was in bed, scrolling through my phone, when a notification popped up: a critical bug in production. My laptop was downstairs. The bug was simple—a one-line fix. But here I was, trapped by my own setup.

Sound familiar?

As developers, we've accepted a weird reality: our best ideas (and worst bugs) don't respect office hours. Yet we're tethered to our desks by the tools we use.

That's why I built **moCode**.

---

## The Problem With "Coding on the Go"

Sure, there are mobile code editors. But they're exactly that—editors. They let you *type* code on a phone. Which is fine if you enjoy masochism.

What I wanted was different. I wanted to:

- **Experiment with ideas** whenever inspiration struck
- **Leverage my Tailscale setup** to access my home lab from anywhere
- **Fix bugs** without running downstairs to grab my laptop
- **Add features** while testing on my phone, using my phone

I didn't want to *type* more code on mobile. I wanted to *think* about code, and have an intelligent agent help me write it.

---

## Enter AI-Assisted TUI

moCode isn't just a mobile IDE. It's a window into AI-powered terminal interfaces like [OpenCode](https://github.com/chaifam/opencode) and [KiloCode](https://github.com/kilocode)

The paradigm shift? **You don't write the code. You talk to the agent.**

Instead of tapping out brackets and semicolons on a tiny keyboard, you have a conversation:

> "@server.js find the memory leak in the API route"

> "Refactor this authentication logic to use JWT instead of sessions"

> "Create a new endpoint for user profile updates with validation"

The AI agent understands your codebase, makes the changes, and explains what it did. You review, you guide, you ship.

---

## What Makes moCode Different

Most mobile dev tools try to shrink the desktop experience. We reimagined it for mobile-first workflows:

### AI-First Interface
Smart chat with @file mentions, slash commands, and streaming responses. Markdown rendering with syntax-highlighted code blocks. It's like having a senior dev pair programming with you.

### Full Development Environment
- **SFTP file browser** with bookmarks and downloads
- **Built-in terminal** with SSH support
- **Rich diff viewer** showing exactly what changed
- **Session management** organized by Git branches

### Model Flexibility
Browse all your AI providers, star favorites, set defaults per session. Full support for reasoning models when you need deep thinking.

### Secure by Design
Connects to your own OpenCode Server. Your code never touches our servers. Works perfectly with Tailscale for private networking.

---

## Built With moCode

Here's the fun part: many of the experiments and features inside moCode were written *using* moCode.

That late-night bug fix that sparked the idea? I eventually fixed it from my phone. The new file browser feature? Prototyped on a train. The terminal integration? Debugged while waiting for coffee.

**Dogfooding isn't just a buzzword here. It's how we build.**

---

## How It Works (3 Minutes to Productivity)

1. **Run your OpenCode Server** locally or on a remote machine (Tailscale makes this beautiful)
2. **Enter your server address** in moCode settings, sign in with Google
3. **Start coding**—chat with AI, browse files, run commands, ship features

No complex setup. No desktop required. Just you, your phone, and an AI agent that knows your codebase.

---

## What's Next

moCode is currently in open beta on Google Play. We're iterating fast based on real usage.

**iOS is coming very soon.** (Apple developers, I hear you.)

We're also exploring:
- Offline mode for planes and spotty connections
- Voice-to-code for truly hands-free coding
- Deeper integrations with CI/CD pipelines

---

## Join the Beta

If you're tired of being chained to your desk when inspiration strikes, try moCode.

**[Join the Google Play Tester Program →](https://play.google.com/apps/internaltest/4701180456195017781)**

Your best ideas don't wait for you to be at your computer. Neither should your tools.

---

*moCode is free to use during beta. Connect it to your own OpenCode Server and experience AI-assisted coding from anywhere.*

**Website:** [mocode.ordinity.com](https://mocode.ordinity.com)  
**Questions?** Drop them in the comments—I'll be here.

---

*Built by developers, for developers. Code anywhere.*
