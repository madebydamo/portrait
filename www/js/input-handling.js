// Input handling methods for Terminal class



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