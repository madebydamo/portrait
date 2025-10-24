// Input handling methods for Terminal class

Terminal.prototype.setupPermanentFocus = function() {
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
    // Do not focus if clicking on a clickable command
    if (e.target.classList.contains("clickable-command")) {
      return;
    }
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
    // Allow interaction with clickable commands
    if (e.target.classList.contains("clickable-command")) {
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
};

Terminal.prototype.handleKeyDown = function(e) {
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
};

Terminal.prototype.handleKeyUp = function(e) {
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
};

Terminal.prototype.navigateHistory = function(direction) {
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
};