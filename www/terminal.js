class Terminal {
  constructor() {
    this.output = document.getElementById("output");
    this.input = document.getElementById("command-input");
    this.inputLine = document.getElementById("input-line");
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
    document.addEventListener('click', (e) => {
      if (e.target.classList.contains('clickable-command')) {
        const command = e.target.getAttribute('data-command');
        if (command) {
          this.executeClickableCommand(command);
        }
      }
    });
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
    this.input.focus();
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
    }
  }

  handleKeyUp(e) {
    // Keep cursor focused
    this.input.focus();
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
