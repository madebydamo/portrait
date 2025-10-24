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

  showPrompt() {
    this.inputLine.style.display = "";
    setTimeout(() => this.input.focus(), 0);
  }

  scrollToBottom() {
    window.scrollTo(0, document.body.scrollHeight);
  }
}

// Initialize terminal when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
  new Terminal();
});