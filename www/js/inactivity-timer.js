// Inactivity timer methods for Terminal class

Terminal.prototype.initInactivityTimer = function () {
  this.inactivityTimeout = null;
  this.inactivityDelay = 10000; // 10 seconds

  // Reset timer on any input activity
  this.input.addEventListener("input", () => this.resetInactivityTimer());
  this.input.addEventListener("keydown", () => this.resetInactivityTimer());
  this.input.addEventListener("keyup", () => this.resetInactivityTimer());

  // Start the timer initially
  this.resetInactivityTimer();
};

Terminal.prototype.resetInactivityTimer = function () {
  // Only start timer if input is visible
  if (this.inputLine.style.display === "none") return;

  // Clear existing timeout
  if (this.inactivityTimeout) {
    clearTimeout(this.inactivityTimeout);
  }

  // Clear any existing inactivity message
  this.clearInactivityMessage();

  // Start new timeout
  this.inactivityTimeout = setTimeout(() => {
    this.showInactivityMessage();
  }, this.inactivityDelay);
};

Terminal.prototype.showInactivityMessage = function () {
  // Clear any completion options first
  this.clearCompletionOptions();

  // Show the help message
  const messageDiv = document.createElement("div");
  messageDiv.id = "inactivity-message";
  messageDiv.innerHTML =
    'Type <a class="clickable-command" href="/commands/help.html" data-command="help">help</a> to see the available commands';
  this.completionContainer.appendChild(messageDiv);
};

Terminal.prototype.clearInactivityMessage = function () {
  const messageElement = document.getElementById("inactivity-message");
  if (messageElement) {
    messageElement.remove();
  }
};
