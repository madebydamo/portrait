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

    window.addEventListener("scroll", () => this.handleScroll());
    document.addEventListener("keydown", (e) => this.globalKeyDown(e));

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
  }

  scrollToBottom() {
    window.scrollTo(0, document.body.scrollHeight);
  }

  handleScroll() {
    const threshold = 10;
    const atBottom =
      window.innerHeight + window.scrollY >=
      document.body.scrollHeight - threshold;
    if (this.inputLine.style.display !== "none") {
      if (atBottom) {
        this.input.focus();
      } else {
        this.input.blur();
      }
    }
  }

  globalKeyDown(e) {
    if (this.inputLine.style.display === "none") return;
    if (document.activeElement === this.input) return;

    e.preventDefault();
    e.stopPropagation();

    const input = this.input;
    input.focus();

    const start = input.selectionStart ?? 0;
    const end = input.selectionEnd ?? 0;
    let value = input.value;
    let newStart = start;
    let newEnd = end;

    if (start !== end) {
      value = value.slice(0, start) + value.slice(end);
      newStart = start;
      newEnd = start;
    }

    const key = e.key;

    if (key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey) {
      value = value.slice(0, newStart) + key + value.slice(newStart);
      newStart += 1;
      newEnd = newStart;
    } else if (key === "Backspace") {
      if (newStart > 0) {
        value = value.slice(0, newStart - 1) + value.slice(newStart);
        newStart -= 1;
        newEnd = newStart;
      }
    } else if (key === "Delete") {
      value = value.slice(0, newStart) + value.slice(newStart + 1);
    } else if (key === "ArrowLeft") {
      newStart = Math.max(0, newStart - 1);
      newEnd = newStart;
    } else if (key === "ArrowRight") {
      newStart = Math.min(value.length, newStart + 1);
      newEnd = newStart;
    } else if (key === "Home") {
      newStart = 0;
      newEnd = 0;
    } else if (key === "End") {
      newStart = value.length;
      newEnd = newStart;
    }

    input.value = value;
    input.setSelectionRange(newStart, newEnd);

    const fakeEvent = {
      key: key,
      preventDefault: () => {},
      stopPropagation: () => {},
    };
    this.handleKeyDown(fakeEvent);
    this.handleKeyUp(fakeEvent);
  }
}

// Initialize terminal when DOM is loaded
document.addEventListener("DOMContentLoaded", () => {
  new Terminal();
});
