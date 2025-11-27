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
    // Fetch available commands first
    try {
      const response = await fetch("/commands");
      if (response.ok) {
        this.availableCommands = await response.json();
      }
    } catch (error) {
      console.error("Failed to fetch available commands:", error);
    }

    // Start with intro animation
    this.startIntroAnimation();

    // Set up input handling
    this.input.addEventListener("keydown", (e) => this.handleKeyDown(e));
    this.input.addEventListener("keyup", (e) => this.handleKeyUp(e));

    document.addEventListener("keydown", (e) => this.globalKeyDown(e));

    // Set up clickable command functionality
    this.setupClickableCommands();

    // Initialize inactivity timer
    this.initInactivityTimer();

    // Add click handler to input line to focus input
    this.inputLine.addEventListener("click", () => this.input.focus());
  }

  showPrompt() {
    this.inputLine.style.display = "";
  }

  scrollToBottom() {
    const prompts = document.querySelectorAll('.prompt');
    const targetPrompt = prompts[prompts.length - 2]; // Second to last prompt (last command's prompt)
    if (!targetPrompt) {
      // Fallback if no previous prompt
      window.scrollTo(0, document.body.scrollHeight);
      return;
    }
    const targetTop = targetPrompt.offsetTop;
    const viewportHeight = window.innerHeight;
    const bodyHeight = document.body.scrollHeight;

    if (targetTop + viewportHeight > bodyHeight) {
      // Scrolling target to top would leave space below, so scroll to bottom
      window.scrollTo(0, bodyHeight);
    } else {
      // Scroll to bring target to top
      window.scrollTo(0, targetTop);
    }
  }

  globalKeyDown(e) {
    if (this.inputLine.style.display === "none") return;
    if (document.activeElement === this.input) return;
    if (document.activeElement.tagName === "TEXTAREA") return;

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
  window.terminal = new Terminal();
});
