class Terminal {
  constructor() {
    this.output = document.getElementById("output");
    this.input = document.getElementById("command-input");
    this.inputLine = document.getElementById("input-line");
    this.completionContainer = document.getElementById("completion-container");
    this.commandHistory = [];
    this.historyIndex = -1;
    this.availableCommands = [];

    this.init();
  }

  async init() {
    // Start with intro animation
    this.startIntroAnimation();

    // Set up input handling
    this.input.addEventListener("keydown", (e) => this.handleKeyDown(e));
    this.input.addEventListener("keyup", (e) => this.handleKeyUp(e));

    // Set up permanent focus on input
    this.setupPermanentFocus();

    // Fetch available commands
    try {
      const response = await fetch("/commands");
      if (response.ok) {
        this.availableCommands = await response.json();
      }
    } catch (error) {
      console.error("Failed to fetch available commands:", error);
    }

    // Set up clickable command functionality
    this.setupClickableCommands();
  }

  setupClickableCommands() {
    // Add event listeners for clickable commands
    document.addEventListener("click", (e) => {
      if (e.target.classList.contains("clickable-command")) {
        const command = e.target.getAttribute("data-command");
        if (command) {
          this.executeClickableCommand(command);
        }
      }
    });
  }

  setupPermanentFocus() {
    // Prevent losing focus by intercepting all focus events
    document.addEventListener("focusin", (e) => {
      // If input line is visible and focus is not on the input, force it back
      if (this.inputLine.style.display !== "none" && e.target !== this.input) {
        // Small delay to allow the event to complete before refocusing
        setTimeout(() => {
          if (this.inputLine.style.display !== "none") {
            this.input.focus();
          }
        }, 0);
      }
    });

    // Handle clicks anywhere on the document
    document.addEventListener("click", (e) => {
      // If input line is visible, ensure input stays focused
      if (this.inputLine.style.display !== "none") {
        setTimeout(() => {
          if (this.inputLine.style.display !== "none") {
            this.input.focus();
          }
        }, 0);
      }
    });

    // Handle mousedown to prevent focus loss before click events
    document.addEventListener("mousedown", (e) => {
      // Allow interaction with the input itself
      if (e.target === this.input || this.input.contains(e.target)) {
        return;
      }
      // For any other interaction when input is visible, keep focus on input
      if (this.inputLine.style.display !== "none") {
        setTimeout(() => {
          if (this.inputLine.style.display !== "none") {
            this.input.focus();
          }
        }, 0);
      }
    });

    // Handle keydown events to prevent Tab from causing focus loss
    document.addEventListener("keydown", (e) => {
      if (e.key === "Tab" && this.inputLine.style.display !== "none") {
        // Tab is handled by handleKeyDown, but ensure focus stays
        setTimeout(() => {
          if (this.inputLine.style.display !== "none") {
            this.input.focus();
          }
        }, 0);
      }
    });

    // Additional safeguard: periodically check focus when input should be focused
    setInterval(() => {
      if (
        this.inputLine.style.display !== "none" &&
        document.activeElement !== this.input
      ) {
        this.input.focus();
      }
    }, 1000);
  }

  executeClickableCommand(command) {
    // Simulate typing the command like the initial help
    this.showCommand(command);
    this.inputLine.style.display = "none";

    // Execute the command after a short delay (skip the command display since we already did it)
    setTimeout(() => {
      // Handle special commands
      if (command === "clear") {
        this.clearTerminal();
        return;
      }

      // Handle projects subcommands
      if (command.startsWith("projects ")) {
        const parts = command.split(" ");
        if (parts.length === 2) {
          const subcommand = parts[1];
          this.loadProjectSubcommand(subcommand);
          return;
        }
      }

      // Load command from commands directory
      this.loadCommand(command);
    }, 500);
  }

  startIntroAnimation() {
    const introText = [
      "Welcome to my Portfolio Website^5",
      "Welcome to my Portfolio Terminal^500",
      "Connecting...^1000",
      "Type 'help' to see available commands.",
    ];

    new Typed("#typed-intro", {
      strings: introText,
      typeSpeed: 10,
      backSpeed: 7,
      fadeOut: false,
      smartBackspace: true,
      loop: false,
      showCursor: true,
      cursorChar: "_",
      onComplete: () => {
        setTimeout(() => {
          this.showCommand("help");
          setTimeout(() => {
            this.loadCommand("help");
            // Ensure input gets focus after intro completes
            setTimeout(() => {
              if (this.inputLine.style.display !== "none") {
                this.input.focus();
              }
            }, 200);
          }, 500);
        }, 1000);
      },
    });
  }

  showCommand(command) {
    const commandLine = document.createElement("div");
    commandLine.innerHTML = `<span class="prompt">damo@portfolio:~$ </span>${command}`;
    this.output.appendChild(commandLine);
  }

