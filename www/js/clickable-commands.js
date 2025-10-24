// Clickable commands methods for Terminal class

Terminal.prototype.setupClickableCommands = function() {
  // Add event listeners for clickable commands
  document.addEventListener("click", (e) => {
    if (e.target.classList.contains("clickable-command")) {
      const command = e.target.getAttribute("data-command");
      if (command) {
        this.executeClickableCommand(command);
      }
    }
  });
};