import React from "react";
import { renderToReadableStream } from "react-dom/server.browser";
import styles from "./styles.css?raw";

export function LandingPage() {
  return (
    <html lang="en">
      <head>
        <meta charSet="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>moCODE - AI-Assisted Coding on Your Mobile Device</title>
        <meta
          name="description"
          content="The mobile companion for OpenCode/KiloCode Server. Connect to your server and bring AI-assisted coding to your mobile device."
        />
        <meta property="og:type" content="website" />
        <meta property="og:title" content="moCODE - AI-Assisted Coding on Your Mobile Device" />
        <meta
          property="og:description"
          content="The mobile companion for OpenCode/KiloCode Server. Connect to your server and bring AI-assisted coding to your mobile device."
        />
        <meta property="og:image" content="/images/feature-cover.png" />
        <meta name="twitter:card" content="summary_large_image" />
        <meta name="twitter:title" content="moCODE - AI-Assisted Coding on Your Mobile Device" />
        <meta
          name="twitter:description"
          content="The mobile companion for OpenCode/KiloCode Server. Connect to your server and bring AI-assisted coding to your mobile device."
        />
        <meta name="twitter:image" content="/images/feature-cover.png" />
        <link rel="icon" type="image/png" href="/app-icon.png" />
        <link rel="apple-touch-icon" href="/app-icon.png" />
        <style dangerouslySetInnerHTML={{ __html: styles }} />
      </head>
      <body>
        <div className="bg-pattern" />
        <div className="bg-grid" />

        <header className="header">
          <div className="container header-content">
            <a href="/" className="logo">
              moCODE
            </a>
            <nav className="nav">
              <a href="#features" className="nav-link">Features</a>
              <a href="#screenshots" className="nav-link">Screenshots</a>
              <a href="#setup" className="nav-link">Setup</a>
              <a
                href="https://play.google.com/apps/internaltest/4701180456195017781"
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-primary"
                style={{ padding: "10px 20px", fontSize: "14px" }}
              >
                Get the App
              </a>
            </nav>
          </div>
        </header>

        <section className="hero">
          <div className="container hero-content">
            <div className="hero-text">
              <div className="hero-badge">
                <span className="hero-badge-dot" />
                Now Available on Google Play
              </div>
              <h1 className="hero-title">
                Code Anywhere with{" "}
                <span className="hero-title-accent">AI Assistance</span>
              </h1>
              <p className="hero-description">
                The mobile companion for OpenCode/KiloCode Server. Connect to your
                server and bring powerful AI-assisted coding directly to your
                mobile device. Write, review, and ship code from anywhere.
              </p>
              <div className="hero-actions">
                <a
                  href="https://play.google.com/apps/internaltest/4701180456195017781"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="btn btn-primary"
                >
                  <span className="btn-icon">▶</span>
                  Join Google Play Tester
                </a>
                <a href="#features" className="btn btn-secondary">
                  See Features
                </a>
              </div>
            </div>

            <div className="hero-visual">
              <div className="hero-phone">
                <div className="hero-phone-screen">
                  <div className="hero-phone-carousel" aria-hidden="true">
                    <img
                      className="hero-phone-slide"
                      src="/images/1.jpeg"
                      alt="moCODE screenshot 1"
                    />
                    <img
                      className="hero-phone-slide"
                      src="/images/2.jpeg"
                      alt="moCODE screenshot 2"
                    />
                    <img
                      className="hero-phone-slide"
                      src="/images/3.jpeg"
                      alt="moCODE screenshot 3"
                    />
                    <img
                      className="hero-phone-slide"
                      src="/images/4.jpeg"
                      alt="moCODE screenshot 4"
                    />
                    <img
                      className="hero-phone-slide"
                      src="/images/5.jpeg"
                      alt="moCODE screenshot 5"
                    />
                    <img
                      className="hero-phone-slide"
                      src="/images/6.jpeg"
                      alt="moCODE screenshot 6"
                    />
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>

        <section id="screenshots" className="screenshots">
          <div className="section-header">
            <span className="section-label">Screenshots</span>
            <h2 className="section-title">See It In Action</h2>
            <p className="section-description">
              A powerful IDE in your pocket with a beautiful dark interface.
            </p>
          </div>
          <div className="screenshots-track">
            <div className="screenshot-card">
              <img src="/images/1.jpeg" alt="moCODE Chat Interface" />
            </div>
            <div className="screenshot-card">
              <img src="/images/2.jpeg" alt="moCODE File Browser" />
            </div>
            <div className="screenshot-card">
              <img src="/images/3.jpeg" alt="moCODE Model Selection" />
            </div>
            <div className="screenshot-card">
              <img src="/images/4.jpeg" alt="moCODE Session Management" />
            </div>
            <div className="screenshot-card">
              <img src="/images/5.jpeg" alt="moCODE Developer Tools" />
            </div>
            <div className="screenshot-card">
              <img src="/images/6.jpeg" alt="moCODE Terminal" />
            </div>
            <div className="screenshot-card">
              <img src="/images/1.jpeg" alt="moCODE Chat Interface" />
            </div>
            <div className="screenshot-card">
              <img src="/images/2.jpeg" alt="moCODE File Browser" />
            </div>
            <div className="screenshot-card">
              <img src="/images/3.jpeg" alt="moCODE Model Selection" />
            </div>
            <div className="screenshot-card">
              <img src="/images/4.jpeg" alt="moCODE Session Management" />
            </div>
            <div className="screenshot-card">
              <img src="/images/5.jpeg" alt="moCODE Developer Tools" />
            </div>
            <div className="screenshot-card">
              <img src="/images/6.jpeg" alt="moCODE Terminal" />
            </div>
          </div>
        </section>

        <section id="features" className="features">
          <div className="container">
            <div className="section-header">
              <span className="section-label">Features</span>
              <h2 className="section-title">
                Everything You Need for Mobile Development
              </h2>
              <p className="section-description">
                A powerful IDE in your pocket with all the features developers expect.
              </p>
            </div>

            <div className="features-grid">
              <div className="feature-card">
                <div className="feature-icon">💬</div>
                <h3 className="feature-title">AI Chat Interface</h3>
                <p className="feature-description">
                  Smart chat with @file mentions to reference files in
                  conversations. Slash commands for quick actions. Markdown
                  rendering with syntax-highlighted code blocks. Real-time
                  streaming responses.
                </p>
              </div>

              <div className="feature-card">
                <div className="feature-icon">📁</div>
                <h3 className="feature-title">Session Management</h3>
                <p className="feature-description">
                  Create, fork, archive, and share chat sessions. Organize by
                  Git branch status. Search and filter through your history.
                  Safe deletion with confirmations.
                </p>
              </div>

              <div className="feature-card">
                <div className="feature-icon">🤖</div>
                <h3 className="feature-title">Model Selection</h3>
                <p className="feature-description">
                  Browse all available models from your providers. Star
                  favorites for quick access. Set default models per session or
                  globally. Full support for reasoning models.
                </p>
              </div>

              <div className="feature-card">
                <div className="feature-icon">📝</div>
                <h3 className="feature-title">Developer Tools</h3>
                <p className="feature-description">
                  Rich diff viewer with syntax highlighting. File changes
                  sidebar showing additions/deletions. Clear error messages with
                  troubleshooting. Built-in terminal with SSH support.
                </p>
              </div>

              <div className="feature-card">
                <div className="feature-icon">📂</div>
                <h3 className="feature-title">File Browser</h3>
                <p className="feature-description">
                  SFTP integration for remote file navigation. Download files
                  directly to your device. Bookmark frequently accessed files
                  with sorting options.
                </p>
              </div>

              <div className="feature-card">
                <div className="feature-icon">🔒</div>
                <h3 className="feature-title">Secure & Modern</h3>
                <p className="feature-description">
                  Built for developers who demand security. Modern interface
                  designed for productivity. Regular updates and improvements.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section id="setup" className="setup">
          <div className="container">
            <div className="section-header">
              <span className="section-label">Get Started</span>
              <h2 className="section-title">Setup in 3 Simple Steps</h2>
              <p className="section-description">
                Be up and running in minutes with your AI coding assistant.
              </p>
            </div>

            <div className="setup-grid">
              <div className="setup-step">
                <div className="step-number">1</div>
                <h3 className="step-title">Run OpenCode Server</h3>
                <p className="step-description">
                  Have an OpenCode Server running locally or on a remote machine.
                  Make sure it's accessible via network.
                </p>
              </div>

              <div className="setup-step">
                <div className="step-number">2</div>
                <h3 className="step-title">Enter Server Address</h3>
                <p className="step-description">
                  Open moCODE, go to Settings, and enter your server address.
                  Sign in with your Google account.
                </p>
              </div>

              <div className="setup-step">
                <div className="step-number">3</div>
                <h3 className="step-title">Start Coding Smarter</h3>
                <p className="step-description">
                  You're ready! Chat with AI, browse files, write code, and
                  bring your development workflow mobile.
                </p>
              </div>
            </div>
          </div>
        </section>

        <section className="cta">
          <div className="container">
            <div className="cta-content">
              <h2 className="cta-title">
                Ready to Code on the Go?
              </h2>
              <p className="cta-description">
                Join our Google Play Tester program and be the first to
                experience new features. Your feedback shapes the future of
                moCODE.
              </p>
              <div className="cta-buttons">
                <a
                  href="https://play.google.com/apps/internaltest/4701180456195017781"
                  target="_blank"
                  rel="noopener noreferrer"
                  className="play-store-badge"
                >
                  <svg
                    className="play-store-icon"
                    viewBox="0 0 24 24"
                    fill="currentColor"
                  >
                    <path d="M3.609 1.814L13.792 12 3.61 22.186a.996.996 0 01-.61-.92V2.734a1 1 0 01.609-.92zm10.89 10.893l2.302 2.302-10.937 6.333 8.635-8.635zm3.199-3.198l2.807 1.626a1 1 0 010 1.73l-2.808 1.626L15.206 12l2.492-2.491zM5.864 2.658L16.8 8.99l-2.302 2.302-8.634-8.634z" />
                  </svg>
                  <div className="play-store-text">
                    <div className="play-store-text-small">Join Google Play</div>
                    <div className="play-store-text-big">Tester Program</div>
                  </div>
                </a>
              </div>
            </div>
          </div>
        </section>

        <footer className="footer">
          <div className="container footer-content">
            <p className="footer-text">
              © 2024 moCODE. Built for developers.
            </p>
            <div className="footer-links">
              <a href="/privacy" className="footer-link">
                Privacy
              </a>
              <a href="/terms" className="footer-link">
                Terms
              </a>
            </div>
          </div>
        </footer>
      </body>
    </html>
  );
}

export async function renderLandingPage() {
  const stream = await renderToReadableStream(<LandingPage />);
  return new Response(stream, {
    headers: {
      "Content-Type": "text/html",
    },
  });
}