  showPrompt() {
    this.inputLine.style.display = "";
    setTimeout(() => this.input.focus(), 0);
  }

  handleKeyDown(e) {
    if (e.key === "Enter") {
      e.preventDefault();
      const command = this.input.value.trim();

      if (command) {
        this.executeCommand(command);
        this.commandHistory.unshift(command);
        this.historyIndex = -1;
      }

      this.input.value = "";
    } else if (e.key === "ArrowUp") {
      e.preventDefault();
      this.navigateHistory("up");
    } else if (e.key === "ArrowDown") {
      e.preventDefault();
      this.navigateHistory("down");
    } else if (e.key === "Tab") {
      e.preventDefault();
      this.handleTabCompletion();
    }
  }

  handleKeyUp(e) {
    // Keep cursor focused
    this.input.focus();

    // Clear any visible completion options when user types
    if (
      e.key !== "Tab" &&
      e.key !== "ArrowUp" &&
      e.key !== "ArrowDown" &&
      e.key !== "Enter"
    ) {
      this.clearCompletionOptions();
    }
  }

  navigateHistory(direction) {
    if (this.commandHistory.length === 0) return;

    if (direction === "up") {
      if (this.historyIndex < this.commandHistory.length - 1) {
        this.historyIndex++;
        this.input.value = this.commandHistory[this.historyIndex];
      }
    } else if (direction === "down") {
      if (this.historyIndex > 0) {
        this.historyIndex--;
        this.input.value = this.commandHistory[this.historyIndex];
      } else if (this.historyIndex === 0) {
        this.historyIndex = -1;
        this.input.value = "";
      }
    }
  }

