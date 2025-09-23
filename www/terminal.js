class Terminal {
  constructor() {
    this.output = document.getElementById('output');
    this.input = document.getElementById('command-input');
    this.inputLine = document.getElementById('input-line');
    this.commandHistory = [];
    this.historyIndex = -1;
    
    this.init();
  }

  init() {
    // Start with intro animation
    this.startIntroAnimation();
    
    // Set up input handling
    this.input.addEventListener('keydown', (e) => this.handleKeyDown(e));
    this.input.addEventListener('keyup', (e) => this.handleKeyUp(e));
  }

  startIntroAnimation() {
    const introText = [
      "Welcome to Damian's Portfolio Terminal",
      "Initializing secure connection...",
      "Connection established.",
      "",
      "Type 'help' to see available commands."
    ];

    new Typed('#typed-intro', {
      strings: introText,
      typeSpeed: 50,
      backSpeed: 0,
      fadeOut: false,
      loop: false,
      showCursor: true,
      cursorChar: '_',
      onComplete: () => {
        // Show help command automatically after intro
        setTimeout(() => {
          this.showCommand('help');
          setTimeout(() => {
            this.loadCommand('help');
          }, 500);
        }, 1000);
      }
    });
  }

  showCommand(command) {
    const commandLine = document.createElement('div');
    commandLine.innerHTML = `<span class="prompt">damian@portfolio:~$ </span>${command}`;
    this.output.appendChild(commandLine);
  }

  showPrompt() {
    this.inputLine.style.display = 'block';
    this.input.focus();
  }

  handleKeyDown(e) {
    if (e.key === 'Enter') {
      e.preventDefault();
      const command = this.input.value.trim();
      
      if (command) {
        this.executeCommand(command);
        this.commandHistory.unshift(command);
        this.historyIndex = -1;
      }
      
      this.input.value = '';
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      this.navigateHistory('up');
    } else if (e.key === 'ArrowDown') {
      e.preventDefault();
      this.navigateHistory('down');
    }
  }

  handleKeyUp(e) {
    // Keep cursor focused
    this.input.focus();
  }

  navigateHistory(direction) {
    if (this.commandHistory.length === 0) return;

    if (direction === 'up') {
      if (this.historyIndex < this.commandHistory.length - 1) {
        this.historyIndex++;
        this.input.value = this.commandHistory[this.historyIndex];
      }
    } else if (direction === 'down') {
      if (this.historyIndex > 0) {
        this.historyIndex--;
        this.input.value = this.commandHistory[this.historyIndex];
      } else if (this.historyIndex === 0) {
        this.historyIndex = -1;
        this.input.value = '';
      }
    }
  }

  executeCommand(command) {
    this.showCommand(command);
    this.inputLine.style.display = 'none';
    
    // Handle special commands
    if (command === 'clear') {
      this.clearTerminal();
      return;
    }
    
    // Load command from commands directory
    this.loadCommand(command);
  }

  async loadCommand(command) {
    try {
      const response = await fetch(`commands/${command}.html`);
      
      if (response.ok) {
        const html = await response.text();
        const commandOutput = document.createElement('div');
        commandOutput.innerHTML = html;
        this.output.appendChild(commandOutput);
      } else {
        // Command not found
        const errorOutput = document.createElement('div');
        errorOutput.innerHTML = `<p class="output">bash: ${command}: command not found</p>`;
        this.output.appendChild(errorOutput);
      }
    } catch (error) {
      const errorOutput = document.createElement('div');
      errorOutput.innerHTML = `<p class="output">Error loading command: ${error.message}</p>`;
      this.output.appendChild(errorOutput);
    }

    // Show prompt again after command execution
    setTimeout(() => {
      this.showPrompt();
      this.scrollToBottom();
    }, 100);
  }

  clearTerminal() {
    this.output.innerHTML = '';
    setTimeout(() => {
      this.showPrompt();
    }, 100);
  }

  scrollToBottom() {
    window.scrollTo(0, document.body.scrollHeight);
  }
}

// Initialize terminal when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
  new Terminal();
});