  async handleTabCompletion() {
    const currentInput = this.input.value;
    const cursorPosition = this.input.selectionStart;

    // Get the current word being typed (from cursor back to last space or start)
    const beforeCursor = currentInput.substring(0, cursorPosition);
    const lastSpaceIndex = beforeCursor.lastIndexOf(" ");
    const currentWord =
      lastSpaceIndex === -1
        ? beforeCursor
        : beforeCursor.substring(lastSpaceIndex + 1);

    if (!currentWord) return;

    try {
      // Determine completion type based on position
      const isFirstWord = lastSpaceIndex === -1;
      let completionCommand;

      if (isFirstWord) {
        // Complete commands
        completionCommand = `compgen -c "${currentWord}"`;
      } else {
        // Complete files/directories
        const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
        completionCommand = `compgen -f "${currentWord}"`;
      }

      const response = await fetch("/execute", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ command: completionCommand }),
      });

      if (response.ok) {
        const data = await response.json();
        // Filter out duplicates and empty lines
        let completions = [
          ...new Set(
            data.stdout
              .trim()
              .split("\n")
              .filter((line) => line.trim()),
          ),
        ];

        // For first word completion, add custom portfolio commands that match
        if (isFirstWord && this.availableCommands) {
          const matchingCustomCommands = this.availableCommands.filter(cmd =>
            cmd.startsWith(currentWord) && !completions.includes(cmd)
          );
          completions = [...completions, ...matchingCustomCommands];
        }

        if (completions.length === 0) {
          // No completions found
          return;
        }

        if (completions.length === 1) {
          // Single completion - auto-complete
          const completion = completions[0];
          if (isFirstWord) {
            this.input.value = completion + " ";
          } else {
            const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
            this.input.value = prefix + completion + " ";
          }
          // Reset cursor to end
          this.input.setSelectionRange(
            this.input.value.length,
            this.input.value.length,
          );
        } else {
          // Multiple completions - show options
          const maxCompletions = 10;
          let displayCompletions = completions.slice(0, maxCompletions);
          let overflowMessage = "";

          if (completions.length > maxCompletions) {
            displayCompletions = completions.slice(0, maxCompletions);
            overflowMessage = `... and ${completions.length - maxCompletions} more`;
          }

          // Show completions below the prompt
          const completionDiv = document.createElement("div");
          completionDiv.innerHTML = `<div>${displayCompletions.join("  ")}${overflowMessage ? "  " + overflowMessage : ""}</div>`;
          this.completionContainer.appendChild(completionDiv);

          // Find common prefix for partial completion
          if (displayCompletions.length > 1) {
            const commonPrefix = this.findCommonPrefix(displayCompletions);
            if (commonPrefix.length > currentWord.length) {
              // Partial completion possible
              if (isFirstWord) {
                this.input.value = commonPrefix;
              } else {
                const prefix = beforeCursor.substring(0, lastSpaceIndex + 1);
                this.input.value = prefix + commonPrefix;
              }
              // Set cursor to end of completed part
              this.input.setSelectionRange(
                this.input.value.length,
                this.input.value.length,
              );
            }
          }
        }
      }
    } catch (error) {
      console.error("Tab completion error:", error);
    }
  }

  findCommonPrefix(strings) {
    if (strings.length === 0) return "";
    if (strings.length === 1) return strings[0];

    let prefix = strings[0];
    for (let i = 1; i < strings.length; i++) {
      while (strings[i].indexOf(prefix) !== 0) {
        prefix = prefix.substring(0, prefix.length - 1);
        if (prefix === "") return "";
      }
    }
    return prefix;
  }

  clearCompletionOptions() {
    this.completionContainer.innerHTML = "";
  }

  executeCommand(command) {
    this.showCommand(command);
    this.inputLine.style.display = "none";

    // Handle special commands
    if (command === "clear") {
      this.clearTerminal();
      return;
    }

    // Handle projects subcommands
    if (command.startsWith("projects ")) {
      const parts = command.split(" ");
      if (parts.length === 2) {
        const subcommand = parts[1];
        this.loadProjectSubcommand(subcommand);
        return;
      }
    }

    // Load command from commands directory
    this.loadCommand(command);
  }

  async loadProjectSubcommand(subcommand) {
    const validSubcommands = ["rubiks", "uttt", "mandelbrot"];

    if (validSubcommands.includes(subcommand)) {
      try {
        // Load HTML content from commands directory
        const htmlResponse = await fetch(`/commands/${subcommand}.html`);
        if (htmlResponse.ok) {
          const htmlContent = await htmlResponse.text();
          const commandOutput = document.createElement("div");
          commandOutput.innerHTML = htmlContent;
          this.output.appendChild(commandOutput);
        } else {
          const errorOutput = document.createElement("div");
          errorOutput.innerHTML = `<p class="output">Error loading project: ${subcommand}</p>`;
          this.output.appendChild(errorOutput);
        }
      } catch (error) {
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">Error loading project: ${error.message}</p>`;
        this.output.appendChild(errorOutput);
      }
    } else {
      const errorOutput = document.createElement("div");
      errorOutput.innerHTML = `<p class="output">Unknown project: ${subcommand}. Available projects: rubiks, uttt, mandelbrot</p>`;
      this.output.appendChild(errorOutput);
    }

    // Show prompt again after command execution
    setTimeout(() => {
      this.showPrompt();
      this.scrollToBottom();
    }, 100);
  }

  async loadCommand(command) {
    // Check if command is available in the commands directory
    if (this.availableCommands.includes(command)) {
      try {
        // Load HTML content from commands directory
        const htmlResponse = await fetch(`/commands/${command}.html`);
        if (htmlResponse.ok) {
          const htmlContent = await htmlResponse.text();
          const commandOutput = document.createElement("div");
          commandOutput.innerHTML = htmlContent;
          this.output.appendChild(commandOutput);
        } else {
          // This shouldn't happen if the command is in availableCommands, but fallback just in case
          const errorOutput = document.createElement("div");
          errorOutput.innerHTML = `<p class="output">Error loading command: ${command}</p>`;
          this.output.appendChild(errorOutput);
        }
      } catch (error) {
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">Error loading command: ${error.message}</p>`;
        this.output.appendChild(errorOutput);
      }
    } else {
      // Command not in available commands - try executing as shell command
      try {
        const response = await fetch("/execute", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ command: command }),
        });

        if (response.ok) {
          const data = await response.json();
          const commandOutput = document.createElement("div");

          if (data.stdout) {
            commandOutput.innerHTML = `<pre class="output">${data.stdout}</pre>`;
          }

          if (data.stderr) {
            const stderrDiv = document.createElement("div");
            stderrDiv.innerHTML = `<pre class="output error">${data.stderr}</pre>`;
            commandOutput.appendChild(stderrDiv);
          }

          this.output.appendChild(commandOutput);
        } else {
          // Command not found or error
          const errorOutput = document.createElement("div");
          errorOutput.innerHTML = `<p class="output">bash: ${command}: command not found</p>`;
          this.output.appendChild(errorOutput);
        }
      } catch (error) {
        const errorOutput = document.createElement("div");
        errorOutput.innerHTML = `<p class="output">Error executing command: ${error.message}</p>`;
        this.output.appendChild(errorOutput);
      }
    }

    // Show prompt again after command execution
    setTimeout(() => {
      this.showPrompt();
      this.scrollToBottom();
    }, 100);
  }

  clearTerminal() {
    this.output.innerHTML = "";
    setTimeout(() => {
      this.showPrompt();
    }, 100);
  }

  scrollToBottom() {
    window.scrollTo(0, document.body.scrollHeight);
  }
}

// Initialize terminal when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
  new Terminal();
});
